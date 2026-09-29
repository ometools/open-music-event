#!/usr/bin/env python3
"""Install private DNS and CA trust only in a dedicated rootable test AVD.

Bind mounts last until emulator reboot. Run again after each fresh boot.
Uses the same CA directory for Chrome and native FoundationNetworking.
"""
import argparse
import importlib.util
from pathlib import Path
import re
import subprocess
import tempfile
from run import dedicated_android
from sandbox import UPSTREAM


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--device', required=True)
    parser.add_argument('--run', type=Path, help='Route handles from this prepared auth run')
    args = parser.parse_args()
    device = args.device
    if not re.fullmatch(r'emulator-\d+', device):
        parser.error('Only an emulator serial is accepted')
    dedicated_android(device)

    def adb(*args, capture=False):
        return subprocess.run(['adb', '-s', device, *args], check=True, text=True,
                              stdout=subprocess.PIPE if capture else None, timeout=60).stdout

    ca = UPSTREAM / 'state/ca/root.crt'
    fingerprint = subprocess.check_output(
        ['openssl', 'x509', '-in', str(ca), '-subject_hash_old', '-noout'], text=True).strip()
    if not re.fullmatch(r'[0-9a-f]{8}', fingerprint):
        raise RuntimeError('Unexpected certificate subject hash')
    adb('root')
    adb('wait-for-device')
    if adb('shell', 'id -u', capture=True).strip() != '0':
        raise RuntimeError('Use a rootable Google APIs image, not a Play Store image')
    stage = '/data/local/tmp/ome-auth-cacerts'
    adb('shell', 'mkdir -p ' + stage)
    for source in ['/system/etc/security/cacerts', '/apex/com.android.conscrypt/cacerts']:
        adb('shell', f'for cert in {source}/*; do [ "$cert" -ef "{stage}/${{cert##*/}}" ] || cp "$cert" {stage}/; done')
    adb('push', str(ca), stage + '/' + fingerprint + '.0')
    adb('shell', 'chmod 755 ' + stage + '; chmod 644 ' + stage + '/*; chown -R root:root ' + stage)
    adb('shell', 'chcon -R u:object_r:system_security_cacerts_file:s0 ' + stage)
    user_store = '/data/misc/user/0/cacerts-added'
    user_cert = user_store + '/' + fingerprint + '.0'
    adb('shell', 'mkdir -p ' + user_store)
    adb('shell', f'cp {stage}/{fingerprint}.0 {user_cert}')
    adb('shell', f'chown system:system {user_store} {user_cert}; chmod 755 {user_store}; chmod 644 {user_cert}')
    adb('shell', 'restorecon -R ' + user_store)

    spec = importlib.util.spec_from_file_location('hosts', Path(__file__).with_name('host-routing.py'))
    hosts = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(hosts)
    current = adb('shell', 'cat /system/etc/hosts', capture=True)
    updated = hosts.updated(current, False) + hosts.block(hosts.handles_for_run(args.run)).replace('127.0.0.1', '10.0.2.2')
    with tempfile.TemporaryDirectory() as directory:
        path = Path(directory) / 'hosts'
        path.write_text(updated)
        adb('push', str(path), '/data/local/tmp/ome-auth-hosts')
    adb('shell', 'chmod 644 /data/local/tmp/ome-auth-hosts; chcon u:object_r:system_file:s0 /data/local/tmp/ome-auth-hosts')

    # Existing resolver and zygote namespaces need the same mounts as init.
    # Newly launched app/browser processes then inherit the trusted CA view.
    pids = {'1'}
    for process in ['zygote64', 'netd', 'system_server']:
        pids.update(adb('shell', 'pidof ' + process, capture=True).split())
    for pid in sorted(pids):
        if not pid.isdecimal():
            raise RuntimeError('Unexpected process identifier')
        adb('shell', f'nsenter -t {pid} -m -- mount --bind {stage} /apex/com.android.conscrypt/cacerts')
        adb('shell', f'nsenter -t {pid} -m -- mount --bind {stage} /system/etc/security/cacerts')
        adb('shell', f'nsenter -t {pid} -m -- mount --bind /data/local/tmp/ome-auth-hosts /system/etc/hosts')
    print('Private DNS and CA mounted in the dedicated emulator; restart app and browser processes.')


if __name__ == '__main__':
    main()
