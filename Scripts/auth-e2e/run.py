#!/usr/bin/env python3
"""Run the same real auth story on two already-installed, dedicated devices."""
import argparse
import collections
import datetime
import json
import os
from pathlib import Path
import re
import secrets
import subprocess
import time

ROOT = Path(__file__).resolve().parents[2]
WRAPPERS = Path.home() / '.codex/skills/woodys-swift-workflow/scripts'
EVENT = re.compile(r'OME_AUTH_E2E (getSession|refresh|exchange) status=(\d{3})')


def output(*command):
    return subprocess.check_output(command, text=True, cwd=ROOT)


def dedicated_ios(device):
    devices = json.loads(output('xcrun', 'simctl', 'list', 'devices', '--json'))['devices']
    match = next((d for group in devices.values() for d in group if d['udid'] == device), None)
    if not match or not match['name'].startswith('OME Auth E2E'):
        raise ValueError('iOS target must be a dedicated simulator named OME Auth E2E…')


def dedicated_android(device):
    name = output(str(WRAPPERS / 'android-inspect.sh'), '--device', device,
                  'getprop', 'ro.boot.qemu.avd_name').strip().splitlines()[-1]
    if not name.startswith('OME_Auth_E2E'):
        raise ValueError('Android target must be a dedicated AVD named OME_Auth_E2E…')


def refresh_proven(events):
    # A 401 alone is not refresh proof; require a successful refresh and retry in order.
    expected = [('getSession', '401'), ('refresh', '200'), ('getSession', '200')]
    for event in events:
        if expected and event == expected[0]:
            expected.pop(0)
    return not expected


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--ios-device', required=True)
    parser.add_argument('--android-device', required=True)
    parser.add_argument('--ios-app-id', required=True)
    parser.add_argument('--android-app-id', required=True)
    parser.add_argument('--check-devices', action='store_true')
    args = parser.parse_args()
    dedicated_ios(args.ios_device)
    dedicated_android(args.android_device)
    if args.check_devices:
        return
    subprocess.run(['python3', str(Path(__file__).with_name('preflight.py'))], check=True)
    run_id = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%SZ')
    artifacts = ROOT / '.build/auth-e2e/runs' / run_id
    artifacts.mkdir(parents=True, mode=0o700)
    password = 'OME-' + secrets.token_urlsafe(24)
    platforms = [dict(platform='ios', device=args.ios_device, app=args.ios_app_id),
                 dict(platform='android', device=args.android_device, app=args.android_app_id)]
    report = dict(run=run_id, passed=False, phases=[], failures=[])
    started = datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')

    def events(target):
        if target['platform'] == 'ios':
            log = output('xcrun', 'simctl', 'spawn', target['device'], 'log', 'show',
                         '--style', 'compact', '--start', started,
                         '--predicate', 'category == "auth-e2e"')
        else:
            log = output(str(WRAPPERS / 'android-inspect.sh'), '--device', target['device'],
                         'logcat', '--lines', '10000', '--filter', 'OME_AUTH_E2E')
        return EVENT.findall(log)

    def phase(name, flow, targets=platforms, identity=None, require_refresh=False):
        failures = []
        for target in targets:
            platform = target['platform']
            username = (identity or platform) + '-tester'
            directory = artifacts / name / platform
            directory.mkdir(parents=True, mode=0o700)
            before = collections.Counter(events(target))
            command = ['maestro', '--device', target['device'], 'test',
                       '--test-output-dir', str(directory),
                       '-e', 'APP_ID=' + target['app'], '-e', 'USERNAME=' + username,
                       '-e', 'HANDLE=' + username + '.pds1.ome-auth.test',
                       '-e', 'EMAIL=' + username + '@ome-auth.test', '-e', 'PASSWORD=' + password,
                       str(ROOT / '.maestro/auth' / (flow + '.yaml'))]
            print(f'{name}: {platform}', flush=True)
            with (directory / 'maestro.log').open('w') as log:
                result = subprocess.run(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT)
            new_events = []
            for event in events(target):
                if before[event]:
                    before[event] -= 1
                else:
                    new_events.append(event)
            passed = result.returncode == 0
            if flow == 'relaunch':
                passed = passed and ('getSession', '200') in new_events
            if flow in ['signup', 'login']:
                passed = passed and ('exchange', '200') in new_events
            if require_refresh:
                passed = passed and refresh_proven(new_events)
            report['phases'].append(dict(name=name, platform=platform, identity=username,
                                         uiExitCode=result.returncode, events=new_events, passed=passed))
            if not passed:
                failures.append(f'{name}: {platform} UI or network evidence failed')
        report['failures'].extend(failures)
        (artifacts / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
        if failures:
            raise RuntimeError('; '.join(failures))

    def expire():
        # Stop both processes so no background request refreshes before the assertion.
        for target in platforms:
            if target['platform'] == 'ios':
                subprocess.run(['xcrun', 'simctl', 'terminate', target['device'], target['app']], check=True)
            else:
                subprocess.run([str(WRAPPERS / 'android-drive.sh'), '--device', target['device'],
                                'stop', target['app']], check=True)
        print('Waiting 70 real seconds for the PDS access-token lifetime.', flush=True)
        time.sleep(70)

    try:
        phase('signup', 'signup')
        phase('logout', 'logout')
        phase('login', 'login')
        phase('restore', 'relaunch')
        expire()
        phase('expired-token', 'relaunch', require_refresh=True)
        phase('restore-refreshed-session', 'relaunch')
        # Both devices hold independent sessions for the Android-created account.
        phase('cross-logout-ios', 'logout', platforms[:1])
        phase('cross-login-ios', 'login', platforms[:1], identity='android')
        phase('cross-restore-ios', 'relaunch', platforms[:1], identity='android')
        phase('peer-still-signed-in', 'relaunch', platforms[1:])
        phase('cross-local-logout', 'logout', platforms[:1], identity='android')
        phase('peer-survives-local-logout', 'relaunch', platforms[1:])
        # Also prove Android can resolve and sign in to the iOS-created account.
        phase('cross-logout-android', 'logout', platforms[1:])
        phase('cross-login-android', 'login', platforms[1:], identity='ios')
        phase('cross-restore-android', 'relaunch', platforms[1:], identity='ios')
        report['passed'] = True
    finally:
        (artifacts / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
        print('Report: ' + str(artifacts / 'report.json'), flush=True)


if __name__ == '__main__':
    main()
