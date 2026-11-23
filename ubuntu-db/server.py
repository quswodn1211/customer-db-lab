"""Run as the postgres OS user. Compatible with Ubuntu 16.04 Python 3.5."""
import csv
import ipaddress
import os
from pathlib import Path
import pwd
import subprocess
import sys

HERE = Path(__file__).resolve().parent
ROOT = Path('/var/lib/postgresql/customer-honey-lab')
DATA = ROOT / 'data'
SOCKET = ROOT / 'socket'


def settings():
    values = {}
    for line in (HERE / '.env').read_text().splitlines():
        if line.strip() and not line.lstrip().startswith('#'):
            key, value = line.split('=', 1)
            values[key.strip()] = value.strip()
    ips = [str(ipaddress.IPv4Address(values[key])) for key in
           ('DB_SERVER_IP', 'CLIENT_1_IP', 'CLIENT_2_IP')]
    port = int(values['DB_PORT'])
    if len(set(ips)) != 3 or not 1 <= port <= 65535:
        raise ValueError('Use three distinct IPv4 addresses and a valid TCP port.')
    return ips, str(port)


def main():
    if pwd.getpwuid(os.getuid()).pw_name != 'postgres':
        sys.exit('Run as the postgres OS user.')
    ips, port = settings()
    os.umask(0o077)
    versions = sorted(Path('/usr/lib/postgresql').glob('*/bin/postgres'),
                      key=lambda p: tuple(map(int, p.parts[-3].split('.'))))
    if not versions:
        sys.exit('Install the Ubuntu postgresql package first.')
    binary = versions[-1].parent
    if (DATA / 'PG_VERSION').exists():
        binary = Path('/usr/lib/postgresql') / (DATA / 'PG_VERSION').read_text().strip() / 'bin'
    ROOT.mkdir(exist_ok=True)
    SOCKET.mkdir(exist_ok=True)
    ready = ROOT / 'seeded'
    if not ready.exists():
        if DATA.exists():
            sys.exit('Incomplete initialization. Inspect the dedicated lab directory before retrying.')
        subprocess.check_call([str(binary / 'initdb'), '-D', str(DATA), '-E', 'UTF8',
                               '--no-locale', '--auth-local=peer', '--auth-host=reject'])
        ctl = [str(binary / 'pg_ctl'), '-D', str(DATA), '-w']
        subprocess.check_call(ctl + ['-l', str(ROOT / 'setup.log'), '-o',
                              "-c listen_addresses='' -k {} -p {}".format(SOCKET, port), 'start'])
        client = [str(binary / 'psql'), '-X', '-v', 'ON_ERROR_STOP=1',
                  '-h', str(SOCKET), '-p', port]
        try:
            subprocess.check_call(client + ['-d', 'postgres', '-c', 'CREATE ROLE business_reader LOGIN'])
            subprocess.check_call(client + ['-d', 'postgres', '-c', r'\password business_reader'])
            for ratio in (1, 5, 10):
                db = 'customers_{}'.format(ratio)
                source = HERE.parent / 'example-results' / ('{}-percent'.format(ratio))
                with (source / 'customers.csv').open(encoding='utf-8-sig') as f:
                    rows = list(csv.DictReader(f))
                tokens = set((source / 'tokens.txt').read_text(encoding='utf-8-sig').splitlines())
                refs = set(row['customer_ref'] for row in rows)
                if len(rows) != 100 or len(refs) != 100 or len(tokens) != ratio or not tokens <= refs:
                    raise ValueError('Invalid dataset: ' + db)
                subprocess.check_call(client + ['-d', 'postgres', '-c', 'CREATE DATABASE ' + db])
                subprocess.check_call(client + ['-d', db, '-c',
                    'REVOKE CREATE ON SCHEMA public FROM PUBLIC; CREATE TABLE customers '
                    '(customer_ref text PRIMARY KEY, full_name text, email text, tier text)'])
                with (source / 'customers.csv').open('rb') as f:
                    subprocess.check_call(client + ['-d', db, '-c',
                        'COPY customers FROM STDIN WITH (FORMAT csv, HEADER true)'], stdin=f)
                subprocess.check_call(client + ['-d', db, '-c', 'GRANT SELECT ON customers TO business_reader'])
            ready.touch()
        finally:
            subprocess.check_call(ctl + ['-m', 'fast', 'stop'])
    if (DATA / 'postmaster.pid').exists():
        sys.exit('Check the existing lab server before starting a second instance.')
    rules = ['local all postgres peer']
    for ip in ips[1:]:
        rules.append('host customers_1,customers_5,customers_10 business_reader {}/32 md5'.format(ip))
    hba = ROOT / 'lab_hba.conf'
    hba.write_text('\n'.join(rules) + '\n')
    args = [str(binary / 'postgres'), '-D', str(DATA), '-k', str(SOCKET),
            '-p', port, '-h', ips[0], '-c', 'hba_file=' + str(hba)]
    print('Listening on {}:{} for {} and {}'.format(ips[0], port, ips[1], ips[2]), flush=True)
    os.execv(args[0], args)


if __name__ == '__main__':
    main()
