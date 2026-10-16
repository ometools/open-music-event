#!/usr/bin/env python3
"""Build an isolated Swift 6.3.3 Android arm64 networking runtime overlay.

Run through swift-compiler-lane.sh. The installed SDK is read-only input.
This is an explicit local workaround pending an upstream SDK release; it is
not selected automatically by the app or the auth fixture.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tarfile
import urllib.request

TAG = "swift-6.3.3-RELEASE"
ARCHIVE_SHA256 = "cfba08125b15c3138f6d1e2b6cf5058ef2f294f3a08c54ef322d903a5002c20d"
RUNTIME_SHA256 = "99cb42ad356c90b6ec0b7c90d1a05fdafadbe39a97c2a671d14d2513a7cbe088"
LIBRARY = Path("swift-android/swift-resources/usr/lib/swift-aarch64/android/libFoundationNetworking.so")


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def overlay_tree(source, destination, remaining, replacement):
    """Materialize only ancestors of the replacement; symlink other inputs."""
    destination.mkdir(parents=True, exist_ok=True)
    for child in source.iterdir():
        target = destination / child.name
        if child.name == remaining[0]:
            if len(remaining) == 1:
                if target.is_symlink():
                    target.unlink()
                shutil.copy2(replacement, target)
            else:
                if target.is_symlink():
                    raise RuntimeError(f"Refusing to write through overlay symlink: {target}")
                overlay_tree(child, target, remaining[1:], replacement)
        elif not target.exists() and not target.is_symlink():
            target.symlink_to(child.absolute(), target_is_directory=child.is_dir())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sdk", type=Path, required=True)
    parser.add_argument("--swiftc", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    sdk, output = args.sdk.resolve(), args.output.resolve()
    if output == sdk or sdk in output.parents:
        raise RuntimeError("Overlay output must be outside the installed SDK")
    if digest(sdk / LIBRARY) != RUNTIME_SHA256:
        raise RuntimeError("Expected the unmodified Swift 6.3.3 Android arm64 runtime")
    version = subprocess.check_output([str(args.swiftc), "--version"], text=True)
    if "Swift version 6.3.3" not in version:
        raise RuntimeError("This overlay requires the matching Swift 6.3.3 compiler")
    output.mkdir(parents=True, exist_ok=True)
    archive = output / "source.tar.gz"
    if not archive.exists():
        urllib.request.urlretrieve(
            f"https://codeload.github.com/swiftlang/swift-corelibs-foundation/tar.gz/refs/tags/{TAG}", archive)
    if digest(archive) != ARCHIVE_SHA256:
        raise RuntimeError("Foundation source archive checksum mismatch")
    source = output / f"swift-corelibs-foundation-{TAG}"
    with tarfile.open(archive) as bundle:
        prefix = source.name + "/Sources/"
        members = [m for m in bundle.getmembers() if
                   m.name.startswith(prefix + "FoundationNetworking/") or
                   m.name.startswith(prefix + "_CFURLSessionInterface/include/")]
        bundle.extractall(output, members=members, filter="data")
    header = source / "Sources/_CFURLSessionInterface/include"
    (header / "module.modulemap").write_text(
        'module _CFURLSessionInterface { header "CFURLSessionInterface.h" export * }\n')
    task = source / "Sources/FoundationNetworking/URLSession/URLSessionTask.swift"
    text = task.read_text()
    patches = [
        # Upstream swift-corelibs-foundation PR #5417: avoid task/queue lock inversion.
        ("open func cancel() {\n        workQueue.sync {",
         "open func cancel() {\n        workQueue.async {"),
        # Completion can win while _getProtocol enqueues the second block.
        # Both this check and task-registry removal execute on the session work queue.
        ("self.workQueue.async {\n                    var info =",
         "self.workQueue.async {\n                    guard self.state != .completed else { return }\n                    var info ="),
    ]
    for old, new in patches:
        if text.count(old) != 1:
            raise RuntimeError("Foundation cancellation source no longer matches the reviewed patch")
        text = text.replace(old, new)
    task.write_text(text)
    resources = sdk / "swift-android/swift-resources/usr/lib/swift-aarch64"
    static = sdk / "swift-android/swift-resources/usr/lib/swift_static-aarch64/android"
    library = output / "libFoundationNetworking.so"
    command = [
        str(args.swiftc), "-emit-library", "-module-name", "FoundationNetworking",
        "-parse-as-library", "-O", "-whole-module-optimization", "-swift-version", "6",
        "-target", "aarch64-unknown-linux-android28",
        "-sdk", str(sdk / "swift-android/ndk-sysroot"),
        "-resource-dir", str(resources), "-module-cache-path", str(output / "module-cache"),
        "-I", str(header), "-Xcc", "-I" + str(resources / "CoreFoundation"),
        "-DDEPLOYMENT_RUNTIME_SWIFT", "-DSWIFT_CORELIBS_FOUNDATION_HAS_THREADS",
        "-Xclang-linker", "-resource-dir", "-Xclang-linker", str(resources / "clang"),
        "-Xclang-linker", "-fuse-ld=lld", "-L", str(static),
        "-l_CFURLSessionInterface", "-lcurl", "-lssl", "-lcrypto", "-lz",
        "-Xlinker", "-soname", "-Xlinker", "libFoundationNetworking.so",
        "-Xlinker", "-z", "-Xlinker", "max-page-size=16384", "-o", str(library),
        *map(str, sorted((source / "Sources/FoundationNetworking").rglob("*.swift"))),
    ]
    (output / "build-command.json").write_text(json.dumps(command, indent=2) + "\n")
    with (output / "build.log").open("w") as log:
        subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, check=True)
    overlay = output / "sdk" / sdk.name
    overlay_tree(sdk, overlay, LIBRARY.parts, library)
    (output / "manifest.json").write_text(json.dumps({
        "upstream": TAG, "sourceSHA256": ARCHIVE_SHA256,
        "installedRuntimeSHA256": RUNTIME_SHA256, "runtimeSHA256": digest(library),
        "architecture": "arm64-v8a", "sdk": str(sdk), "overlay": str(overlay),
        "fixes": ["upstream-5417-async-cancel", "ignore-cancel-after-completion"],
    }, indent=2) + "\n")
    print(f"SWIFT_ANDROID_SDK_BUNDLE={overlay}")


if __name__ == "__main__":
    main()
