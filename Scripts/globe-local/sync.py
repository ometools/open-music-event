#!/usr/bin/env python3
"""Publish every configured source graph from its venue-owned local DID."""
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
SOURCE = Path(__file__).resolve().parent
STATE = Path(os.environ.get('OME_GLOBE_STATE_DIRECTORY', ROOT / '.build/globe-local')).resolve()
REVISION = '26cf1f60f81b491b065dfc830efd27aba8b89a54'
UPSTREAM = STATE / f'atmosphereinabox-{REVISION}'
DOMAIN = 'ome-globe.test'
PDS = f'pds1.{DOMAIN}'
PROXY = 'http://127.0.0.1:18083'
LANE = Path.home() / '.codex/skills/woodys-swift-workflow/scripts/swift-compiler-lane.sh'


def ometools_root():
    configured = os.environ.get('OMETools_ROOT')
    if configured:
        return Path(configured).resolve()
    return ROOT.parent.parent if ROOT.parent.name == 'worktrees' else ROOT.parent


def atmosphere_root():
    configured = os.environ.get('OME_COMPOSABLE_ATMOSPHERE_PATH')
    candidates = [
        Path(configured).resolve() if configured else None,
        Path('/Users/woody/Developer/swift-packages/swift-composable-atmosphere-reorg-auth'),
        ometools_root() / 'worktrees/atmosphere-publication-android/swift-composable-atmosphere-reorg-auth',
    ]
    path = next((candidate for candidate in candidates if candidate and (candidate / 'Package.swift').exists()), None)
    if path is None:
        raise SystemExit('Could not find the local swift-composable-atmosphere package.')
    return path


def create_session(account, directory):
    ca = UPSTREAM / 'state/ca/root.crt'
    response = subprocess.run([
        'curl', '--silent', '--show-error', '--fail', '--proxy', PROXY,
        '--cacert', str(ca), '--request', 'POST',
        '--header', 'content-type: application/json', '--data-binary', '@-',
        f'https://{PDS}/xrpc/com.atproto.server.createSession',
    ], input=json.dumps({
        'identifier': account['handle'], 'password': account['password'],
    }), text=True, check=True, capture_output=True)
    value = json.loads(response.stdout)
    if value.get('did') != account['did'] or not value.get('accessJwt'):
        raise SystemExit(f"Session identity mismatch for {account['handle']}")
    path = directory / 'session.json'
    path.write_text(json.dumps({'did': value['did'], 'accessJwt': value['accessJwt']}))
    path.chmod(0o600)
    return path


def run_ome(arguments):
    environment = os.environ.copy()
    environment['OME_COMPOSABLE_ATMOSPHERE_PATH'] = str(atmosphere_root())
    subprocess.run([
        str(LANE), '--repo', str(ROOT), '--wait', '--priority', 'normal',
        'exec', 'swift', 'run', 'ome', *arguments,
    ], cwd=ROOT, env=environment, check=True)


def start_proxy():
    environment = os.environ.copy()
    environment['OME_GLOBE_PROXY_UPSTREAM_HOST'] = '127.0.0.1'
    environment['OME_GLOBE_PROXY_LISTEN_PORT'] = '18083'
    process = subprocess.Popen(
        [sys.executable, str(SOURCE / 'venue_publication_proxy.py')],
        env=environment,
    )
    for _ in range(50):
        if process.poll() is not None:
            raise SystemExit('The local venue publication proxy stopped during startup.')
        try:
            with socket.create_connection(('127.0.0.1', 18083), timeout=0.1):
                return process
        except OSError:
            time.sleep(0.1)
    process.terminate()
    process.wait()
    raise SystemExit('The local venue publication proxy did not start.')


def main():
    proxy = start_proxy()
    try:
        publish()
    finally:
        proxy.terminate()
        proxy.wait()


def publish():
    configuration = json.loads((SOURCE / 'venues.json').read_text())
    account_state = json.loads((UPSTREAM / 'state/accounts.json').read_text())['accounts']
    ca = UPSTREAM / 'state/ca/root.crt'
    private = STATE / 'publication'
    private.mkdir(parents=True, exist_ok=True, mode=0o700)
    total = 0
    for venue in configuration['venues']:
        handle = f"{venue['accountLabel']}.pds1.{DOMAIN}"
        account = account_state.get(handle)
        if not account or account.get('phase') != 'ready' or not account.get('did'):
            raise SystemExit(f'Run seed before sync; {handle} is not ready')
        source = ometools_root() / venue['source']
        event_count = len([path for path in (source / 'events').iterdir() if path.is_dir()])
        if event_count != venue['eventCount']:
            raise SystemExit(
                f"Source count changed for {venue['slug']}: expected {venue['eventCount']}, found {event_count}"
            )
        venue_state = private / venue['slug']
        venue_state.mkdir(parents=True, exist_ok=True, mode=0o700)
        session = create_session(account, venue_state)
        profile = [
            'protocol', 'publish-profile', '--account', account['did'],
            '--display-name', venue['displayName'], '--description', venue['description'],
            '--pds', PDS, '--session-file', str(session),
            '--ca-certificate', str(ca), '--proxy', PROXY,
        ]
        if venue.get('avatar'):
            profile += ['--avatar', str(ROOT / venue['avatar'])]
        run_ome(profile)
        run_ome([
            'protocol', 'publish-events', str(source), '--discover-events',
            '--created-at', configuration['createdAt'], '--account', account['did'],
            '--all-records', '--identity-map', str(venue_state / 'identities.json'),
            '--image-cache', str(venue_state / 'images'), '--preserve-link-text',
            '--pds', PDS, '--session-file', str(session),
            '--ca-certificate', str(ca), '--proxy', PROXY,
        ])
        total += event_count
    print(f'Verified {total} source Events across {len(configuration["venues"])} venue DIDs.')


if __name__ == '__main__':
    main()
