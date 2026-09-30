#!/usr/bin/env python3
"""Real UI recovery and multi-account stories using accounts created by a passed run."""
import argparse
import datetime
import json
import re
import subprocess
import time
import threading
from contextlib import contextmanager
from pathlib import Path
import run as auth
from sandbox import PROJECT

PDS = PROJECT + '-pds1-1'
CLIENT = 'https://metadata.ome-auth.test/oauth-client-metadata.json'


def pds_database(script, *arguments):
    # Fixed private container/database. Scripts never select credential values.
    return json.loads(subprocess.check_output(
        ['docker', 'exec', PDS, 'node', '-e', script, *arguments], text=True))


def account_for_handle(handle):
    return pds_database('''const {DatabaseSync}=require('node:sqlite');
const db=new DatabaseSync('/data/account.sqlite',{readOnly:true});
const row=db.prepare('SELECT did, handle FROM actor WHERE handle = ?').get(process.argv[1]);
if (!row) throw Error('Test account does not exist');
console.log(JSON.stringify(row));''', handle)


def revoke_account(account):
    return pds_database('''const {DatabaseSync}=require('node:sqlite');
const db=new DatabaseSync('/data/account.sqlite');
db.exec('PRAGMA foreign_keys=ON; BEGIN IMMEDIATE');
const row=db.prepare('SELECT did FROM actor WHERE did=? AND handle=?').get(process.argv[1],process.argv[2]);
if (!row || !process.argv[2].endsWith('.pds1.ome-auth.test')) throw Error('Not a private test account');
const result=db.prepare('DELETE FROM token WHERE did=? AND clientId=?').run(row.did,process.argv[3]);
db.exec('COMMIT');
console.log(JSON.stringify({revokedGrants:result.changes}));''', account['did'], account['handle'], CLIENT)


@contextmanager
def unavailable(mode):
    command, restore = ('pause', 'unpause') if mode == 'paused' else ('stop', 'start')
    subprocess.run(['docker', command, PDS], check=True, stdout=subprocess.DEVNULL)
    try:
        yield
    finally:
        subprocess.run(['docker', restore, PDS], check=True, stdout=subprocess.DEVNULL)
        if mode != 'paused':
            # Wait for the actual private HTTPS endpoint, not an arbitrary settling delay.
            from sandbox import UPSTREAM
            for _ in range(30):
                probe = subprocess.run(['curl', '--silent', '--fail', '--connect-timeout', '2', '--max-time', '3', '--cacert',
                    str(UPSTREAM / 'state/ca/root.crt'),
                    'https://pds1.ome-auth.test/xrpc/_health'], stdout=subprocess.DEVNULL)
                if probe.returncode == 0:
                    break
                time.sleep(1)
            else:
                raise RuntimeError('Private PDS did not recover')


def tap(selector):
    return {'tapOn': selector}


def visible(selector, timeout=30000):
    return {'extendedWaitUntil': {'visible': selector, 'timeout': timeout}}


def menu(account):
    return {'id': 'menu.account', 'text': 'Signed in as @' + account['handle']}


def row(account):
    return {'id': 'row.account.' + account['did']}


def account_status(account, status='Session verified'):
    return {'runFlow': {'file': str(auth.ROOT / '.maestro/auth/assert-account.yaml'), 'env': {
        'ACCOUNT_DID': account['did'],
        'ACCOUNT_HANDLE': account['handle'] if status == 'Session verified' else '',
        'ACCOUNT_STATUS': status}}}


def open_accounts():
    return [tap({'id': 'menu.account'}), tap('Accounts')]


def restart():
    return ['stopApp', 'launchApp', visible({'id': 'menu.account'})]


class Story:
    def __init__(self, target, directory, password):
        self.target, self.directory, self.password = target, directory, password
        self.started = datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')
        self.phases = []
        self.scope = "setup"

    def events(self):
        if self.target['platform'] == 'ios':
            output = auth.output('xcrun', 'simctl', 'spawn', self.target['device'], 'log', 'show',
                '--style', 'compact', '--start', self.started, '--predicate', 'category == "auth-e2e"')
        else:
            output = auth.output(auth.sys.executable, str(auth.ANDROID_DEVICE), '--device',
                self.target['device'], 'logs')
        return [line for line in output.splitlines() if auth.EVENT.search(line)]

    @contextmanager
    def live_events(self):
        if self.target['platform'] != 'android':
            yield self.events
            return
        # Maestro clears logcat at each flow start. Keep a reader across the
        # PDS unpause/next-flow boundary so completed requests remain evidence.
        process = subprocess.Popen(['adb', '-s', self.target['device'], 'logcat',
            '-v', 'threadtime', '-T', '1', 'app.openmusicevent/auth-e2e:I', '*:S'],
            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
        lines = []
        lock = threading.Lock()

        def collect():
            for line in process.stdout:
                if auth.EVENT.search(line):
                    with lock:
                        lines.append(line.rstrip())

        def snapshot():
            if process.poll() is not None:
                raise RuntimeError('Android auth event stream stopped unexpectedly')
            with lock:
                return list(lines)

        reader = threading.Thread(target=collect, daemon=True)
        reader.start()
        try:
            yield snapshot
        finally:
            process.terminate()
            process.wait(timeout=5)
            reader.join(timeout=5)
            process.stdout.close()

    def phase(self, name, commands, account=None, require=None, before=None, read_events=None):
        read_events = read_events or self.events
        name = self.scope + "/" + name
        directory = self.directory / name
        directory.mkdir(parents=True, mode=0o700)
        flow = directory / 'flow.yaml'
        flow.write_text('appId: ' + self.target['app'] + '\n---\n' + json.dumps(commands, indent=2) + '\n')
        if before is None:
            before = read_events()
        command = ['maestro', '--device', self.target['device'], 'test', '--test-output-dir', str(directory),
                   '-e', 'APP_ID=' + self.target['app'], '-e', 'PASSWORD=' + self.password]
        if account:
            command += ['-e', 'HANDLE=' + account['handle']]
        print(self.target['platform'] + ': ' + name, flush=True)
        with (directory / 'maestro.log').open('w') as log:
            try:
                result = subprocess.run([*command, str(flow)], cwd=auth.ROOT, stdout=log,
                                        stderr=subprocess.STDOUT, timeout=300)
                exit_code = result.returncode
            except subprocess.TimeoutExpired:
                exit_code = 124
        after = read_events()
        (directory / "network-events.json").write_text(
            json.dumps(dict(before=before, after=after), indent=2) + "\n")
        events = auth.new_events(before, after)
        passed = exit_code == 0 and (require is None or require(events))
        self.phases.append(dict(name=name, passed=passed, uiExitCode=exit_code, events=events))
        (self.directory / 'report.json').write_text(json.dumps(self.phases, indent=2) + '\n')
        if not passed:
            raise RuntimeError(self.target['platform'] + ': ' + name + ' failed')
        return events

    def authorize(self, prefilled=False):
        flow = 'submit-login-form.yaml' if prefilled else 'login-from-form.yaml'
        return {'runFlow': str(auth.ROOT / '.maestro/auth' / flow)}

    def setup(self, first, second):
        self.phase('login-first-account', [*restart(), tap({'id': 'menu.account'}),
            {'runFlow': {'when': {'visible': 'Accounts'}, 'commands': [
                tap('Accounts'), tap({'id': 'button.account.logout-all'}),
                {'assertNotVisible': {'id': 'row.account.*'}}, tap('Close'),
                tap({'id': 'menu.account'})]}},
            tap('Sign In'), self.authorize(), visible(menu(first))], first,
            require=lambda e: ('exchange', '200') in e)
        self.add(second, 'add-second-account')

    def add(self, account, name):
        self.phase(name, [*open_accounts(), tap('Add Another Account'), self.authorize(),
            visible(row(account)), tap('Close'), visible(menu(account))], account,
            require=lambda e: ('exchange', '200') in e)

    def multiple_accounts(self, first, second):
        # Both getSession calls remain genuinely in flight while the user switches.
        with self.live_events() as read_events:
            with unavailable('paused'):
                self.phase('switch-while-validating', [*restart(), *open_accounts(),
                    account_status(first, 'Checking session'), account_status(second, 'Checking session'),
                    tap(row(first))], read_events=read_events)
                before = read_events()
            self.phase('verify-both-after-switch', [account_status(first), account_status(second),
                tap('Close'), visible(menu(first))], require=lambda e: ('getSession', '200') in e,
                before=before, read_events=read_events)
        self.phase('restore-selected-account', [*restart(), visible(menu(first)), *open_accounts(),
            account_status(first), account_status(second)])
        self.phase('remove-only-second-account', [{'longPressOn': row(second)}, tap('Log Out'),
            {'assertNotVisible': row(second)}, account_status(first), tap('Close'), visible(menu(first))])
        self.phase('restore-after-removal', [*restart(), visible(menu(first)), *open_accounts(),
            account_status(first), {'assertNotVisible': row(second)}, tap('Close')],
            require=lambda e: ('getSession', '200') in e)

    def cancel_login(self, first, second):
        # Cancel from the platform browser, then prove a subsequent login can start.
        commands = [*open_accounts(), tap('Add Another Account'), tap({'id': 'field.account.handle'}),
            {'inputText': second['handle']}, visible({'id': 'button.account.submit', 'enabled': True}),
            tap({'id': 'button.account.submit', 'enabled': True})]
        if self.target['platform'] == 'ios':
            commands += [visible('Continue', 60000), tap('Continue')]
        commands += [visible('Password')]
        if self.target['platform'] == 'ios':
            commands += [tap('Cancel')]
        else:
            commands += [{'pressKey': 'Back'}]
        commands += [visible({'id': 'field.account.handle'}),
            visible({'id': 'button.account.submit', 'enabled': True}),
            {'assertNotVisible': 'Sign in failed.'}, tap('Close'),
            account_status(first), {'assertNotVisible': row(second)}, tap('Close'), visible(menu(first))]
        self.phase('cancel-browser-login', commands, require=lambda e: ('exchange', '200') not in e)
        self.add(second, 'login-after-cancellation')

    def offline(self, first, second):
        with unavailable('stopped'):
            self.phase('offline-keeps-both-accounts', [*restart(), *open_accounts(),
                account_status(first, 'Session could not be verified'),
                account_status(second, 'Session could not be verified'), tap('Close')],
                require=lambda e: ('getSession', '200') not in e)
        self.phase('recover-network-and-selection', [*restart(), visible(menu(second)), *open_accounts(),
            account_status(first), account_status(second), tap('Close')],
            require=lambda e: ('getSession', '200') in e)

    def revoke(self, first, second):
        self.phase('select-account-before-revocation', [*open_accounts(), tap(row(first)),
            tap('Close'), visible(menu(first))])
        result = revoke_account(first)
        if result['revokedGrants'] < 1:
            raise RuntimeError('No private OAuth grant was revoked')
        (self.directory / 'revocation.json').write_text(json.dumps(result) + '\n')
        self.phase('revoked-account-needs-sign-in', [*restart(), *open_accounts(),
            account_status(first, 'Sign in required'), account_status(second)],
            require=lambda e: ('refresh', '400') in e and ('getSession', '401') in e)
        self.phase('reauthenticate-selected-account', [tap(row(first)),
            visible({'id': 'field.account.handle',
                     'text': '^(?:' + re.escape(first['did']) + '|' + re.escape(first['handle']) + ')$'}),
            self.authorize(prefilled=True), account_status(first), account_status(second),
            tap('Close'), visible(menu(first))], first, require=lambda e: ('exchange', '200') in e)
        self.phase('restore-reauthorized-account', [*restart(), visible(menu(first)), *open_accounts(),
            account_status(first), account_status(second), tap('Close')],
            require=lambda e: ('getSession', '200') in e)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('run', type=Path)
    parser.add_argument('--platform', choices=['ios', 'android', 'both'], default='both')
    parser.add_argument('--scenario', choices=['all', 'multiple', 'cancellation', 'offline', 'revocation'], default='all')
    args = parser.parse_args()
    directory = args.run.resolve()
    if directory.parent != (auth.ROOT / '.build/auth-e2e/runs').resolve():
        parser.error('Expected a run directory in this workspace')
    baseline = json.loads((directory / 'report.json').read_text())
    if not baseline['passed']:
        parser.error('Recovery stories require a passed baseline')
    auth.dedicated_ios(baseline['platforms'][0]['device'])
    auth.dedicated_android(baseline['platforms'][1]['device'])
    subprocess.run(['python3', str(Path(__file__).with_name('preflight.py'))], check=True)
    password = json.loads((directory / 'credentials.json').read_text())['password']
    accounts = {key: account_for_handle(value + '.pds1.ome-auth.test')
                for key, value in baseline['identities'].items()}
    results = []
    output = directory / ('recovery-' + datetime.datetime.now().strftime('%Y%m%dT%H%M%S'))
    output.mkdir(mode=0o700)
    for target in baseline['platforms']:
        if args.platform not in ('both', target['platform']):
            continue
        first = accounts[target['platform']]
        second = accounts['android' if target['platform'] == 'ios' else 'ios']
        story = Story(target, output / target['platform'], password)
        scenarios = ['multiple', 'cancellation', 'offline', 'revocation'] if args.scenario == 'all' else [args.scenario]
        outcomes = []
        needs_setup = True
        for scenario in scenarios:
            story.scope = scenario
            try:
                if needs_setup:
                    story.setup(first, second)
                if scenario == 'multiple':
                    story.multiple_accounts(first, second)
                elif scenario == 'cancellation':
                    if needs_setup:
                        story.phase('remove-second-before-cancellation', [*open_accounts(),
                            {'longPressOn': row(second)}, tap('Log Out'),
                            {'assertNotVisible': row(second)}, tap('Close')])
                    story.cancel_login(first, second)
                elif scenario == 'offline':
                    story.offline(first, second)
                else:
                    story.revoke(first, second)
                outcomes.append(dict(scenario=scenario, passed=True))
                needs_setup = False
            except Exception as error:
                outcomes.append(dict(scenario=scenario, passed=False, error=str(error)))
                # A failure stays recorded. Re-establish accounts through normal UI
                # so independent scenarios still run; never silently retry a story.
                needs_setup = True
        results.append(dict(platform=target['platform'],
                            passed=all(item['passed'] for item in outcomes), scenarios=outcomes))
        (output / 'report.json').write_text(json.dumps(results, indent=2) + '\n')
    print('Recovery report: ' + str(output / 'report.json'))
    if not all(result['passed'] for result in results):
        raise SystemExit(1)


if __name__ == '__main__':
    main()
