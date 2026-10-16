#!/usr/bin/env python3
"""Build the real AppView with an ephemeral, build-only GitHub credential."""
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def main():
    token = os.environ.get('GITHUB_TOKEN') or subprocess.check_output(
        ['gh', 'auth', 'token'], text=True, stderr=subprocess.DEVNULL).strip()
    if not token or any(character.isspace() for character in token):
        raise SystemExit('A valid GitHub token is required to fetch the pinned private TCA dependency.')
    with tempfile.TemporaryDirectory(prefix='ome-appview-build-') as directory:
        credential = Path(directory) / 'netrc'
        credential.touch(mode=0o600)
        credential.write_text(f'machine github.com\nlogin x-access-token\npassword {token}\n')
        command = ['docker', 'build',
            '--secret', f'id=github_netrc,src={credential}',
            '-f', 'Scripts/auth-e2e/appview/Dockerfile',
            '-t', 'ome-auth-e2e-appview:local', '.',
        ]
        if lane := os.environ.get('OME_COMPILER_LANE'):
            command = [lane, '--repo', str(ROOT), '--wait', '--priority', 'interactive', 'exec', *command]
        subprocess.run(command, cwd=ROOT, check=True)


if __name__ == '__main__':
    main()
