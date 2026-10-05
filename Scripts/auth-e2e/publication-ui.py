#!/usr/bin/env python3
"""Drive publication through the app. This harness never writes ATProto records or blobs."""
import argparse
import datetime
import json
from pathlib import Path
import ssl
import subprocess
import urllib.parse
import urllib.request

from run import ROOT, dedicated_android, dedicated_ios
from sandbox import UPSTREAM


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--run', type=Path, required=True)
    parser.add_argument('--phase', choices=['signup', 'import', 'edit', 'replace-description', 'replace-image', 'replace-image-picker', 'image', 'select-image-a', 'select-image-b', 'publish', 'authorize', 'reader'], required=True)
    parser.add_argument('--reader-device')
    parser.add_argument('--reader-platform', choices=['ios', 'android'])
    parser.add_argument('--description', default='Testival published from the app with image A')
    args = parser.parse_args()
    directory = args.run.resolve()
    if directory.parent != (ROOT / '.build/auth-e2e/runs').resolve():
        parser.error('Use a prepared run in this workspace')
    report = json.loads((directory / 'report.json').read_text())
    organizer = next(p for p in report['platforms'] if p['platform'] == 'ios')
    target = organizer
    if args.phase == 'reader':
        if not args.reader_device or not args.reader_platform or args.reader_device == organizer['device']:
            parser.error('A reader must be an independent device, never the organizer')
        app = next(p['app'] for p in report['platforms'] if p['platform'] == args.reader_platform)
        target = dict(device=args.reader_device, platform=args.reader_platform, app=app)
    if target['platform'] == 'ios':
        dedicated_ios(target['device'])
    else:
        dedicated_android(target['device'])
    attempt = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    artifacts = directory / ('publication-' + args.phase) / attempt
    artifacts.mkdir(parents=True, mode=0o700)
    environment = {'APP_ID': target['app'], 'DESCRIPTION': args.description}
    if args.phase == 'signup':
        username = report['identities']['ios']
        environment.update(USERNAME=username, HANDLE=username + '.pds1.ome-auth.test',
                           EMAIL=username + '@example.test',
                           PASSWORD=json.loads((directory / 'credentials.json').read_text())['password'])
        flow = ROOT / '.maestro/auth/signup.yaml'
    else:
        flow = ROOT / '.maestro/publication' / (args.phase + '.yaml')
    if args.phase in ['publish', 'authorize']:
        environment['PASSWORD'] = json.loads((directory / 'credentials.json').read_text())['password']
    if args.phase == 'import':
        # Public identity resolution is verification/input; the app performs the import.
        opener = urllib.request.build_opener(urllib.request.ProxyHandler({}),
            urllib.request.HTTPSHandler(context=ssl.create_default_context(cafile=str(UPSTREAM / 'state/ca/root.crt'))))
        handle = report['identities']['ios'] + '.pds1.ome-auth.test'
        url = 'https://pds1.ome-auth.test/xrpc/com.atproto.identity.resolveHandle?' + urllib.parse.urlencode({'handle': handle})
        with opener.open(url, timeout=10) as response:
            environment['PUBLISHER_DID'] = json.load(response)['did']
    command = ['maestro', '--device', target['device'], 'test', '--test-output-dir', str(artifacts)]
    for key, value in environment.items():
        command += ['-e', key + '=' + value]
    command.append(str(flow))
    # Auth automation output may contain typed credentials: retain it only in the private run directory.
    with (artifacts / 'maestro.log').open('x') as log:
        result = subprocess.run(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT)
    evidence = dict(phase=args.phase, platform=target['platform'], device=target['device'],
                    passed=result.returncode == 0, flow=str(flow), artifacts=str(artifacts))
    (artifacts / 'result.json').write_text(json.dumps(evidence, indent=2) + '\n')
    print(f"{args.phase}: {'passed' if evidence['passed'] else 'failed'}; evidence: {artifacts}")
    raise SystemExit(result.returncode)


if __name__ == '__main__':
    main()
