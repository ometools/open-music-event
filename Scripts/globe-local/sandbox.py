#!/usr/bin/env python3
"""One local PDS with one durable account/DID per sample venue."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import signal
import socket
import subprocess
import sys
import tarfile
import time
import urllib.request

ARCHIVE_SHA256 = 'f6fbc8d72316aa4a553ecf4ab2ce0201eeb802ea284715f7b976c2896984d383'
REVISION = '26cf1f60f81b491b065dfc830efd27aba8b89a54'
ROOT = Path(__file__).resolve().parents[2]
SOURCE = Path(__file__).resolve().parent
STATE = Path(os.environ.get('OME_GLOBE_STATE_DIRECTORY', ROOT / '.build/globe-local')).resolve()
UPSTREAM = STATE / f'atmosphereinabox-{REVISION}'
PROJECT = 'ome-globe'
DOMAIN = 'ome-globe.test'
LANE = Path.home() / '.codex/skills/woodys-swift-workflow/scripts/swift-compiler-lane.sh'
BROWSER_PORT = 18081
BROWSER_PID = STATE / 'browser-http-proxy.pid'
BROWSER_LOG = STATE / 'browser-http-proxy.log'


def run(*args):
    subprocess.run(args, cwd=UPSTREAM, check=True)


def sandbox(*args):
    run('deno', 'task', 'sandbox', *args)


def running_browser_proxy_pid():
    try:
        request = urllib.request.Request(f'http://127.0.0.1:{BROWSER_PORT}/healthz')
        opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
        with opener.open(request, timeout=1) as response:
            if response.headers.get('X-OME-Globe-Loopback-Proxy') != '1':
                return None
            return int(response.headers['X-OME-Globe-Loopback-PID'])
    except (KeyError, OSError, ValueError):
        return None


def start_browser_proxy():
    if running_browser_proxy_pid() is not None:
        print(f'Globe browser already available at http://127.0.0.1:{BROWSER_PORT}/')
        return
    try:
        with socket.create_connection(('127.0.0.1', BROWSER_PORT), timeout=0.2):
            raise SystemExit(f'Port {BROWSER_PORT} is already used by another process.')
    except ConnectionRefusedError:
        pass
    ca = UPSTREAM / 'state/ca/root.crt'
    if not ca.exists():
        raise SystemExit('The sandbox public CA is unavailable; run up first.')
    BROWSER_LOG.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    with BROWSER_LOG.open('ab') as log:
        process = subprocess.Popen([
            sys.executable, str(SOURCE / 'browser_http_proxy.py'),
            '--ca-certificate', str(ca),
            '--listen-port', str(BROWSER_PORT),
        ], stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
    BROWSER_PID.write_text(f'{process.pid}\n')
    for _ in range(50):
        if process.poll() is not None:
            raise SystemExit(f'Globe browser proxy stopped during startup; see {BROWSER_LOG}.')
        if running_browser_proxy_pid() == process.pid:
            print(f'Globe browser available at http://127.0.0.1:{BROWSER_PORT}/')
            return
        time.sleep(0.1)
    process.terminate()
    process.wait()
    raise SystemExit(f'Globe browser proxy did not start; see {BROWSER_LOG}.')


def stop_browser_proxy():
    if not BROWSER_PID.exists():
        return
    try:
        pid = int(BROWSER_PID.read_text().strip())
    except ValueError:
        raise SystemExit(f'Invalid browser proxy PID file: {BROWSER_PID}')
    running_pid = running_browser_proxy_pid()
    if running_pid is not None:
        if running_pid != pid:
            raise SystemExit(
                f'Browser proxy PID mismatch: state records {pid}, but port {BROWSER_PORT} belongs to {running_pid}.'
            )
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        for _ in range(50):
            if running_browser_proxy_pid() is None:
                break
            time.sleep(0.1)
        else:
            raise SystemExit(f'Browser proxy process {pid} did not stop.')
    BROWSER_PID.unlink(missing_ok=True)


def accounts():
    path = UPSTREAM / 'state/accounts.json'
    if not path.exists():
        return {}
    return json.loads(path.read_text())['accounts']


def configure_appview():
    entries = json.loads((UPSTREAM / 'stacks/components.json').read_text())
    entries = [entry for entry in entries if entry.get('id') != 'ome-globe-egress']
    application = {
        'id': 'ome-globe', 'file': 'stacks/ome-globe.yaml',
        'application': 'ome-globe',
        'definition': 'stacks/ome-globe.definition.json',
    }
    for index, entry in enumerate(entries):
        if entry.get('id') == 'ome-globe':
            entries[index] = application
            break
    else:
        entries.append(application)
    entries.append({'id': 'ome-globe-egress', 'file': 'stacks/ome-globe-egress.yaml'})
    (UPSTREAM / 'stacks/components.json').write_text(json.dumps(entries, indent=2) + '\n')
    proxy_path = UPSTREAM / 'ome-globe-public-https-proxy.py'
    if proxy_path.is_dir():
        proxy_path.rmdir()
    shutil.copyfile(SOURCE / 'public_https_proxy.py', proxy_path)
    (UPSTREAM / 'stacks/ome-globe-egress.yaml').write_text('''services:
  public-network-relay:
    image: caddy:2.11.4-alpine
    command: [caddy, reverse-proxy, --from, :8080, --to, https://bsky.network, --change-host-header]
    read_only: true
    tmpfs: [/config, /data, /tmp]
    cap_drop: [ALL]
    cap_add: [NET_BIND_SERVICE]
    security_opt: [no-new-privileges:true]
    networks: [atmosinabox, ome-globe-egress]
  public-plc-relay:
    image: caddy:2.11.4-alpine
    command: [caddy, reverse-proxy, --from, :8082, --to, https://plc.directory, --change-host-header]
    read_only: true
    tmpfs: [/config, /data, /tmp]
    cap_drop: [ALL]
    cap_add: [NET_BIND_SERVICE]
    security_opt: [no-new-privileges:true]
    networks: [atmosinabox, ome-globe-egress]
  public-https-proxy:
    image: python:3.13-alpine
    command: [python3, /proxy.py]
    read_only: true
    tmpfs: [/tmp]
    volumes: [./ome-globe-public-https-proxy.py:/proxy.py:ro]
    cap_drop: [ALL]
    security_opt: [no-new-privileges:true]
    networks: [atmosinabox, ome-globe-egress]
networks:
  ome-globe-egress: {}
''')
    ready = {
        entry['did']: f'pds1.{DOMAIN}'
        for entry in accounts().values()
        if entry.get('phase') == 'ready' and entry.get('did')
    }
    (UPSTREAM / 'stacks/ome-globe.definition.json').write_text(json.dumps({
        'version': 1,
        'id': 'ome-globe',
        'services': [
            {'service': 'ome-globe-appview', 'environment': []},
            {'service': 'hydrant-private', 'environment': []},
            {'service': 'hydrant-public', 'environment': []},
        ],
        'routes': [
            {'id': 'globe', 'service': 'ome-globe-appview', 'host': 'metadata', 'port': 8080}
        ],
        'secrets': [],
    }, indent=2) + '\n')
    bindings = json.dumps(ready, separators=(',', ':'))
    ingestions = json.dumps([
        {'endpoint': 'ws://hydrant-private:3000/stream', 'subscriptionID': 'private-venues'},
        {'endpoint': 'ws://hydrant-public:3000/stream', 'subscriptionID': 'public-community-calendar'},
    ], separators=(',', ':'))
    geocoding_overrides = json.dumps({
        '3901 Kootenay Hwy, Fairmont Hot Springs, BC V0B 1L1, Canada': {
            'latitude': 50.3659721, 'longitude': -115.870314,
        },
        '2496 East River Road, Livingston, MT 59047': {
            'latitude': 45.50765, 'longitude': -110.56357,
        },
        'Salmo River Ranch, 7790 Hwy 3, Salmo, BC, V0G 1Z0, Canada': {
            'latitude': 49.141946, 'longitude': -117.264095,
        },
        # Shambhala 2026 currently publishes stage names but no ranch address.
        'Ampitheatre': {
            'latitude': 49.141946, 'longitude': -117.264095,
        },
        'Uptown Butte, Butte, MT': {
            'latitude': 46.0124, 'longitude': -112.5382,
        },
        '422 East Mendenhall Street, Bozeman, MT 59715': {
            'latitude': 45.68020, 'longitude': -111.03126,
        },
    }, separators=(',', ':'))
    (UPSTREAM / 'stacks/ome-globe.yaml').write_text(f'''services:
  ome-globe-appview:
    image: ome-globe-appview:local
    environment:
      OME_APPVIEW_PUBLIC_HOST: metadata.{DOMAIN}
      OME_APPVIEW_DATABASE_PATH: /data/appview.sqlite
      OME_APPVIEW_HYDRANT_CONFIGURATIONS: '{ingestions}'
      OME_WEB_PDS_HOSTS: '{bindings}'
      GEOAPIFY_API_KEY: '${{GEOAPIFY_API_KEY:-}}'
      OME_APPVIEW_GEOCODING_OVERRIDES: '{geocoding_overrides}'
    volumes: [ome-globe-appview-data:/data]
    read_only: true
    tmpfs: [/tmp]
    cap_drop: [ALL]
    security_opt: [no-new-privileges:true]
    healthcheck:
      test: [CMD, curl, --fail, --silent, http://127.0.0.1:8080/healthz]
      interval: 5s
      timeout: 3s
      retries: 30
    depends_on:
      hydrant-private: {{condition: service_started}}
      hydrant-public: {{condition: service_started}}
  hydrant-private:
    image: '${{OME_GLOBE_HYDRANT_IMAGE:-ome-publication-hydrant:local}}'
    environment:
      HYDRANT_RELAY_HOSTS: pds::wss://pds1.{DOMAIN}
      HYDRANT_PLC_URL: https://plc.{DOMAIN}
      HYDRANT_FULL_NETWORK: 'false'
      HYDRANT_ENABLE_CRAWLER: 'false'
      HYDRANT_CRAWLER_URLS: ''
      HYDRANT_FILTER_COLLECTIONS: events.openmusic.event,events.openmusic.eventPlace,events.openmusic.contributor,events.openmusic.program,events.openmusic.schedule,events.openmusic.programItem,social.ome.category,social.ome.post,app.bsky.actor.profile
      HYDRANT_FILTER_SIGNALS: events.openmusic.event,events.openmusic.eventPlace,events.openmusic.contributor,events.openmusic.program,events.openmusic.schedule,events.openmusic.programItem,social.ome.category,social.ome.post,app.bsky.actor.profile
      HYDRANT_VERIFY_SIGNATURES: full
      HYDRANT_VERIFY_CIDS: 'true'
      HYDRANT_API_BIND: 0.0.0.0:3000
      HYDRANT_DATABASE_PATH: /data/hydrant.db
      SSL_CERT_FILE: /ca/root.crt
    volumes: [ome-globe-private-hydrant-data:/data]
    depends_on:
      pds1: {{condition: service_started}}
  hydrant-public:
    image: '${{OME_GLOBE_HYDRANT_IMAGE:-ome-publication-hydrant:local}}'
    environment:
      HYDRANT_RELAY_HOSTS: ws://public-network-relay:8080
      HYDRANT_PLC_URL: http://public-plc-relay:8082
      HYDRANT_FULL_NETWORK: 'false'
      HYDRANT_ENABLE_CRAWLER: 'true'
      HYDRANT_CRAWLER_URLS: by_collection::http://public-network-relay:8080
      HYDRANT_FILTER_COLLECTIONS: community.lexicon.calendar.event
      HYDRANT_FILTER_SIGNALS: community.lexicon.calendar.event
      HYDRANT_VERIFY_SIGNATURES: full
      HYDRANT_VERIFY_CIDS: 'true'
      HYDRANT_BACKFILL_PROXIES: http://public-https-proxy:8081
      HTTPS_PROXY: http://public-https-proxy:8081
      HYDRANT_API_BIND: 0.0.0.0:3000
      HYDRANT_DATABASE_PATH: /data/hydrant.db
    volumes: [ome-globe-public-hydrant-data:/data]
    depends_on:
      public-network-relay: {{condition: service_started}}
      public-plc-relay: {{condition: service_started}}
      public-https-proxy: {{condition: service_started}}
volumes:
  ome-globe-appview-data:
  ome-globe-private-hydrant-data:
  ome-globe-public-hydrant-data:
''')


def prepare():
    STATE.mkdir(parents=True, exist_ok=True, mode=0o700)
    if (UPSTREAM / 'state/manifest.json').exists():
        if (STATE / 'provenance.json').exists():
            raise SystemExit('Already prepared. Existing venue identities are preserved.')
        configure_appview()
        sandbox('apply')
        sandbox('check')
        (STATE / 'provenance.json').write_text(json.dumps({
            'revision': REVISION,
            'archiveSHA256': ARCHIVE_SHA256,
            'project': PROJECT,
        }, indent=2) + '\n')
        return
    archive = STATE / f'{REVISION}.tar.gz'
    if not archive.exists():
        urllib.request.urlretrieve(
            f'https://tangled.org/kandake.africa/atmosphereinabox/archive/{REVISION}.tar.gz',
            archive,
        )
    if hashlib.sha256(archive.read_bytes()).hexdigest() != ARCHIVE_SHA256:
        raise SystemExit('Upstream archive checksum mismatch')
    if not UPSTREAM.exists():
        with tarfile.open(archive) as bundle:
            bundle.extractall(STATE, filter='data')
    configure_appview()
    venues = json.loads((SOURCE / 'venues.json').read_text())['venues']
    manifest = {
        'version': 1, 'project': PROJECT, 'domain': DOMAIN,
        'subnet': '172.30.247.0/24', 'plc': f'https://plc.{DOMAIN}',
        'applications': ['ome-globe'],
        'pds': [{
            'id': 'pds1', 'hostname': f'pds1.{DOMAIN}', 'url': f'https://pds1.{DOMAIN}',
            'users': [
                {'handle': f"{venue['accountLabel']}.pds1.{DOMAIN}",
                 'email': f"{venue['slug']}@{DOMAIN}"}
                for venue in venues
            ],
        }],
    }
    (UPSTREAM / 'ome-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    run('deno', 'task', 'install')
    sandbox('create', '--manifest', 'ome-manifest.json')
    sandbox('check')
    (STATE / 'provenance.json').write_text(json.dumps({
        'revision': REVISION,
        'archiveSHA256': hashlib.sha256(archive.read_bytes()).hexdigest(),
        'project': PROJECT,
    }, indent=2) + '\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=[
        'prepare', 'apply', 'up', 'seed', 'sync', 'check', 'access', 'hosts',
        'access-start', 'access-stop', 'browser-start', 'browser-stop', 'down', 'ps',
    ])
    command = parser.parse_args().command
    if command == 'prepare':
        prepare()
        return
    if not (UPSTREAM / 'state/manifest.json').exists():
        parser.error('Run prepare first')
    if command == 'up':
        subprocess.run([
            str(LANE), '--repo', str(ROOT), '--wait', '--priority', 'normal',
            'exec', sys.executable, str(SOURCE / 'build-appview.py'),
        ], check=True)
        configure_appview()
        sandbox('apply')
        sandbox('up', '--build')
        sandbox('access', 'start')
        start_browser_proxy()
    elif command == 'apply':
        configure_appview()
        sandbox('apply')
    elif command == 'seed':
        sandbox('seed')
        configure_appview()
        sandbox('apply')
        sandbox('up')
    elif command == 'sync':
        subprocess.run([sys.executable, str(SOURCE / 'sync.py')], check=True)
    elif command == 'browser-start':
        sandbox('access', 'start')
        start_browser_proxy()
    elif command == 'browser-stop':
        stop_browser_proxy()
    elif command == 'access':
        sandbox('access', '--json')
    elif command == 'hosts':
        sandbox('access', 'hosts')
    elif command.startswith('access-'):
        if command == 'access-stop':
            stop_browser_proxy()
        sandbox('access', command.removeprefix('access-'))
    elif command == 'down':
        stop_browser_proxy()
        sandbox('down')
    else:
        sandbox(command)


if __name__ == '__main__':
    main()
