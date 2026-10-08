#!/usr/bin/env python3
"""One test-device UI request plus timestamped Orblino SDK evidence."""
import argparse
import base64
import csv
from datetime import datetime, timedelta, timezone
import json
from pathlib import Path
import queue
import plistlib
import shutil
import socket
import subprocess
import threading
import time
from zoneinfo import ZoneInfo


def classify(line):
    if '[NativeAdTest]' not in line:
        return 'raw'
    if 'tap serverBidding' in line or 'tap viewAd=' in line:
        return 'unexpected_test_action'
    if 'tap format=' in line:
        if all(x in line for x in ('mode=测试设备验证', 'canRun=true',
                                    'attached=true', 'tokenOnly=false')):
            return 'app_request_started'
        return 'unverified_or_blocked_tap'
    if 'status=加载成功，正在展示' in line:
        return 'load_success_show_attempt'
    if 'status=加载失败' in line or 'status=广告失败' in line:
        return 'ad_failure'
    if 'status=已收到奖励回调' in line:
        return 'reward_callback'
    if 'status=广告已关闭' in line:
        return 'closed_callback'
    if 'sdkError=' in line:
        return 'sdk_error_detail'
    return 'app_log'


def socket_command(path, payload):
    with socket.socket(socket.AF_UNIX) as sock:
        sock.settimeout(15)
        sock.connect(str(path))
        sock.sendall(json.dumps(payload).encode() + b'\n')
        with sock.makefile('rb') as stream:
            response = json.loads(stream.readline(16 * 1024 * 1024))
    if not response.get('ok'):
        raise RuntimeError(response.get('error', 'host command failed'))
    return response


def save_screen(response, path):
    if response.get('image'):
        path.write_bytes(base64.b64decode(response['image'], validate=True))


def read_logs(proc, messages):
    for line in proc.stdout:
        messages.put((datetime.now(timezone.utc), time.monotonic(), line.rstrip()))
    messages.put((datetime.now(timezone.utc), time.monotonic(), None))


def export_summary(folder, rows, report_tz):
    fields = ['utc', 'report_time', 'report_hour', 'elapsed_ms', 'kind', 'message']
    with (folder / 'events.csv').open('w', newline='') as out:
        writer = csv.DictWriter(out, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)
    buckets = {}
    for row in rows:
        if row['kind'] == 'app_request_started':
            buckets[row['report_hour']] = buckets.get(row['report_hour'], 0) + 1
    with (folder / 'hours.csv').open('w', newline='') as out:
        writer = csv.writer(out)
        writer.writerow(['report_timezone', 'hour', 'app_request_starts', 'suggested_check_after'])
        for hour, count in sorted(buckets.items()):
            # Wait until the entire hour is at least five hours old.
            check_after = datetime.fromisoformat(hour) + timedelta(hours=6)
            writer.writerow([report_tz, hour, count, check_after.isoformat()])
    kinds = [r['kind'] for r in rows]
    ui = next((r for r in rows if r['kind'] == 'ui_request_sent'), None)
    def latency(accepted):
        found = next((r for r in rows if r['kind'] in accepted and ui is not None
                      and r['elapsed_ms'] >= ui['elapsed_ms']), None)
        return found['elapsed_ms'] - ui['elapsed_ms'] if found else None
    summary = {
        'ui_request_utc': ui['utc'] if ui else None,
        'app_start_after_ui_ms': latency({'app_request_started'}),
        'load_result_after_ui_ms': latency({'ad_failure', 'load_success_show_attempt'}),
        'app_request_starts': kinds.count('app_request_started'),
        'load_success_show_attempts': kinds.count('load_success_show_attempt'),
        'failures': kinds.count('ad_failure'),
        'reward_callbacks': kinds.count('reward_callback'),
        'impressions': None, 'clicks': None,
        'note': 'Local receive times, not server ingestion times. UI requests are not billable impressions. '
                'Backend test-traffic inclusion is unverified; aggregate equality cannot establish attribution.'}
    (folder / 'summary.json').write_text(json.dumps(summary, ensure_ascii=False, indent=2) + '\n')
    return summary


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--socket', type=Path, required=True)
    parser.add_argument('--udid', required=True)
    parser.add_argument('--output', type=Path, required=True, help='New evidence directory; never overwritten')
    parser.add_argument('--report-timezone', default='UTC', help='Match the dashboard, e.g. UTC or Asia/Shanghai')
    parser.add_argument('--seconds', type=int, default=45, choices=range(5, 301), metavar='5..300')
    parser.add_argument('--request', action='store_true',
                        help='OCR-locate the test-panel load button and request once')
    parser.add_argument('--test-device-confirmed', action='store_true',
                        help='Current IDFA registered and effective; test mode and permissions checked in UI')
    parser.add_argument('--format', choices=['rewarded', 'interstitial'], default='rewarded')
    parser.add_argument('--app-id', default='8895377')
    parser.add_argument('--placement-id', required=True, help='Observed test-panel ID, recorded as operator input')
    args = parser.parse_args()
    tz = ZoneInfo(args.report_timezone)
    if args.request and not args.test_device_confirmed:
        parser.error('Automated request requires --test-device-confirmed; otherwise use capture-only mode')
    if not shutil.which('idevicesyslog'):
        parser.error('idevicesyslog is required')
    args.output.mkdir(parents=True, exist_ok=False)
    metadata = dict(vars(args), socket=str(args.socket.resolve()), output=str(args.output.resolve()))
    metadata['timestamp_basis'] = 'Host UTC log receipt; original guest timestamp retained in message'
    (args.output / 'run.json').write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + '\n')
    rows, messages = [], queue.Queue()
    start = time.monotonic()
    proc = None

    def event(kind, message='', utc=None, mono=None):
        utc = utc or datetime.now(timezone.utc)
        local = utc.astimezone(tz)
        row = dict(utc=utc.isoformat(timespec='milliseconds'), report_time=local.isoformat(timespec='milliseconds'),
                   report_hour=local.replace(minute=0, second=0, microsecond=0).isoformat(),
                   elapsed_ms=round(((mono if mono is not None else time.monotonic()) - start) * 1000),
                   kind=kind, message=message)
        rows.append(row)
        with (args.output / 'events.jsonl').open('a') as out:
            out.write(json.dumps(row, ensure_ascii=False) + '\n')
        if kind not in ('raw', 'pre_request_log'):
            print(f"{row['report_time']} {kind}: {message}", flush=True)

    try:
        event('run_started')
        save_screen(socket_command(args.socket, {'t': 'screenshot'}), args.output / 'before.jpg')
        proc = subprocess.Popen(['idevicesyslog', '-u', args.udid, '--no-colors', '-p', 'Orblino Weave'],
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1)
        threading.Thread(target=read_logs, args=(proc, messages), daemon=True).start()
        # Require actual device attachment, not merely a live collector process.
        ready_by = time.monotonic() + 15
        while True:
            if time.monotonic() >= ready_by:
                raise RuntimeError('Log collector did not confirm target device; no request sent')
            try:
                utc, mono, line = messages.get(timeout=0.5)
            except queue.Empty:
                if proc.poll() is not None:
                    raise RuntimeError('Log collector exited before attachment')
                continue
            if line is None:
                raise RuntimeError('Log collector disconnected before request')
            event('collector_log', line, utc, mono)
            if line.strip() == f'[connected:{args.udid}]':
                break
        tap_sent = False
        request_mono = None
        if args.request:
            source = Path(__file__).with_name('ad_test_button.swift')
            binary = args.output / 'button-locator'
            subprocess.run(['xcrun', 'swiftc', str(source), '-o', str(binary)], check=True, timeout=120)
            with (args.socket.resolve().parent / 'config.plist').open('rb') as stream:
                screen = plistlib.load(stream)['screenConfig']
            label = '加载并展示激励广告' if args.format == 'rewarded' else '加载并展示插屏广告'
            def locate(name):
                photo = (args.output / name).resolve()
                socket_command(args.socket, {'t': 'screenshot', 'path': str(photo)})
                result = subprocess.run([str(binary.resolve()), str(photo), label],
                                        capture_output=True, text=True, check=True, timeout=60)
                return json.loads(result.stdout)
            first = locate('button-first.png')
            time.sleep(1)
            point = locate('before-tap.png')
            if abs(point['x'] - first['x']) > 0.005 or abs(point['y'] - first['y']) > 0.005:
                raise RuntimeError('Page is moving; no request sent. Wait for scrolling to stop')
            x, y = point['x'] * screen['width'], point['y'] * screen['height']
            event('ui_request_sent', f'{args.format} placement={args.placement_id} OCR={label} x={x:.1f} y={y:.1f}')
            request_mono = time.monotonic()
            socket_command(args.socket, dict(t='tap', x=x, y=y, screen=False))
            tap_sent = True
            event('ui_command_ack', 'Host accepted touch injection; SDK request not yet confirmed')
        deadline = time.monotonic() + args.seconds
        while time.monotonic() < deadline:
            try:
                utc, mono, line = messages.get(timeout=min(0.5, max(0.01, deadline - time.monotonic())))
            except queue.Empty:
                continue
            if line is None:
                raise RuntimeError('Log collector disconnected')
            kind = classify(line)
            if request_mono is not None and mono < request_mono:
                kind = 'pre_request_log'
            if kind == 'app_request_started' and f'tap format={args.format} ' not in line:
                kind = 'unexpected_format'
            event(kind, line, utc, mono)
            if tap_sent and kind in ('unexpected_format', 'unverified_or_blocked_tap', 'unexpected_test_action'):
                raise RuntimeError('Unexpected test-panel state; stopping without further actions')
        if tap_sent and sum(r['kind'] == 'app_request_started' for r in rows) != 1:
            raise RuntimeError('Expected one confirmed app request; inspect evidence, do not auto-retry')
        save_screen(socket_command(args.socket, {'t': 'screenshot'}), args.output / 'after.jpg')
        event('capture_finished', 'No further UI actions; close any test ad manually')
    except (Exception, KeyboardInterrupt) as error:
        event('capture_error', str(error) or 'Interrupted')
        raise
    finally:
        if proc is not None:
            if proc.poll() is None:
                proc.terminate()
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait()
        summary = export_summary(args.output, rows, args.report_timezone)
        print(json.dumps(summary, ensure_ascii=False, indent=2))
        print(f'Evidence: {args.output.resolve()}')


if __name__ == '__main__':
    main()
