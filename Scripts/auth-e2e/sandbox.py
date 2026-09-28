#!/usr/bin/env python3
"""Pinned private Atmosphere for OME UI tests. Never seeds accounts."""
import argparse
import hashlib
import json
import pathlib
import shutil
import subprocess
import sys
import tarfile
import urllib.request

ARCHIVE_SHA256 = 'f6fbc8d72316aa4a553ecf4ab2ce0201eeb802ea284715f7b976c2896984d383'
REVISION = '26cf1f60f81b491b065dfc830efd27aba8b89a54'
ROOT = pathlib.Path(__file__).resolve().parents[2]
STATE = ROOT / '.build/auth-e2e'
UPSTREAM = STATE / f'atmosphereinabox-{REVISION}'
SOURCE = pathlib.Path(__file__).resolve().parent
PROJECT = 'ome-auth-e2e'
DOMAIN = 'ome-auth.test'
PDS_IMAGE = 'ghcr.io/bluesky-social/pds@sha256:05e164855fa1a3cf251c002210c46f8c86e7ae27bddc7a96045da25483840826'


def run(*args):
    subprocess.run(args, cwd=UPSTREAM, check=True)


def sandbox(*args):
    run('deno', 'task', 'sandbox', *args)


def configure_appview():
    """Update services without recreating the PDS, CA, or sandbox identities."""
    shutil.copytree(SOURCE / 'pds', UPSTREAM / 'ome-pds', dirs_exist_ok=True)
    (UPSTREAM / 'stacks/ome-auth.definition.json').write_text(json.dumps({
        'version': 1, 'id': 'ome-auth',
        'services': [{'service': 'ome-metadata', 'environment': []}],
        'routes': [{'id': 'metadata', 'service': 'ome-metadata', 'host': 'metadata', 'port': 8080}],
        'secrets': [],
    }, indent=2) + '\n')
    # Retain the service name so Compose replaces the old Node fixture in place.
    (UPSTREAM / 'stacks/ome-auth.yaml').write_text(f"""services:
  ome-metadata:
    image: ome-auth-e2e-appview:local
    environment:
      OME_OAUTH_CLIENT: private-authentication
      OME_APPVIEW_PUBLIC_HOST: metadata.ome-auth.test
      OME_APPVIEW_DATABASE_PATH: /data/appview.sqlite
    volumes: [ome-appview-data:/data]
    read_only: true
    tmpfs: [/tmp]
    cap_drop: [ALL]
    security_opt: [no-new-privileges:true]
    healthcheck:
      test: [CMD, curl, --fail, --silent, http://127.0.0.1:8080/healthz]
      interval: 5s
      timeout: 3s
      retries: 20
volumes:
  ome-appview-data:
""")


def prepare():
    STATE.mkdir(parents=True, exist_ok=True, mode=0o700)
    if (UPSTREAM / 'state/manifest.json').exists():
        raise SystemExit('Already prepared. Use check/up/down; existing identities are preserved.')
    archive = STATE / f'{REVISION}.tar.gz'
    if not archive.exists():
        urllib.request.urlretrieve(
            f'https://tangled.org/kandake.africa/atmosphereinabox/archive/{REVISION}.tar.gz', archive)
    if hashlib.sha256(archive.read_bytes()).hexdigest() != ARCHIVE_SHA256:
        raise SystemExit('Upstream archive checksum mismatch')
    with tarfile.open(archive) as bundle:
        bundle.extractall(STATE, filter='data')
    shutil.copytree(SOURCE / 'pds', UPSTREAM / 'ome-pds', dirs_exist_ok=True)
    networking = UPSTREAM / 'compose/networking.yaml'
    networking.write_text(networking.read_text().replace(
        '    networks: [atmosinabox, host-access]',
        '    networks:\n      atmosinabox: {priority: 0}\n      host-access: {priority: 100, gw_priority: 1}'))
    pds = UPSTREAM / 'compose/pds.yaml'
    content = pds.read_text()
    image = 'image: ghcr.io/bluesky-social/pds:0.4@sha256:' + PDS_IMAGE.split('@sha256:')[1]
    if content.count(image) != 1:
        raise SystemExit('Pinned PDS compose source changed')
    pds.write_text(content.replace(image, 'build: {context: ./ome-pds}\n    image: ome-auth-e2e-pds:0.5.34-60s'))
    components = UPSTREAM / 'stacks/components.json'
    entries = json.loads(components.read_text())
    entries.append(dict(id='ome-auth', file='stacks/ome-auth.yaml', application='ome-auth',
                        definition='stacks/ome-auth.definition.json'))
    components.write_text(json.dumps(entries, indent=2) + '\n')
    configure_appview()
    manifest = {
        'version': 1, 'project': PROJECT, 'domain': DOMAIN,
        'subnet': '172.30.248.0/24', 'plc': f'https://plc.{DOMAIN}',
        'applications': ['ome-auth'],
        'pds': [{'id': 'pds1', 'hostname': f'pds1.{DOMAIN}', 'url': f'https://pds1.{DOMAIN}',
                 # Declarations provision routing only. Accounts must be created through OME.
                 'users': [{'handle': f'{name}.pds1.{DOMAIN}', 'email': f'{name}@{DOMAIN}'}
                           for name in ['ios-tester', 'android-tester']]}],
    }
    (UPSTREAM / 'ome-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    run('deno', 'task', 'install')
    sandbox('create', '--manifest', 'ome-manifest.json')
    sandbox('check')
    (STATE / 'provenance.json').write_text(json.dumps({
        'revision': REVISION, 'archiveSHA256': hashlib.sha256(archive.read_bytes()).hexdigest(),
        'pdsImage': PDS_IMAGE, 'accessTokenAgeSeconds': 60, 'project': PROJECT,
    }, indent=2) + '\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['prepare', 'up', 'check', 'access', 'hosts', 'access-start', 'access-stop', 'down', 'reset'])
    command = parser.parse_args().command
    if command == 'prepare':
        prepare()
        return
    if not (UPSTREAM / 'state/manifest.json').exists():
        parser.error('Run prepare first')
    if command == 'reset':
        sandbox('destroy', '--accept-destructive')
        prepare()
        return
    if command == 'up':
        subprocess.run([sys.executable, str(SOURCE / 'build-appview.py')], check=True)
        configure_appview()
        sandbox('apply')
        sandbox('up', '--build')
    elif command == 'access':
        sandbox('access', '--json')
    elif command == 'hosts':
        sandbox('access', 'hosts')
    elif command.startswith('access-'):
        sandbox('access', command.removeprefix('access-'))
    else:
        sandbox(command)


if __name__ == '__main__':
    main()
