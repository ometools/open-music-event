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
import socket
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


def new_events(before, lines):
    remaining = collections.Counter(before)
    result = []
    for line in lines:
        if remaining[line]:
            remaining[line] -= 1
        else:
            result.extend(EVENT.findall(line))
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--ios-device', required=True)
    parser.add_argument('--android-device', required=True)
    parser.add_argument('--ios-app-id', required=True)
    parser.add_argument('--android-app-id', required=True)
    parser.add_argument('--check-devices', action='store_true')
    parser.add_argument('--prepare', action='store_true', help='Create a run for DNS/HTTPS provisioning without starting UI tests')
    parser.add_argument('--resume', type=Path, help='Resume an incomplete run using its UI-created accounts')
    parser.add_argument('--prepared', type=Path, help='Start a provisioned run that has never started UI tests')
    args = parser.parse_args()
    dedicated_ios(args.ios_device)
    dedicated_android(args.android_device)
    if args.check_devices:
        return
    subprocess.run(['python3', str(Path(__file__).with_name('preflight.py'))], check=True)
    runs = ROOT / '.build/auth-e2e/runs'
    platforms = [dict(platform='ios', device=args.ios_device, app=args.ios_app_id),
                 dict(platform='android', device=args.android_device, app=args.android_app_id)]
    if args.resume and args.prepared:
        parser.error('--resume and --prepared are mutually exclusive')
    if args.resume or args.prepared:
        artifacts = (args.resume or args.prepared).resolve()
        if artifacts.parent != runs.resolve():
            raise ValueError('Resume requires a run directory inside this workspace')
        report = json.loads((artifacts / 'report.json').read_text())
        if args.prepared and (report.get('phases') or report.get('attempts')):
            raise ValueError('Prepared run has already started; cannot claim an uninterrupted fresh run')
        if report.get('platforms', platforms) != platforms:
            raise ValueError('Resume must use the original devices and app IDs')
        if report['passed']:
            print('This run already passed: ' + str(artifacts / 'report.json'))
            return
        password = json.loads((artifacts / 'credentials.json').read_text())['password']
        report['failures'] = []
    else:
        run_id = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%SZ')
        artifacts = runs / run_id
        artifacts.mkdir(parents=True, mode=0o700)
        password = 'OME-' + secrets.token_urlsafe(24)
        # Preserve credentials of UI-created accounts; never print them.
        descriptor = os.open(artifacts / 'credentials.json', os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(descriptor, 'w') as file:
            json.dump(dict(password=password), file)
            file.write('\n')
        report = dict(run=run_id, passed=False, phases=[], failures=[], platforms=platforms,
                      identities={p['platform']: p['platform'] + '-' + secrets.token_hex(5)
                                  for p in platforms})
    identities = report.get('identities', {'ios': 'ios-tester', 'android': 'android-tester'})
    (artifacts / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
    if args.prepare:
        print('Prepared run: ' + str(artifacts))
        return
    for username in identities.values():
        handle = username + '.pds1.ome-auth.test'
        try:
            addresses = {entry[4][0] for entry in socket.getaddrinfo(handle, 443)}
        except socket.gaierror:
            addresses = set()
        if '127.0.0.1' not in addresses:
            raise RuntimeError('Private account routing is missing for ' + handle
                               + '. Run prepare-run.py for ' + str(artifacts) + ' and verify the one-time Mac resolver installation'
                               + ', then resume it. No UI tests were started.')
    started = datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    report.setdefault('attempts', []).append(dict(started=started, resumed=bool(args.resume)))
    (artifacts / 'report.json').write_text(json.dumps(report, indent=2) + '\n')

    def events(target):
        if target['platform'] == 'ios':
            log = output('xcrun', 'simctl', 'spawn', target['device'], 'log', 'show',
                         '--style', 'compact', '--start', started,
                         '--predicate', 'category == "auth-e2e"')
        else:
            log = output(str(WRAPPERS / 'android-inspect.sh'), '--device', target['device'],
                         'logcat', '--lines', '100000')
        # Keep timestamps/process IDs until after subtraction: logcat can rotate old entries.
        return [line for line in log.splitlines() if EVENT.search(line)]

    def phase(name, flow, targets=platforms, identity=None, require_refresh=False):
        failures = []
        for target in targets:
            platform = target['platform']
            previous = next((p for p in report['phases']
                             if p['name'] == name and p['platform'] == platform), None)
            if previous and previous['passed']:
                print(f'{name}: {platform} already passed', flush=True)
                continue
            username = identities[identity or platform]
            directory = artifacts / name / platform
            directory.mkdir(parents=True, mode=0o700, exist_ok=True)
            before = events(target)
            command = ['maestro', '--device', target['device'], 'test',
                       '--test-output-dir', str(directory),
                       '-e', 'APP_ID=' + target['app'], '-e', 'USERNAME=' + username,
                       '-e', 'HANDLE=' + username + '.pds1.ome-auth.test',
                       '-e', 'EMAIL=' + username + '@ome-auth.test', '-e', 'PASSWORD=' + password,
                       str(ROOT / '.maestro/auth' / (flow + '.yaml'))]
            print(f'{name}: {platform}', flush=True)
            with (directory / 'maestro.log').open('w') as log:
                result = subprocess.run(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT)
            observed = new_events(before, events(target))
            passed = result.returncode == 0
            if flow == 'relaunch':
                passed = passed and ('getSession', '200') in observed
            if flow in ['signup', 'login']:
                passed = passed and ('exchange', '200') in observed
            if require_refresh:
                passed = passed and refresh_proven(observed)
            report['phases'] = [p for p in report['phases']
                                if (p['name'], p['platform']) != (name, platform)]
            report['phases'].append(dict(name=name, platform=platform, identity=username,
                                         uiExitCode=result.returncode, events=observed, passed=passed))
            if not passed:
                failure = f'{name}: {platform} UI or network evidence failed'
                failures.append(failure)
                report['failures'].append(failure)
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
        if not all(any(p['name'] == 'expired-token' and p['platform'] == target['platform']
                       and p['passed'] for p in report['phases']) for target in platforms):
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
