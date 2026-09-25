#!/usr/bin/env python3
"""Print, install, or remove only OME's private host routing block."""
import argparse
import os
from pathlib import Path

BEGIN = '# BEGIN OME AUTH E2E'
END = '# END OME AUTH E2E'
HOSTS = ['plc.ome-auth.test', 'pds1.ome-auth.test', 'metadata.ome-auth.test',
         'ios-tester.pds1.ome-auth.test', 'android-tester.pds1.ome-auth.test']
BLOCK = BEGIN + '\n' + '\n'.join('127.0.0.1 ' + host for host in HOSTS) + '\n' + END + '\n'


def updated(contents, install):
    if (BEGIN in contents) != (END in contents) or contents.count(BEGIN) > 1:
        raise ValueError('Malformed OME routing block; refusing to edit hosts')
    if BEGIN in contents:
        start, end = contents.index(BEGIN), contents.index(END) + len(END)
        if end < start:
            raise ValueError('Malformed OME routing block')
        contents = contents[:start] + contents[end:].lstrip('\n')
    return contents.rstrip('\n') + '\n' + (BLOCK if install else '')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['print', 'install', 'remove'])
    command = parser.parse_args().command
    if command == 'print':
        print(BLOCK, end='')
    elif os.geteuid() != 0:
        parser.error('Installing/removing host routing requires an administrator. Run with sudo.')
    else:
        hosts = Path('/etc/hosts')
        hosts.write_text(updated(hosts.read_text(), command == 'install'))
