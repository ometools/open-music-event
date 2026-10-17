import contextlib
import io
import json
import os
import shlex
from pathlib import Path
import subprocess
import sys
import tarfile
import tempfile
import unittest
from unittest.mock import patch

import artifact
import install
import pipeline


class ArtifactTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.executable = self.bin / "OpenMusicEventAppView"
        self.executable.write_bytes(b"\x7fELF\x02\x01" + bytes(12) + b"\x3e\x00" + b"fixture")
        site = self.bin / "open_music_event_OpenMusicEventAppViewServer.resources/Site"
        site.mkdir(parents=True)
        (site / "index.html").write_text("globe")
        self.lock = self.root / "Package.resolved"
        self.lock.write_text('{"pins": []}\n')
        self.library = self.root / "libswiftCore.so"
        self.library.write_bytes(b"runtime fixture")
        self.revision = "a" * 40

    def package(self, name="output"):
        return artifact.package(self.bin, [self.library], self.lock, self.revision,
                                "swift@example-digest", self.root / name)

    def test_archive_is_identical_when_file_timestamps_change(self):
        first = self.package("first")
        for path in self.bin.rglob("*"):
            os.utime(path, (12345, 12345))
        second = self.package("second")
        self.assertEqual((first.parent / "appview.tar.gz").read_bytes(),
                         (second.parent / "appview.tar.gz").read_bytes())
        self.assertEqual(artifact.verify(first), artifact.verify(second))

    def test_extracted_archive_keeps_runtime_resources_and_identity(self):
        release = self.package()
        extracted = self.root / "extracted"
        extracted.mkdir()
        install.extract(release.parent / "appview.tar.gz", extracted)
        manifest = artifact.verify(extracted)
        self.assertEqual(manifest["sourceRevision"], self.revision)
        self.assertEqual((extracted / "lib/libswiftCore.so").read_bytes(), b"runtime fixture")
        identity = json.loads(next(extracted.glob("*.resources/Site/assets/release.json")).read_text())
        self.assertEqual(identity["executableSHA256"], artifact.digest(self.executable))
        self.assertEqual(identity["lockfileSHA256"], artifact.digest(self.lock))

    def test_changed_binary_resources_or_library_fail_verification(self):
        release = self.package()
        for filename in ("OpenMusicEventAppView", "lib/libswiftCore.so",
                         "open_music_event_OpenMusicEventAppViewServer.resources/Site/index.html"):
            path = release / filename
            original = path.read_bytes()
            path.write_bytes(b"changed")
            with self.assertRaisesRegex(ValueError, "changed"):
                artifact.verify(release)
            path.write_bytes(original)

    def test_missing_extra_or_nonexecutable_files_fail_verification(self):
        release = self.package()
        extra = release / "unexpected.env"
        extra.write_text("not a release input")
        with self.assertRaisesRegex(ValueError, "file list"):
            artifact.verify(release)
        extra.unlink()
        (release / "run").chmod(0o644)
        with self.assertRaisesRegex(ValueError, "mode changed"):
            artifact.verify(release)

    def test_arm_binary_cannot_be_packaged_for_staging(self):
        self.executable.write_bytes(b"\x7fELF\x02\x01" + bytes(12) + b"\xb7\x00")
        with self.assertRaisesRegex(ValueError, "x86-64"):
            self.package()

    def test_missing_bundle_cannot_be_packaged(self):
        self.executable.rename(self.root / "OpenMusicEventAppView")
        with self.assertRaisesRegex(ValueError, "resource bundle"):
            artifact.package(self.root, [], self.lock, self.revision, "swift", self.root / "out")

    def test_archive_rejects_traversal_and_links_before_extracting(self):
        for name, kind in (("../escaped", tarfile.REGTYPE), ("/escaped", tarfile.REGTYPE),
                           ("link", tarfile.SYMTYPE)):
            archive = self.root / "unsafe.tar.gz"
            with tarfile.open(archive, "w:gz") as tar:
                member = tarfile.TarInfo(name)
                member.type = kind
                member.linkname = "/etc"
                tar.addfile(member)
            destination = self.root / "unsafe"
            with self.assertRaisesRegex(ValueError, "unsafe"):
                install.extract(archive, destination)
            self.assertFalse(destination.exists())


class PromotionTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.revision = "a" * 40
        self.archive = b"exact staged artifact bytes"
        self.digest = pipeline.hashlib.sha256(self.archive).hexdigest()
        self.candidate = {
            "sourceRevision": self.revision,
            "artifactSHA256": self.digest,
            "artifactKey": f"server/artifacts/{self.digest}.tar.gz",
        }
        self.tests = b'<testsuite><testcase name="web"/></testsuite>'
        self.manifest = json.dumps({"sourceRevision": self.revision}).encode()
        self.candidate["testReportSHA256"] = pipeline.hashlib.sha256(self.tests).hexdigest()
        self.candidate["manifestSHA256"] = pipeline.hashlib.sha256(self.manifest).hexdigest()
        self.receipt = {
            "sourceRevision": self.revision, "artifactSHA256": self.digest,
            "environment": "staging", "result": "passed",
        }
        self.objects = {
            pipeline.candidate_key(self.revision): json.dumps(self.candidate).encode(),
            f"server/releases/{self.revision}/staging.json": json.dumps(self.receipt).encode(),
            self.candidate["artifactKey"]: self.archive,
            f"server/releases/{self.revision}/tests.xml": self.tests,
            f"server/releases/{self.revision}/verified-manifest.json": self.manifest,
        }
        objects = self.objects
        class Store:
            def get(self, key, path, optional=False):
                if key not in objects:
                    if optional:
                        return False
                    raise ValueError("Missing release evidence")
                path.write_bytes(objects[key])
                return True
            def put_once(self, key, path):
                if key in objects and objects[key] != path.read_bytes():
                    raise ValueError("Immutable object changed")
                objects[key] = path.read_bytes()
        self.addCleanup(patch.stopall)
        patch("pipeline.ReleaseStore", Store).start()
        patch.dict(os.environ, {
            "GITHUB_SHA": self.revision, "GITHUB_EVENT_NAME": "workflow_dispatch",
            "GITHUB_REF": "refs/heads/main",
            "GITHUB_REPOSITORY": "ometools/open-music-event",
        }, clear=True).start()
        patch.object(sys, "argv", ["pipeline.py", "promote", "--revision", self.revision]).start()

    def test_promotion_downloads_the_exact_staged_bytes_without_any_build(self):
        with patch("pipeline.command", side_effect=AssertionError("Promotion must not build")), \
                patch("pipeline.deploy") as deploy, contextlib.redirect_stdout(io.StringIO()):
            def check(candidate, archive, environment):
                self.assertEqual(archive.read_bytes(), self.archive)
                self.assertEqual(candidate["artifactSHA256"], self.digest)
                self.assertEqual(environment, "production")
            deploy.side_effect = check
            pipeline.main()
            deploy.assert_called_once()
        self.assertIn(f"server/releases/{self.revision}/production.json", self.objects)

    def test_promotion_uses_selected_staged_revision_instead_of_workflow_head(self):
        os.environ["GITHUB_SHA"] = "b" * 40
        with patch("pipeline.deploy") as deploy, contextlib.redirect_stdout(io.StringIO()):
            pipeline.main()
        self.assertEqual(deploy.call_args.args[0]["sourceRevision"], self.revision)

    def test_promotion_requires_an_explicit_full_commit(self):
        for arguments in (["promote"], ["promote", "--revision", "main"],
                          ["promote", "--revision", "../candidate"]):
            with self.subTest(arguments=arguments), patch.object(sys, "argv", ["pipeline.py", *arguments]):
                self.assert_stopped()

    def test_another_repository_cannot_deploy(self):
        os.environ["GITHUB_REPOSITORY"] = "someone/ome-fork"
        self.assert_stopped()

    def test_missing_staging_proof_stops_before_deployment(self):
        del self.objects[f"server/releases/{self.revision}/staging.json"]
        self.assert_stopped()

    def test_another_artifacts_staging_proof_cannot_approve_this_artifact(self):
        self.receipt["artifactSHA256"] = "b" * 64
        self.objects[f"server/releases/{self.revision}/staging.json"] = json.dumps(self.receipt).encode()
        self.assert_stopped()

    def test_changed_stored_artifact_stops_before_deployment(self):
        self.objects[self.candidate["artifactKey"]] = b"corrupted"
        self.assert_stopped()

    def test_push_and_pull_request_cannot_promote_to_production(self):
        for kind in ("push", "pull_request"):
            os.environ["GITHUB_EVENT_NAME"] = kind
            self.assert_stopped()

    def test_manual_feature_branch_cannot_promote(self):
        os.environ["GITHUB_REF"] = "refs/heads/experiment"
        self.assert_stopped()

    def test_failed_host_validation_never_writes_production_receipt(self):
        with patch("pipeline.deploy", side_effect=ValueError("Smoke failed")), \
                contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
            pipeline.main()
        self.assertNotIn(f"server/releases/{self.revision}/production.json", self.objects)


    def test_pipeline_retry_reuses_original_artifact_and_test_evidence(self):
        os.environ["GITHUB_EVENT_NAME"] = "push"
        with patch.object(sys, "argv", ["pipeline.py", "build"]), patch("pipeline.ROOT", self.root), \
                patch("pipeline.command", side_effect=AssertionError("Retry must not rebuild")), \
                contextlib.redirect_stdout(io.StringIO()):
            pipeline.main()
        output = self.root / ".build/web-release"
        self.assertEqual((output / "appview.tar.gz").read_bytes(), self.archive)
        self.assertEqual((output / "tests.xml").read_bytes(), self.tests)

    def test_new_revision_runs_the_build_gate(self):
        os.environ["GITHUB_EVENT_NAME"] = "push"
        del self.objects[pipeline.candidate_key(self.revision)]
        with patch.object(sys, "argv", ["pipeline.py", "build"]), patch("pipeline.command") as command:
            pipeline.main()
            command.assert_called_once_with("bash", str(pipeline.ROOT / "Scripts/web-release/ci.sh"), cwd=pipeline.ROOT)

    def test_changed_stored_test_evidence_cannot_be_repaired_by_rebuilding(self):
        os.environ["GITHUB_EVENT_NAME"] = "push"
        self.objects[f"server/releases/{self.revision}/tests.xml"] = b"changed report"
        with patch.object(sys, "argv", ["pipeline.py", "build"]), patch("pipeline.ROOT", self.root), \
                patch("pipeline.command") as command, contextlib.redirect_stderr(io.StringIO()):
            with self.assertRaises(SystemExit):
                pipeline.main()
            command.assert_not_called()

    def test_stage_publishes_server_evidence_and_promotes_the_same_archive(self):
        # A fresh build contains the executable/site archive and its validation evidence.
        output = self.root / ".build/web-release"
        output.mkdir(parents=True)
        (output / "appview.tar.gz").write_bytes(self.archive)
        (output / "tests.xml").write_bytes(self.tests)
        (output / "verified-manifest.json").write_bytes(self.manifest)
        self.objects.clear()
        os.environ["GITHUB_EVENT_NAME"] = "push"

        def verify_deployed_bytes(candidate, archive, environment):
            self.assertEqual(archive.read_bytes(), self.archive)
            self.assertEqual(candidate["artifactKey"], f"server/artifacts/{self.digest}.tar.gz")

        with patch("pipeline.ROOT", self.root), \
                patch("pipeline.deploy", side_effect=verify_deployed_bytes) as deploy, \
                patch("pipeline.command", side_effect=AssertionError("Stored artifact must not rebuild")), \
                contextlib.redirect_stdout(io.StringIO()):
            with patch.object(sys, "argv", ["pipeline.py", "stage"]):
                pipeline.main()

            # Staging writes the complete server release contract.
            prefix = f"server/releases/{self.revision}"
            self.assertEqual(set(self.objects), {
                f"server/artifacts/{self.digest}.tar.gz",
                f"{prefix}/candidate.json",
                f"{prefix}/tests.xml",
                f"{prefix}/verified-manifest.json",
                f"{prefix}/staging.json",
            })
            self.assertEqual(deploy.call_args.args[2], "staging")
            candidate = json.loads(self.objects[f"{prefix}/candidate.json"])
            self.assertEqual(candidate, self.candidate)

            # Manual production approval consumes that exact candidate and staging receipt.
            os.environ["GITHUB_EVENT_NAME"] = "workflow_dispatch"
            with patch.object(sys, "argv", ["pipeline.py", "promote", "--revision", self.revision]):
                pipeline.main()
            self.assertEqual(deploy.call_count, 2)
            self.assertEqual(deploy.call_args.args[2], "production")
            production = json.loads(self.objects[f"{prefix}/production.json"])
            self.assertEqual(production["artifactSHA256"], self.digest)

    def assert_stopped(self):
        with patch("pipeline.deploy") as deploy, contextlib.redirect_stderr(io.StringIO()):
            with self.assertRaises(SystemExit) as result:
                pipeline.main()
            self.assertEqual(result.exception.code, 1)
            deploy.assert_not_called()


class ConfigurationTests(unittest.TestCase):
    def setUp(self):
        self.environment = {
            "GITHUB_SHA": "a" * 40,
            "GITHUB_EVENT_NAME": "push",
            "GITHUB_REF": "refs/heads/main",
            "GITHUB_REPOSITORY": "ometools/open-music-event",
            "OME_RELEASE_BUCKET": "openmusicevent-releases",
            "AWS_REGION": "us-west-2",
            "OME_DEPENDENCY_TOKEN": "fixture-token",
            "OME_STAGING_SSH_HOST": "stg.example.test",
            "OME_STAGING_SSH_USER": "deploy",
            "OME_STAGING_SERVICE": "ome-appview-canary.service",
            "OME_STAGING_DATABASE": "/srv/ome-appview/data/canary/appview.sqlite",
            "OME_STAGING_URL": "https://stg.example.test",
            "OME_STAGING_SSH_KEY": "fixture-key",
            "OME_STAGING_KNOWN_HOSTS": "fixture-host-key",
        }

    def test_preflight_and_store_accept_the_ome_release_bucket(self):
        with patch.dict(os.environ, self.environment, clear=True), \
                patch.object(sys, "argv", ["pipeline.py", "preflight"]), \
                contextlib.redirect_stdout(io.StringIO()), \
                patch("pipeline.subprocess.run", side_effect=AssertionError("Preflight must not deploy")):
            pipeline.main()
            self.assertEqual(pipeline.ReleaseStore().bucket, "openmusicevent-releases")

    def test_push_cannot_override_the_workflow_commit(self):
        with (
            patch.dict(os.environ, self.environment, clear=True),
            patch.object(sys, "argv", ["pipeline.py", "build", "--revision", "b" * 40]),
            patch("pipeline.ReleaseStore") as store,
            contextlib.redirect_stderr(io.StringIO()),
            self.assertRaises(SystemExit),
        ):
            pipeline.main()
        store.assert_not_called()

    def test_old_bucket_setting_does_not_satisfy_preflight(self):
        self.environment["OME_WEB_RELEASE_BUCKET"] = self.environment.pop("OME_RELEASE_BUCKET")
        stderr = io.StringIO()
        with patch.dict(os.environ, self.environment, clear=True), \
                patch.object(sys, "argv", ["pipeline.py", "preflight"]), \
                contextlib.redirect_stderr(stderr), self.assertRaises(SystemExit) as result:
            pipeline.main()
        self.assertEqual(result.exception.code, 1)
        self.assertIn("Missing CI settings: OME_RELEASE_BUCKET", stderr.getvalue())


class StoreTests(unittest.TestCase):
    @patch.dict(os.environ, {"OME_RELEASE_BUCKET": "example", "AWS_REGION": "us-west-2"})
    def test_existing_identical_object_is_idempotent_but_different_bytes_are_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "object"
            path.write_bytes(b"immutable")
            store = pipeline.ReleaseStore()
            result = subprocess.CompletedProcess([], 1, "", "(PreconditionFailed)")
            with patch("pipeline.subprocess.run", return_value=result):
                with patch.object(store, "get", side_effect=lambda key, output: output.write_bytes(b"immutable")):
                    store.put_once("candidate", path)
                with patch.object(store, "get", side_effect=lambda key, output: output.write_bytes(b"changed")):
                    with self.assertRaisesRegex(ValueError, "overwrite"):
                        store.put_once("candidate", path)


class HostInstallTests(unittest.TestCase):
    package = ArtifactTests.package

    def setUp(self):
        ArtifactTests.setUp(self)
        import sqlite3
        from types import SimpleNamespace
        release = self.package()
        self.archive = release.parent / "appview.tar.gz"
        self.sha = artifact.digest(self.archive)
        self.base = self.root / "host"
        (self.base / "releases").mkdir(parents=True)
        (self.base / "backups").mkdir()
        self.database = self.base / "data.sqlite"
        with contextlib.closing(sqlite3.connect(self.database)) as database:
            database.execute("CREATE TABLE user_data(value TEXT)")
            database.execute("INSERT INTO user_data VALUES ('keep this event')")
            database.commit()
        self.units = self.root / "systemd"
        self.dropin = self.units / "ome-appview-canary.service.d/50-ome-ci-release.conf"
        self.dropin.parent.mkdir(parents=True)
        self.dropin.write_text("[Service]\nExecStart=/previous/run\n")
        self.previous = self.dropin.read_bytes()
        self.calls = []
        self.bad_identity = False
        self.running = True
        self.wrong_executable = False
        self.property_overrides = {}
        self.http_calls = []
        self.args = SimpleNamespace(
            archive=self.archive, sha256=self.sha, revision=self.revision,
            service="ome-appview-canary.service", database=self.database,
            base_url="https://stg.example.test", smoke_script=self.root / "smoke.sh"
        )
        self.addCleanup(patch.stopall)
        patch("install.BASE", self.base).start()
        patch("install.UNIT_ROOT", self.units).start()
        patch("install.platform.system", return_value="Linux").start()
        patch("install.platform.machine", return_value="x86_64").start()
        patch("install.platform.freedesktop_os_release", return_value={"ID": "ubuntu", "VERSION_ID": "24.04"}).start()
        patch("install.os.geteuid", return_value=0).start()
        original_read = Path.read_bytes
        def read_bytes(path):
            if str(path) == "/proc/12345/environ":
                return ("OME_APPVIEW_DATABASE_PATH=" + str(self.database)).encode() + b"\0"
            return original_read(path)
        patch.object(Path, "read_bytes", read_bytes).start()
        original_resolve = Path.resolve
        def resolve(path, *args, **kwargs):
            if str(path) == "/proc/12345/exe":
                if self.wrong_executable:
                    return Path("/previous/OpenMusicEventAppView")
                return self.base / "releases" / self.sha / "OpenMusicEventAppView"
            return original_resolve(path, *args, **kwargs)
        patch.object(Path, "resolve", resolve).start()
        def run(*command, **kwargs):
            self.calls.append(command)
            if command[1:2] == ("show",):
                key = command[command.index("-p") + 1]
                environment = {"OME_APPVIEW_DATABASE_PATH": str(self.database)}
                properties = {"MainPID": "12345" if self.running else "0",
                              "ActiveState": "active" if self.running else "inactive",
                              "EnvironmentFiles": "", "UnsetEnvironment": ""}
                # The systemd boundary applies later drop-ins after the CI selection.
                for config in sorted(self.dropin.parent.glob("*.conf")):
                    for line in config.read_text().splitlines():
                        name, _, value = line.partition("=")
                        if name in ("ExecStart", "WorkingDirectory"):
                            properties[name] = value
                        elif name == "Environment":
                            environment.update(item.split("=", 1) for item in shlex.split(value))
                executable = properties.get("ExecStart", "/previous/run")
                properties["ExecStart"] = (f"{{ path={executable} ; argv[]={executable} ; "
                                           "ignore_errors=no ; pid=12345 ; code=(null) ; status=0/0 }")
                properties["Environment"] = shlex.join(f"{k}={v}" for k, v in environment.items())
                properties.update(self.property_overrides)
                return subprocess.CompletedProcess(command, 0, properties[key] + "\n")
            if command[1:2] == ("start",):
                self.running = True
            if command[1:2] == ("stop",):
                self.running = False
            if command[1:2] == ("cat",):
                return subprocess.CompletedProcess(command, 0, b"[Service]\n")
            return subprocess.CompletedProcess(command, 0, "")
        patch("install.run", side_effect=run).start()
        identity = next(release.glob("*.resources/Site/assets/release.json")).read_bytes()
        def urlopen(url, **kwargs):
            self.http_calls.append(url)
            body = b"ready" if url.endswith("/readyz") else (b"{}" if self.bad_identity else identity)
            response = io.BytesIO(body)
            response.status = 200
            return response
        patch("install.urllib.request.urlopen", side_effect=urlopen).start()

    def test_success_preserves_database_and_creates_verified_backup(self):
        import sqlite3
        install.install(self.args)
        backup = next((self.base / "backups").glob("*/appview.sqlite"))
        for path in (backup, self.database):
            with contextlib.closing(sqlite3.connect(path)) as database:
                self.assertEqual(database.execute("SELECT value FROM user_data").fetchall(), [("keep this event",)])
        installed = self.base / "releases" / self.sha
        self.assertEqual(installed.stat().st_mode & 0o777, 0o755)
        self.assertEqual(artifact.verify(installed)["sourceRevision"], self.revision)
        self.assertTrue(next((self.base / "backups").glob("*/result.json")).is_file())

    def test_wrong_public_release_stops_candidate_without_rolling_back_database(self):
        self.bad_identity = True
        with contextlib.redirect_stderr(io.StringIO()), self.assertRaisesRegex(ValueError, "Public host"):
            install.install(self.args)
        self.assertEqual(self.dropin.read_bytes(), self.previous)
        lifecycle = [c[1] for c in self.calls if c[:1] == ("systemctl",) and c[1] in ("start", "stop")]
        self.assertEqual(lifecycle, ["stop", "start", "stop"])
        self.assertTrue(self.database.exists())
        self.assertTrue(next((self.base / "backups").glob("*/appview.sqlite")).is_file())
        self.assertEqual(list((self.base / "backups").glob("*/result.json")), [])

    def test_legacy_override_cannot_start_the_previous_release(self):
        legacy = self.dropin.parent / "zzzzzz-proposals-portable.conf"
        legacy.write_text("[Service]\nExecStart=\nExecStart=/september/OpenMusicEventAppView\n")
        with self.assertRaisesRegex(ValueError, "ExecStart"):
            install.install(self.args)
        self.assertEqual(self.dropin.read_bytes(), self.previous)
        self.assertTrue(self.running)
        self.assertFalse(any(c[1] in ("stop", "start") for c in self.calls))
        self.assertEqual(self.http_calls, [])

    def test_stale_site_root_is_rejected_before_stopping(self):
        legacy = self.dropin.parent / "zzzzzz-proposals-portable.conf"
        legacy.write_text("[Service]\nEnvironment=OME_APPVIEW_SITE_ROOT=/september/Site\n")
        with self.assertRaisesRegex(ValueError, "OME_APPVIEW_SITE_ROOT"):
            install.install(self.args)
        self.assertTrue(self.running)
        self.assertFalse(any(c[1] in ("stop", "start") for c in self.calls))

    def test_working_directory_and_environment_removal_conflicts_fail_before_stopping(self):
        for key, value, message in (
            ("WorkingDirectory", "/september", "WorkingDirectory"),
            ("UnsetEnvironment", "OME_APPVIEW_SITE_ROOT", "UnsetEnvironment"),
        ):
            with self.subTest(setting=key):
                self.property_overrides = {key: value}
                with self.assertRaisesRegex(ValueError, message):
                    install.install(self.args)
                self.assertEqual(self.dropin.read_bytes(), self.previous)
                self.assertTrue(self.running)
                self.assertFalse(any(c[1] in ("stop", "start") for c in self.calls))

    def test_first_install_conflict_removes_only_the_new_ci_dropin(self):
        self.dropin.unlink()
        legacy = self.dropin.parent / "zzzzzz-proposals-portable.conf"
        contents = "[Service]\nExecStart=\nExecStart=/september/OpenMusicEventAppView\n"
        legacy.write_text(contents)
        with self.assertRaisesRegex(ValueError, "ExecStart"):
            install.install(self.args)
        self.assertFalse(self.dropin.exists())
        self.assertEqual(legacy.read_text(), contents)
        self.assertTrue(self.running)

    def test_environment_file_cannot_replace_release_paths(self):
        environment_file = self.root / "service.env"
        environment_file.write_text("OME_APPVIEW_SITE_ROOT=/september/Site\nTOKEN=must-not-log\n")
        self.property_overrides["EnvironmentFiles"] = f"{environment_file} (ignore_errors=no)"
        with self.assertRaisesRegex(ValueError, "EnvironmentFile") as error:
            install.install(self.args)
        self.assertNotIn("must-not-log", str(error.exception))
        self.assertTrue(self.running)

    def test_wrong_binary_fails_before_public_health_checks(self):
        self.wrong_executable = True
        with patch("install.time.sleep"), contextlib.redirect_stderr(io.StringIO()), \
                self.assertRaisesRegex(ValueError, "executable"):
            install.install(self.args)
        self.assertEqual(self.http_calls, [])
        self.assertFalse(self.running)

    def test_stopped_service_can_retry_with_verified_existing_database(self):
        self.running = False
        install.install(self.args)
        self.assertTrue(self.running)
        self.assertTrue(next((self.base / "backups").glob("*/appview.sqlite")).is_file())

    def test_stopped_service_rejects_a_different_database(self):
        self.running = False
        self.property_overrides["Environment"] = "OME_APPVIEW_DATABASE_PATH=/other.sqlite"
        with self.assertRaisesRegex(ValueError, "database"):
            install.install(self.args)
        self.assertFalse(any(c[1] in ("stop", "start") for c in self.calls))

    def test_failed_backup_restores_configuration_before_restarting_previous_service(self):
        with patch("install.sqlite3.connect", side_effect=OSError("Backup failed")), \
                self.assertRaisesRegex(OSError, "Backup failed"):
            install.install(self.args)
        self.assertEqual(self.dropin.read_bytes(), self.previous)
        self.assertTrue(self.running)
        self.assertEqual(self.calls[-2:], [("systemctl", "daemon-reload"),
                                          ("systemctl", "start", self.args.service)])

    def test_failed_backup_does_not_start_a_previously_stopped_service(self):
        self.running = False
        with patch("install.sqlite3.connect", side_effect=OSError("Backup failed")), \
                self.assertRaisesRegex(OSError, "Backup failed"):
            install.install(self.args)
        self.assertEqual(self.dropin.read_bytes(), self.previous)
        self.assertFalse(self.running)
        self.assertNotIn(("systemctl", "start", self.args.service), self.calls)

    def test_wrong_host_architecture_never_stops_service(self):
        with patch("install.platform.machine", return_value="aarch64"):
            with self.assertRaisesRegex(ValueError, "x86-64"):
                install.install(self.args)
        self.assertEqual(self.calls, [])

    def test_corrupted_download_never_stops_service(self):
        self.archive.write_bytes(b"corrupted")
        with self.assertRaisesRegex(ValueError, "checksum"):
            install.install(self.args)
        self.assertEqual(self.calls, [])


if __name__ == "__main__":
    unittest.main()
