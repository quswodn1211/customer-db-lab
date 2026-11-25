"""Read complete PostgreSQL CSV records and forward HNY01 alerts in order."""
import csv
import fcntl
import json
import os
import subprocess
import sys
import time

from server import ROOT, settings


def lines(stream):
    while True:
        line = stream.readline()
        if not line.endswith(b'\n'):
            return
        yield line.decode('utf-8')


def forward():
    config = settings()
    url = 'http://{}:{}{}'.format(config['GATEWAY_IP'], config['GATEWAY_PORT'], config['ALERT_PATH'])
    log = ROOT / 'audit.csv'
    checkpoint = ROOT / 'alert.offset'
    pending = ROOT / 'alert.offset.tmp'
    os.umask(0o077)
    lock = (ROOT / 'sender.lock').open('a')
    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    while not log.exists():
        time.sleep(1)
    with log.open('rb') as stream:
        if checkpoint.exists():
            stream.seek(int(checkpoint.read_text()))
        while True:
            start = stream.tell()
            try:
                fields = next(csv.reader(lines(stream), strict=True))
            except (StopIteration, csv.Error):
                stream.seek(start)
                time.sleep(0.5)
                continue
            if len(fields) > 13 and fields[11:13] == ['LOG', 'HNY01']:
                payload = fields[13]
                event = json.loads(payload)
                while True:
                    reply = subprocess.run(['curl', '--silent', '--show-error', '--noproxy', '*',
                                            '--max-time', '4', '--output', os.devnull, '--write-out',
                                            '%{http_code}', '-H', 'Content-Type: application/json',
                                            '--data-binary', '@-', url], input=payload.encode('utf-8'),
                                           stdout=subprocess.PIPE)
                    if reply.returncode == 0 and reply.stdout.startswith(b'2'):
                        print('Delivered ' + event['event_id'], flush=True)
                        break
                    print('Retrying ' + event['event_id'], file=sys.stderr, flush=True)
                    time.sleep(3)
            pending.write_text(str(stream.tell()))
            os.replace(str(pending), str(checkpoint))


if __name__ == '__main__':
    forward()
