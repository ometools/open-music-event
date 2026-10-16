#!/usr/bin/env python3
"""Run a Maestro flow and retain app timings separately from runner timings."""
import argparse
import json
from pathlib import Path
import re
import subprocess
import time

MARKER = re.compile(r"OME_PERF ([0-9.]+) ([\w.-]+) ?(.*)")


def summarize(log, commands):
    marks = []
    for line in log.splitlines():
        match = MARKER.search(line)
        if match:
            marks.append(dict(uptime=float(match[1]), phase=match[2], event=match[3].strip()))
    marks.sort(key=lambda mark: mark['uptime'])
    entries = []
    for mark in marks:
        if mark['phase'] != 'enter.begin':
            continue
        start = mark['uptime']
        event = mark['event']
        next_entry = next((m['uptime'] for m in marks if m['phase'] == 'enter.begin'
                           and m['uptime'] > start), float('inf'))
        segment = [m for m in marks if start <= m['uptime'] < next_entry]
        appeared = next((m for m in segment if m['phase'] == 'schedule.appear'
                         and m['event'] == event), None)
        if appeared:
            segment = [m for m in segment if m['uptime'] <= appeared['uptime']]
        spans = []
        pending = {}
        for m in segment:
            if m['event'] != event:
                continue
            phase = m['phase']
            if phase.endswith('.begin'):
                pending[phase[:-6]] = m['uptime']
            elif phase.endswith('.end') and phase[:-4] in pending:
                spans.append(dict(phase=phase[:-4], milliseconds=round(
                    (m['uptime'] - pending.pop(phase[:-4])) * 1000, 3)))
        entries.append(dict(event=event, complete=appeared is not None,
                            cache='hit' if any(m['phase'] == 'cache.hit' and m['event'] == event
                                              for m in segment) else ('miss' if any(m['phase'] == 'cache.miss' and m['event'] == event
                                              for m in segment) else 'unknown'),
                            action_to_schedule_appear_ms=round((appeared['uptime']-start)*1000, 3)
                            if appeared else None, spans=spans,
                            http_requests=[m['event'] for m in segment if m['phase'] == 'http.begin'],
                            bundle_requests=sum(m['phase'] == 'bundle-request.begin' for m in segment)))
    runner = []
    automation_entries = []
    for path, rows in commands:
        entry_start = None
        for row in rows:
            metadata = row.get('metadata', {})
            command = metadata.get('evaluatedCommand', row.get('command', {}))
            selector = command.get('tapOnElement', {}).get('selector', {})
            if selector.get('idRegex', '').startswith('button.enter-event.') or selector.get('textRegex') == 'Enter Event':
                entry_start = metadata.get('timestamp')
            visible = command.get('assertConditionCommand', {}).get('condition', {}).get('visible', {})
            if visible.get('idRegex', '').startswith('view.schedule.') and entry_start is not None:
                complete = metadata.get('status') == 'COMPLETED'
                end = metadata.get('timestamp', 0) + metadata.get('duration', 0)
                automation_entries.append(dict(source=path, complete=complete,
                                               tap_to_schedule_assert_ms=end-entry_start if complete else None))
                entry_start = None
            runner.append(dict(source=path, command=next(iter(command), 'unknown'),
                               status=metadata.get('status'), timestamp_ms=metadata.get('timestamp'),
                               duration_ms=metadata.get('duration')))
    return dict(schema_version=1, thresholds=None,
                notes=['App durations use monotonic uptime. Spans overlap; do not sum them.',
                       'Schedule onAppear is a lifecycle milestone, not proof of a displayed frame.',
                       'Runner durations include UI synchronization and automation overhead.',
                       'HTTP routes cover the automation transport; image loaders may use other transports.',
                       'Missing app markers mean unavailable measurements, never zero latency.'],
                entries=entries, markers=marks, automation_commands=runner,
                automation_entries=automation_entries)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--device', required=True)
    parser.add_argument('--app-id', default='app.openmusicevent')
    parser.add_argument('--platform', choices=['ios', 'android'], default='ios')
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('flow')
    parser.add_argument('maestro_args', nargs=argparse.REMAINDER)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=False)
    log_path = args.output / 'app-performance.log'
    capture = None
    with log_path.open('w') as log:
        if args.platform == 'ios':
            capture = subprocess.Popen(['xcrun', 'simctl', 'spawn', args.device, 'log', 'stream',
                                        '--style', 'compact', '--level', 'info', '--predicate',
                                        'subsystem == "app.openmusicevent" AND category == "performance"'],
                                       stdout=log, stderr=subprocess.STDOUT)
            time.sleep(1)
            if capture.poll() is not None:
                raise SystemExit('Simulator log capture failed; see app-performance.log')
        try:
            with (args.output / 'maestro.log').open('w') as maestro_log:
                result = subprocess.run(['maestro', '--device', args.device, 'test',
                                         '--test-output-dir', str(args.output),
                                         '-e', 'APP_ID=' + args.app_id,
                                         *args.maestro_args, args.flow],
                                        stdout=maestro_log, stderr=subprocess.STDOUT)
        finally:
            if capture:
                capture.terminate()
                try:
                    capture.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    capture.kill()
                    capture.wait()
    commands = []
    for path in args.output.rglob('*.json'):
        if path.name.startswith('commands'):
            commands.append((str(path.relative_to(args.output)), json.loads(path.read_text())))
    report = summarize(log_path.read_text(), commands)
    report.update(device=args.device, platform=args.platform, flow=args.flow,
                  app_id=args.app_id, maestro_exit_code=result.returncode,
                  app_metrics_available=bool(report['markers']))
    (args.output / 'performance.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(dict(report=str(args.output / 'performance.json'),
                          entries=report['entries'], maestro_exit_code=result.returncode), indent=2))
    raise SystemExit(result.returncode)


if __name__ == '__main__':
    main()
