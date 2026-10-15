#!/usr/bin/env python3
"""Tangled's web pipeline: publish once, stage automatically, promote the staged digest."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def required(name):
    value = os.environ.get(name)
    if not value:
        raise ValueError(f"Missing CI setting: {name}")
    return value


def sha256(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def command(*args, **kwargs):
    return subprocess.run(args, check=True, **kwargs)


class ReleaseStore:
    def __init__(self):
        self.bucket = required("OME_WEB_RELEASE_BUCKET")
        self.region = required("AWS_REGION")

    def get(self, key, path, optional=False):
        result = subprocess.run([
            "aws", "s3api", "get-object", "--region", self.region,
            "--bucket", self.bucket, "--key", key, str(path)
        ], text=True, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        if result.returncode == 0:
            return True
        if optional and "(NoSuchKey)" in result.stderr:
            return False
        raise ValueError(f"Cannot read release object: {key}")

    def put_once(self, key, path):
        result = subprocess.run([
            "aws", "s3api", "put-object", "--region", self.region, "--bucket", self.bucket, "--key", key,
            "--body", str(path), "--if-none-match", "*"
        ], text=True, capture_output=True)
        if result.returncode == 0:
            return
        if "(PreconditionFailed)" not in result.stderr:
            raise ValueError(f"Could not store immutable release object: {key}")
        with tempfile.TemporaryDirectory() as temporary:
            existing = Path(temporary) / "object"
            self.get(key, existing)
            if sha256(existing) != sha256(path):
                raise ValueError(f"Refusing to overwrite release object: {key}")


def candidate_key(revision):
    return f"web/releases/{revision}/candidate.json"


def load_candidate(store, revision, directory):
    path = directory / "candidate.json"
    store.get(candidate_key(revision), path)
    candidate = json.loads(path.read_text())
    digest = candidate.get("artifactSHA256", "")
    if candidate.get("sourceRevision") != revision or not re.fullmatch(r"[0-9a-f]{64}", digest):
        raise ValueError("Invalid candidate identity")
    if candidate.get("artifactKey") != f"web/artifacts/{digest}.tar.gz":
        raise ValueError("Invalid artifact storage key")
    return candidate


def require_staging_receipt(candidate, receipt):
    if (receipt.get("sourceRevision") != candidate["sourceRevision"]
            or receipt.get("artifactSHA256") != candidate["artifactSHA256"]
            or receipt.get("environment") != "staging" or receipt.get("result") != "passed"):
        raise ValueError("Production requires staging proof for this exact artifact")


def deploy(candidate, archive, environment):
    prefix = f"OME_{environment.upper()}_"
    host = required(prefix + "SSH_HOST")
    user = required(prefix + "SSH_USER")
    if not re.fullmatch(r"[a-zA-Z0-9.-]+", host) or not re.fullmatch(r"[a-z_][a-z0-9_-]*", user):
        raise ValueError("Invalid deployment SSH host or user")
    service = required(prefix + "SERVICE")
    database = required(prefix + "DATABASE")
    base_url = required(prefix + "URL").rstrip("/")
    if not re.fullmatch(r"https://[a-zA-Z0-9.-]+", base_url):
        raise ValueError("Deployment URL must be an HTTPS origin")
    with tempfile.TemporaryDirectory(prefix="ome-ci-ssh-") as temporary:
        directory = Path(temporary)
        key = directory / "key"
        key.write_text(required(prefix + "SSH_KEY").rstrip() + "\n")
        key.chmod(0o600)
        known_hosts = directory / "known_hosts"
        known_hosts.write_text(required(prefix + "KNOWN_HOSTS").rstrip() + "\n")
        options = ["-i", str(key), "-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=yes",
                   "-o", f"UserKnownHostsFile={known_hosts}", "-o", "ConnectTimeout=15"]
        target = f"{user}@{host}"
        remote = command("ssh", *options, target, "mktemp -d /tmp/ome-ci.XXXXXXXX",
                         capture_output=True, text=True).stdout.strip()
        if not re.fullmatch(r"/tmp/ome-ci\.[a-zA-Z0-9]+", remote):
            raise ValueError("Unexpected remote temporary directory")
        try:
            command("scp", *options, str(archive), str(ROOT / "Scripts/web-release/install.py"),
                    str(ROOT / "Scripts/web-release/artifact.py"), str(ROOT / "Scripts/web-release/smoke.sh"),
                    f"{target}:{remote}/")
            args = ["sudo", "-n", "python3", remote + "/install.py", "--archive", remote + "/appview.tar.gz",
                    "--sha256", candidate["artifactSHA256"], "--revision", candidate["sourceRevision"],
                    "--service", service, "--database", database, "--base-url", base_url,
                    "--smoke-script", remote + "/smoke.sh"]
            command("ssh", *options, target, shlex.join(args))
        finally:
            subprocess.run(["ssh", *options, target, shlex.join(["rm", "-rf", "--", remote])], check=False)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["preflight", "build", "stage", "promote"])
    args = parser.parse_args()
    try:
        revision = required("TANGLED_SHA")
        kind = required("TANGLED_PIPELINE_KIND")
        if not re.fullmatch(r"[0-9a-f]{40}", revision):
            raise ValueError("Tangled must supply the exact source commit")
        if os.environ.get("TANGLED_REF") != "refs/heads/main":
            raise ValueError("Only the reviewed main branch can deploy")
        expected_kind = "manual" if args.action == "promote" else "push"
        if kind != expected_kind:
            raise ValueError(f"{args.action} requires a {expected_kind} pipeline")
        if args.action == "preflight":
            names = ["OME_WEB_RELEASE_BUCKET", "AWS_REGION", "GITHUB_TOKEN",
                     "OME_STAGING_SSH_HOST", "OME_STAGING_SSH_USER", "OME_STAGING_SERVICE",
                     "OME_STAGING_DATABASE", "OME_STAGING_URL",
                     "OME_STAGING_SSH_KEY", "OME_STAGING_KNOWN_HOSTS"]
            missing = [name for name in names if not os.environ.get(name)]
            if missing:
                raise ValueError("Missing CI settings: " + ", ".join(missing))
            print("Web deployment CI settings are present")
            return
        store = ReleaseStore()
        with tempfile.TemporaryDirectory(prefix="ome-release-") as temporary:
            directory = Path(temporary)
            if args.action == "build":
                if store.get(candidate_key(revision), directory / "candidate.json", optional=True):
                    candidate = load_candidate(store, revision, directory)
                    output = ROOT / ".build/web-release"
                    output.mkdir(parents=True, exist_ok=True)
                    for key, filename, checksum in (
                        (candidate["artifactKey"], "appview.tar.gz", candidate["artifactSHA256"]),
                        (f"web/releases/{revision}/tests.xml", "tests.xml", candidate["testReportSHA256"]),
                        (f"web/releases/{revision}/verified-manifest.json", "verified-manifest.json", candidate["manifestSHA256"]),
                    ):
                        path = output / filename
                        store.get(key, path)
                        if sha256(path) != checksum:
                            raise ValueError(f"Stored release evidence changed: {filename}")
                    print("Reusing the previously validated candidate; no rebuild")
                else:
                    command("bash", str(ROOT / "Scripts/web-release/ci.sh"), cwd=ROOT)
                return
            if args.action == "stage":
                output = ROOT / ".build/web-release"
                archive = output / "appview.tar.gz"
                candidate = {
                    "sourceRevision": revision,
                    "artifactSHA256": sha256(archive),
                    "testReportSHA256": sha256(output / "tests.xml"),
                    "manifestSHA256": sha256(output / "verified-manifest.json"),
                }
                manifest = json.loads((output / "verified-manifest.json").read_text())
                if manifest["sourceRevision"] != revision:
                    raise ValueError("Built artifact is from another source revision")
                candidate["artifactKey"] = f"web/artifacts/{candidate['artifactSHA256']}.tar.gz"
                store.put_once(candidate["artifactKey"], archive)
                for filename in ("tests.xml", "verified-manifest.json"):
                    store.put_once(f"web/releases/{revision}/{filename}", output / filename)
                path = directory / "candidate.json"
                path.write_text(json.dumps(candidate, sort_keys=True) + "\n")
                store.put_once(candidate_key(revision), path)
            candidate = load_candidate(store, revision, directory)
            if args.action == "promote":
                receipt_file = directory / "staging.json"
                store.get(f"web/releases/{revision}/staging.json", receipt_file)
                require_staging_receipt(candidate, json.loads(receipt_file.read_text()))
            archive = directory / "appview.tar.gz"
            store.get(candidate["artifactKey"], archive)
            if sha256(archive) != candidate["artifactSHA256"]:
                raise ValueError("Stored artifact checksum mismatch")
            environment = "staging" if args.action == "stage" else "production"
            deploy(candidate, archive, environment)
            receipt = directory / (environment + ".json")
            receipt.write_text(json.dumps({
                "sourceRevision": revision, "artifactSHA256": candidate["artifactSHA256"],
                "environment": environment, "result": "passed"
            }, sort_keys=True) + "\n")
            store.put_once(f"web/releases/{revision}/{environment}.json", receipt)
            print(f"{environment}: {revision} / {candidate['artifactSHA256']}")
    except (OSError, ValueError, KeyError, subprocess.CalledProcessError) as error:
        parser.exit(1, f"Web pipeline stopped: {error}\n")


if __name__ == "__main__":
    main()
