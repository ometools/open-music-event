#!/usr/bin/env python3
"""Install the one-time macOS resolver; retain hosts helpers for Android routing."""
import argparse
import os
import json
import re
from pathlib import Path

BEGIN = '# BEGIN OME AUTH E2E'
END = '# END OME AUTH E2E'
RESOLVER = Path('/etc/resolver/ome-auth.test')
RESOLVER_CONTENT = '# OME AUTH E2E domain resolver\nnameserver 127.0.0.1\nport 1053\ntimeout 2\n'
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


def install_resolver(resolver=RESOLVER, hosts=Path('/etc/hosts'), remove=False):
    # Refuse to overwrite someone else's domain resolver or a symlink.
    if resolver.is_symlink() or (resolver.exists() and resolver.read_text() != RESOLVER_CONTENT):
        raise ValueError(f'Unrecognized resolver at {resolver}; refusing to overwrite it')
    if hosts.is_symlink():
        raise ValueError('Refusing to replace a symlinked hosts file')
    original = hosts.read_text()
    cleaned = updated(original, False) if BEGIN in original or END in original else original
    if remove:
        if resolver.exists():
            resolver.unlink()
    else:
        import tempfile
        resolver.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.NamedTemporaryFile(mode='w', dir=resolver.parent, delete=False) as temporary:
            temporary.write(RESOLVER_CONTENT)
            name = temporary.name
        os.chmod(name, 0o644)
        os.replace(name, resolver)
    if cleaned != original:
        hosts.write_text(cleaned)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['print', 'install', 'remove'])
    args = parser.parse_args()
    if args.command == 'print':
        print(RESOLVER_CONTENT, end='')
    elif os.geteuid() != 0:
        parser.error('The one-time macOS resolver installation/removal requires sudo.')
    else:
        install_resolver(remove=args.command == 'remove')
        print('Removed OME domain resolver.' if args.command == 'remove' else
              'Installed OME domain resolver; future runs require no Mac hosts edits.')
