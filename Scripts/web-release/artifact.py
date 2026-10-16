#!/usr/bin/env python3
"""Package and verify the portable Ubuntu AppView release, without host configuration."""
import argparse
import gzip
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import tarfile


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def verify(root):
    root = root.resolve()
    if any(p.is_symlink() for p in root.rglob("*")):
        raise ValueError("Release contains a symbolic link")
    manifest = json.loads((root / "manifest.json").read_text())
    expected = manifest["files"]
    actual = {p.relative_to(root).as_posix() for p in root.rglob("*") if p.is_file()}
    if actual != set(expected) | {"manifest.json"}:
        raise ValueError("Release file list differs from the manifest")
    for name, metadata in expected.items():
        path = root / name
        if not path.resolve().is_relative_to(root):
            raise ValueError(f"Unsafe release path: {name}")
        if digest(path) != metadata["sha256"] or (path.stat().st_mode & 0o777) != metadata["mode"]:
            raise ValueError(f"Release content or mode changed: {name}")
    return manifest


def package(bin_dir, libraries, lockfile, revision, toolchain, output):
    if not re.fullmatch(r"[0-9a-f]{40}", revision):
        raise ValueError("Source revision must be a full commit SHA")
    executable = bin_dir / "OpenMusicEventAppView"
    with executable.open("rb") as stream:
        header = stream.read(20)
    if header[:6] != b"\x7fELF\x02\x01" or header[18:20] != b"\x3e\x00":
        raise ValueError("Staging requires a Linux x86-64 executable")
    bundles = sorted(bin_dir.glob("*.resources"))
    if not any(p.name.endswith("OpenMusicEventAppViewServer.resources") for p in bundles):
        raise ValueError("AppView resource bundle is missing")
    if output.exists():
        raise ValueError(f"Output already exists: {output}")
    root = output / "appview"
    root.mkdir(parents=True)
    shutil.copy2(executable, root / executable.name)
    (root / executable.name).chmod(0o755)
    for bundle in bundles:
        if any(path.is_symlink() for path in bundle.rglob("*")):
            raise ValueError(f"Resource bundle contains symlinks: {bundle.name}")
        shutil.copytree(bundle, root / bundle.name)
    site = next(p for p in root.glob("*.resources") if p.name.endswith("OpenMusicEventAppViewServer.resources")) / "Site"
    (site / "assets").mkdir(parents=True, exist_ok=True)
    (site / "assets/release.json").write_text(json.dumps({
        "sourceRevision": revision, "executableSHA256": digest(executable),
        "lockfileSHA256": digest(lockfile),
    }, sort_keys=True) + "\n")
    library_dir = root / "lib"
    library_dir.mkdir()
    for library in libraries:
        target = library_dir / library.name
        if target.exists() and digest(target) != digest(library):
            raise ValueError(f"Conflicting runtime library: {library.name}")
        shutil.copyfile(library, target)
    shutil.copyfile(lockfile, root / "Package.resolved")
    (root / "run").write_text(
        '#!/bin/sh\nset -eu\n'
        'release_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"\n'
        'export LD_LIBRARY_PATH="$release_dir/lib"\n'
        'exec "$release_dir/OpenMusicEventAppView" "$@"\n'
    )
    (root / "run").chmod(0o755)
    files = {}
    for path in sorted(root.rglob("*")):
        if path.is_file():
            mode = 0o755 if path.name in ("run", "OpenMusicEventAppView") else 0o644
            path.chmod(mode)
            files[path.relative_to(root).as_posix()] = {"sha256": digest(path), "mode": mode}
    manifest = {
        "schemaVersion": 1,
        "sourceRevision": revision,
        "platform": "linux/amd64",
        "os": "ubuntu-24.04",
        "toolchainImage": toolchain,
        "files": files,
    }
    (root / "manifest.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    (root / "manifest.json").chmod(0o644)
    verify(root)
    archive = output / "appview.tar.gz"
    with archive.open("wb") as raw, gzip.GzipFile(filename="", fileobj=raw, mode="wb", mtime=0) as compressed:
        with tarfile.open(fileobj=compressed, mode="w") as tar:
            for path in sorted(root.rglob("*")):
                if path.is_file():
                    info = tar.gettarinfo(str(path), arcname=path.relative_to(root).as_posix())
                    info.uid = info.gid = info.mtime = 0
                    info.uname = info.gname = ""
                    with path.open("rb") as stream:
                        tar.addfile(info, stream)
    (output / "appview.tar.gz.sha256").write_text(f"{digest(archive)}  appview.tar.gz\n")
    return root


def runtime_libraries(executable):
    # Keep the host's glibc and loader together; bundle the remaining linked libraries.
    host_libraries = re.compile(r"^(ld-linux.*|lib(c|m|pthread|rt|dl|resolv|util)\.so.*)$")
    result = subprocess.run(["ldd", str(executable)], check=True, text=True, capture_output=True)
    if "not found" in result.stdout:
        raise ValueError("Executable has unresolved runtime libraries")
    paths = []
    for line in result.stdout.splitlines():
        match = re.search(r"(?:=>\s+)?(/\S+)\s+\(", line)
        if match and not host_libraries.fullmatch(Path(match[1]).name):
            paths.append(Path(match[1]))
    if not paths:
        raise ValueError("No dynamic runtime libraries found")
    return paths


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    pack = subparsers.add_parser("package")
    pack.add_argument("--bin-dir", type=Path, required=True)
    pack.add_argument("--lockfile", type=Path, required=True)
    pack.add_argument("--revision", required=True)
    pack.add_argument("--toolchain-image", required=True)
    pack.add_argument("--output", type=Path, required=True)
    check = subparsers.add_parser("verify")
    check.add_argument("directory", type=Path)
    args = parser.parse_args()
    try:
        if args.command == "verify":
            print(json.dumps(verify(args.directory), indent=2))
        else:
            root = package(args.bin_dir, runtime_libraries(args.bin_dir / "OpenMusicEventAppView"),
                           args.lockfile, args.revision, args.toolchain_image, args.output)
            print(root)
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        parser.exit(1, f"Web release: {error}\n")


if __name__ == "__main__":
    main()
