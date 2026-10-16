#!/usr/bin/env python3
"""Reject Android artifacts packaged with a different networking runtime than the selected SDK."""
import argparse
import hashlib
from pathlib import Path
import re
import zipfile

ARCHITECTURES = {"arm64-v8a": "aarch64", "x86_64": "x86_64", "armeabi-v7a": "armv7"}


def verify(artifact, sdk):
    with zipfile.ZipFile(artifact) as bundle:
        libraries = [name for name in bundle.namelist() if re.fullmatch(
            r"(?:base/)?lib/[^/]+/libFoundationNetworking\.so", name)]
        if not libraries:
            raise ValueError("OME artifact is missing FoundationNetworking")
        for name in libraries:
            abi = name.split("/")[-2]
            architecture = ARCHITECTURES[abi]
            source = sdk / f"swift-android/swift-resources/usr/lib/swift-{architecture}/android/libFoundationNetworking.so"
            expected = hashlib.sha256(source.read_bytes()).hexdigest()
            actual = hashlib.sha256(bundle.read(name)).hexdigest()
            if expected != actual:
                raise ValueError(f"{abi}: packaged FoundationNetworking differs from selected SDK")
            print(f"Verified {abi} packaged FoundationNetworking: {actual}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("artifact", type=Path)
    parser.add_argument("sdk", type=Path)
    args = parser.parse_args()
    verify(args.artifact, args.sdk)
