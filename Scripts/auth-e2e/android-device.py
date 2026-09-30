#!/usr/bin/env python3
"""Bounded device operations for the dedicated private-auth emulator."""
import argparse
import re
import subprocess


def device_name(serial):
    if not re.fullmatch(r"emulator-[0-9]+", serial):
        raise ValueError("Private auth requires an Android emulator serial")
    name = subprocess.check_output(
        ["adb", "-s", serial, "shell", "getprop", "ro.boot.qemu.avd_name"],
        text=True).strip()
    if not name.startswith("OME_Auth_E2E"):
        raise ValueError("Android target must be a dedicated AVD named OME_Auth_E2E…")
    return name


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device", required=True)
    parser.add_argument("command", choices=["name", "logs", "stop"])
    parser.add_argument("--app")
    args = parser.parse_args()
    name = device_name(args.device)
    if args.command == "name":
        print(name)
    elif args.command == "logs":
        logs = subprocess.check_output(
            ["adb", "-s", args.device, "logcat", "-d", "-v", "threadtime"], text=True)
        print("\n".join(logs.splitlines()[-100000:]))
    else:
        if not args.app or not re.fullmatch(r"[A-Za-z][A-Za-z0-9_.]+", args.app):
            parser.error("stop requires --app with a package identifier")
        subprocess.run(
            ["adb", "-s", args.device, "shell", "am", "force-stop", args.app], check=True)


if __name__ == "__main__":
    main()
