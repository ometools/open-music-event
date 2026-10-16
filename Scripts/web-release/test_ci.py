"""Exercise CI orchestration with a fake Docker CLI, without compiling or deploying."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

SCRIPTS = Path(__file__).resolve().parent


class CIInvocationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        scripts = self.root / "Scripts/web-release"
        scripts.mkdir(parents=True)
        for name in ("ci.sh", "resources.py", "Dockerfile"):
            shutil.copyfile(SCRIPTS / name, scripts / name)
        (self.root / "Package.swift").write_text("fixture manifest\n")
        (self.root / "Package.resolved").write_text("fixture lockfile\n")
        self.bin = self.root / "bin"
        self.bin.mkdir()
        docker = self.bin / "docker"
        docker.write_text("""#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
args = sys.argv[1:]
with open(os.environ["DOCKER_CALLS"], "a") as log:
    log.write(json.dumps(args) + "\\n")
if args[0] == "run":
    mounts = {}
    for i, arg in enumerate(args):
        if arg == "--mount":
            fields = dict(part.split("=", 1) for part in args[i+1].split(",") if "=" in part)
            mounts[fields["dst"]] = Path(fields["src"])
    assert mounts["/root/.netrc"].read_text().endswith("password fixture-token\\n")
    if os.environ.get("FAIL_CONTAINER") == "1":
        sys.exit(17)
    output = mounts["/output"]
    if args[-1] == "pr":
        for name in ("tests.xml", "phases.tsv", "smoke.log"):
            (output / name).write_text("passed")
    else:
        (output / "passed").mkdir()
        for name in ("appview.tar.gz", "appview.tar.gz.sha256", "tests.xml", "verified-manifest.json"):
            (output / "passed" / name).write_text("validated release")
""")
        docker.chmod(0o755)
        self.log = self.root / "docker.jsonl"
        self.environment = {
            **os.environ,
            "PATH": str(self.bin) + os.pathsep + os.environ["PATH"],
            "DOCKER_CALLS": str(self.log),
            "TANGLED_SHA": "a" * 40,
            "GITHUB_TOKEN": "fixture-token",
            "OME_SWIFT_JOBS": "1",
            "AWS_SECRET_ACCESS_KEY": "must-not-enter-build",
            "OME_PRODUCTION_SSH_KEY": "must-not-enter-build",
        }

    def run_ci(self, *arguments):
        return subprocess.run(
            ["bash", str(self.root / "Scripts/web-release/ci.sh"), *arguments],
            env=self.environment, capture_output=True, text=True,
        )

    def calls(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()]

    def mount(self, command, destination):
        return next(
            command[i + 1] for i, arg in enumerate(command[:-1])
            if arg == "--mount" and f"dst={destination}" in command[i + 1]
        )

    def test_pr_only_exports_reports_and_cleans_up_the_dependency_credential(self):
        result = self.run_ci("pr")
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = self.calls()
        build = next(call for call in calls if call[0] == "buildx")
        self.assertEqual(build[build.index("--target") + 1], "toolchain")
        run = next(call for call in calls if call[0] == "run")
        self.assertEqual(run[-3:], ["bash", "Scripts/web-release/build.sh", "pr"])
        self.assertTrue(self.mount(run, "/src").endswith(",readonly"))
        self.assertIn("/.cache/web-ci/pr/", self.mount(run, "/src/.build"))
        forwarded = [run[i + 1] for i, arg in enumerate(run[:-1]) if arg == "--env"]
        self.assertEqual(set(forwarded), {
            "OME_RELEASE_REVISION=" + "a" * 40, "OME_SWIFT_JOBS=1",
            f"OME_CI_OWNER={os.getuid()}:{os.getgid()}",
        })
        secret_mount = self.mount(run, "/root/.netrc")
        secret = next(part[4:] for part in secret_mount.split(",") if part.startswith("src="))
        self.assertFalse(Path(secret).exists())
        self.assertEqual(
            {path.name for path in (self.root / ".build/web-pr").iterdir()},
            {"tests.xml", "phases.tsv", "smoke.log"},
        )
        self.assertFalse((self.root / ".build/web-release").exists())
        self.assertNotIn("fixture-token", result.stdout + result.stderr)

    def test_default_release_mode_exports_the_validated_artifact_with_a_separate_cache(self):
        result = self.run_ci()
        self.assertEqual(result.returncode, 0, result.stderr)
        run = next(call for call in self.calls() if call[0] == "run")
        self.assertEqual(run[-1], "release")
        self.assertIn("/.cache/web-ci/release/", self.mount(run, "/src/.build"))
        self.assertEqual(
            (self.root / ".build/web-release/appview.tar.gz").read_text(),
            "validated release",
        )

    def test_changed_lockfile_uses_a_different_cache_directory(self):
        self.assertEqual(self.run_ci("pr").returncode, 0)
        (self.root / "Package.resolved").write_text("updated lockfile\n")
        self.assertEqual(self.run_ci("pr").returncode, 0)
        runs = [call for call in self.calls() if call[0] == "run"]
        self.assertNotEqual(self.mount(runs[0], "/src/.build"), self.mount(runs[1], "/src/.build"))

    def test_failed_container_does_not_publish_reports_or_artifacts(self):
        self.environment["FAIL_CONTAINER"] = "1"
        result = self.run_ci("pr")
        self.assertEqual(result.returncode, 17)
        self.assertFalse((self.root / ".build/web-pr").exists())
        self.assertFalse((self.root / ".build/web-release").exists())
        run = next(call for call in self.calls() if call[0] == "run")
        secret = next(
            part[4:] for part in self.mount(run, "/root/.netrc").split(",")
            if part.startswith("src=")
        )
        self.assertFalse(Path(secret).exists())

    def test_invalid_mode_stops_before_docker_or_credentials_are_used(self):
        result = self.run_ci("production")
        self.assertEqual(result.returncode, 2)
        self.assertFalse(self.log.exists())
