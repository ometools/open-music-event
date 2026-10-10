#!/usr/bin/env python3
"""Build the local globe AppView image without persisting the GitHub credential."""
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def package_root(name):
    ometools = ROOT.parent.parent if ROOT.parent.name == 'worktrees' else ROOT.parent
    return ometools / 'worktrees' / name


def atmosphere_root():
    configured = os.environ.get('OME_COMPOSABLE_ATMOSPHERE_PATH')
    candidates = [
        Path(configured).resolve() if configured else None,
        Path('/Users/woody/Developer/swift-packages/swift-composable-atmosphere-reorg-auth'),
        package_root('atmosphere-publication-android') / 'swift-composable-atmosphere-reorg-auth',
    ]
    return next((path for path in candidates if path and (path / 'Package.swift').exists()), None)


def main():
    ometools = ROOT.parent.parent if ROOT.parent.name == 'worktrees' else ROOT.parent
    contexts = {
        'ome-atmosphere': atmosphere_root(),
        'ome-userinput': package_root('composable-atmosphere-userinput-reorg'),
        'ome-workspace': package_root('swift-composable-workspace-atmosphere-reorg'),
        'ome-constellation': package_root('composable-atmosphere-constellation-reorg'),
        'ome-tangled': package_root('composable-atmosphere-tangled-reorg'),
        'ome-calendar': package_root('composable-calendar-events-reorg'),
        'ome-notifications': package_root('swift-composable-notifications-atmosphere-reorg'),
        'ome-forms': package_root('swift-composable-forms-atmosphere-reorg'),
        'ome-hero-images': ometools / 'swift-hero-image-list',
    }
    missing = [name for name, path in contexts.items() if not path or not (path / 'Package.swift').exists()]
    if missing:
        raise SystemExit('Missing local AppView build contexts: ' + ', '.join(missing))
    token = os.environ.get('GITHUB_TOKEN') or subprocess.check_output(
        ['gh', 'auth', 'token'], text=True, stderr=subprocess.DEVNULL).strip()
    if not token or any(character.isspace() for character in token):
        raise SystemExit('A valid GitHub token is required to build the AppView image.')
    with tempfile.TemporaryDirectory(prefix='ome-globe-appview-') as directory:
        credential = Path(directory) / 'netrc'
        credential.touch(mode=0o600)
        credential.write_text(
            f'machine github.com\nlogin x-access-token\npassword {token}\n'
        )
        command = [
            'docker', 'build', '--secret', f'id=github_netrc,src={credential}',
        ]
        for name, path in contexts.items():
            command += ['--build-context', f'{name}={path}']
        command += [
            '-f', 'Scripts/auth-e2e/appview/Dockerfile',
            '-t', 'ome-globe-appview:local', '.',
        ]
        subprocess.run(command, cwd=ROOT, check=True)


if __name__ == '__main__':
    main()
