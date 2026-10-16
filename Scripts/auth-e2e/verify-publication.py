#!/usr/bin/env python3
"""Anonymous verification only. Every Event/blob write must originate in the app."""
import argparse
import base64
import hashlib
import json
from pathlib import Path
import ssl
import time
import urllib.error
import urllib.parse
import urllib.request


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--ca', type=Path, required=True)
    parser.add_argument('--event-uri', required=True)
    parser.add_argument('--minimal-uri', required=True)
    parser.add_argument('--description', required=True)
    parser.add_argument('--image', type=Path, required=True)
    parser.add_argument('--alt', required=True)
    parser.add_argument('--previous', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    opener = urllib.request.build_opener(
        urllib.request.ProxyHandler({}),
        urllib.request.HTTPSHandler(context=ssl.create_default_context(cafile=str(args.ca))),
    )

    def get(host, method, **query):
        url = f'https://{host}/xrpc/{method}?' + urllib.parse.urlencode(query)
        with opener.open(url, timeout=10) as response:
            if response.url != url:
                raise ValueError('Verification must not redirect outside the private endpoint')
            return response.read()

    def record(uri):
        parts = urllib.parse.urlsplit(uri)
        collection, key = parts.path.strip('/').split('/')
        if parts.scheme != 'at' or not parts.netloc.startswith('did:') or collection != 'events.openmusic.event':
            raise ValueError('Expected an Event URI with a DID authority')
        result = json.loads(get('pds1.ome-auth.test', 'com.atproto.repo.getRecord',
                                repo=parts.netloc, collection=collection, rkey=key))
        if result['uri'] != uri:
            raise ValueError('PDS returned a different Event URI')
        return result, parts.netloc

    rich, publisher = record(args.event_uri)
    minimal, minimal_publisher = record(args.minimal_uri)
    if publisher != minimal_publisher or rich['uri'] == minimal['uri']:
        raise ValueError('Expected two distinct Events in one publisher repository')
    value = rich['value']
    if value.get('description') != args.description or value.get('timeZone') != 'America/Denver':
        raise ValueError('Published description or time zone does not match the reviewed Testival')
    if not value.get('start') or not value.get('end') or not value.get('locations') or not value.get('links'):
        raise ValueError('Testival is missing dates, location, or links')
    images = [m for m in value.get('media', []) if m.get('$type') == 'events.openmusic.defs#image']
    image = next((m for m in images if m.get('alt') == args.alt), None)
    if image is None or image.get('source', {}).get('$type') != 'events.openmusic.defs#imageBlob':
        raise ValueError('Expected the reviewed image with alt text and a blob reference')
    blob = image['source']['blob']
    cid = blob['ref']['$link']
    expected = args.image.read_bytes()
    observed = get('pds1.ome-auth.test', 'com.atproto.sync.getBlob', did=publisher, cid=cid)
    expected_cid = 'b' + base64.b32encode(b'\x01\x55\x12\x20' + hashlib.sha256(expected).digest()).decode().lower().rstrip('=')
    if observed != expected or cid != expected_cid or blob['size'] != len(expected):
        raise ValueError('Anonymous blob bytes, CID, or size do not match the reviewed image')
    if any(minimal['value'].get(k) for k in ['description', 'media', 'start', 'end', 'locations', 'links']):
        raise ValueError('Minimal fixture unexpectedly contains optional content')
    for result in [rich, minimal]:
        deadline = time.monotonic() + 60
        while True:
            try:
                indexed = json.loads(get('metadata.ome-auth.test', 'events.openmusic.getEvent', uri=result['uri']))
                if indexed['cid'] == result['cid'] and indexed['value'] == result['value']:
                    break
            except urllib.error.HTTPError as error:
                if error.code != 404:
                    raise
            if time.monotonic() >= deadline:
                raise TimeoutError('AppView did not return the exact published Event CID and payload')
            time.sleep(1)
    if args.previous:
        previous = json.loads(args.previous.read_text())
        if previous['event']['uri'] != rich['uri'] or previous['event']['value']['createdAt'] != value['createdAt']:
            raise ValueError('Replacement changed Event identity or creation timestamp')
        if previous['event']['cid'] == rich['cid'] or previous['blob']['ref'] == blob['ref']:
            raise ValueError('Replacement did not change both record and blob CIDs')
    # This report intentionally makes no claim about the UI or either reader platform.
    report = dict(event=rich, minimal=minimal, blob=blob,
                  imageSHA256=hashlib.sha256(observed).hexdigest(),
                  anonymousBlobReadback=True, exactAppViewIngestion=True)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open('x') as output:
        json.dump(report, output, indent=2)
        output.write('\n')
    print('PDS records, anonymous image bytes, and exact AppView ingestion verified: ' + str(args.output))


if __name__ == '__main__':
    main()
