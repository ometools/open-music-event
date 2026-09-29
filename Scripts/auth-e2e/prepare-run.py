#!/usr/bin/env python3
"""Provision DNS and HTTPS for UI-created accounts without creating or deleting accounts."""
import argparse
import importlib.util
from pathlib import Path
import subprocess
from sandbox import PROJECT, UPSTREAM

spec = importlib.util.spec_from_file_location('hosts', Path(__file__).with_name('host-routing.py'))
hosts = importlib.util.module_from_spec(spec)
spec.loader.exec_module(hosts)


def routes(caddy, core, handles):
    caddy_lines, core_lines = caddy.splitlines(), core.splitlines()
    sites = [i for i, line in enumerate(caddy_lines) if line.startswith('pds1.ome-auth.test,')]
    records = [i for i, line in enumerate(core_lines) if ' pds1.ome-auth.test ' in line]
    if len(sites) != 1 or len(records) != 1:
        raise ValueError('Unexpected private gateway/DNS configuration; refusing to rewrite it')
    index = sites[0]
    names = [name.strip() for name in caddy_lines[index].removesuffix(' {').split(',')]
    caddy_lines[index] = ', '.join(dict.fromkeys([*names, *handles])) + ' {'
    index = records[0]
    core_lines[index] = '    ' + ' '.join(dict.fromkeys([*core_lines[index].split(), *handles]))
    return '\n'.join(caddy_lines) + '\n', '\n'.join(core_lines) + '\n'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('run', type=Path)
    parser.add_argument('--android-device', required=True)
    args = parser.parse_args()
    handles = hosts.handles_for_run(args.run)
    caddy, core = UPSTREAM / 'state/Caddyfile', UPSTREAM / 'state/Corefile'
    updated_caddy, updated_core = routes(caddy.read_text(), core.read_text(), handles)
    changed = updated_caddy != caddy.read_text() or updated_core != core.read_text()
    if changed:
        caddy.write_text(updated_caddy)
        core.write_text(updated_core)
        subprocess.run(['docker', 'restart', PROJECT + '-dns-1', PROJECT + '-gateway-1'], check=True)
    subprocess.run(['python3', str(Path(__file__).with_name('configure-android.py')),
                    '--device', args.android_device, '--run', str(args.run)], check=True)
    print('Private gateway, DNS and emulator routes prepared; PDS accounts and CA preserved.')
    print('Install the matching Mac host block, then resume this run:')
    import shlex
    print(shlex.join(['sudo', '/opt/homebrew/bin/python3', str(Path(__file__).with_name('host-routing.py').resolve()),
                      'install', '--run', str(args.run.resolve())]))


if __name__ == '__main__':
    main()
