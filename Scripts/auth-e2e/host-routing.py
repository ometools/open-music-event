#!/usr/bin/env python3
"""Print, install, or remove only OME's private host routing block."""
import argparse
import os
import json
import re
from pathlib import Path

BEGIN = '# BEGIN OME AUTH E2E'
END = '# END OME AUTH E2E'
HOSTS = ['plc.ome-auth.test', 'pds1.ome-auth.test', 'metadata.ome-auth.test',
         'ios-tester.pds1.ome-auth.test', 'android-tester.pds1.ome-auth.test']
def block(extra_hosts=()):
    names = list(dict.fromkeys([*HOSTS, *extra_hosts]))
    return BEGIN + '\n' + '\n'.join('127.0.0.1 ' + host for host in names) + '\n' + END + '\n'


BLOCK = block()


def handles_for_run(directory):
    if directory is None:
        return []
    directory = Path(directory).resolve()
    runs = Path(__file__).resolve().parents[2] / '.build/auth-e2e/runs'
    if directory.parent != runs.resolve():
        raise ValueError('Expected a run directory inside this workspace')
    identities = json.loads((directory / 'report.json').read_text())['identities']
    if set(identities) != {'ios', 'android'}:
        raise ValueError('Expected exactly the iOS and Android test identities')
    names = list(identities.values())
    if any(not isinstance(name, str) or not re.fullmatch(r'[a-z][a-z0-9-]{0,16}[a-z0-9]', name)
           for name in names):
        raise ValueError('Invalid private test username')
    return [name + '.pds1.ome-auth.test' for name in names]



def updated(contents, install, extra_hosts=()):
    if (BEGIN in contents) != (END in contents) or contents.count(BEGIN) > 1:
        raise ValueError('Malformed OME routing block; refusing to edit hosts')
    if BEGIN in contents:
        start, end = contents.index(BEGIN), contents.index(END) + len(END)
        if end < start:
            raise ValueError('Malformed OME routing block')
        contents = contents[:start] + contents[end:].lstrip('\n')
    return contents.rstrip('\n') + '\n' + (block(extra_hosts) if install else '')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['print', 'install', 'remove'])
    parser.add_argument('--run', type=Path, help='Also route the two account handles in this prepared run')
    args = parser.parse_args()
    command = args.command
    extra_hosts = handles_for_run(args.run)
    if command == 'print':
        print(block(extra_hosts), end='')
    elif os.geteuid() != 0:
        parser.error('Installing/removing host routing requires an administrator. Run with sudo.')
    else:
        hosts = Path('/etc/hosts')
        hosts.write_text(updated(hosts.read_text(), command == 'install', extra_hosts))
