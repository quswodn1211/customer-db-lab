"""Ubuntu 16.04 / Python 3.5, run as the postgres OS user."""
import fcntl
import ipaddress
import os
from pathlib import Path
import pwd
import subprocess
import sys

HERE = Path(__file__).resolve().parent
ROOT = Path('/var/lib/postgresql/customer-honey-v2')
DATA = ROOT / 'data'
SOCKET = ROOT / 'socket'


def settings():
    values = {}
    for line in (HERE / '.env').read_text().splitlines():
        if line.strip() and not line.lstrip().startswith('#'):
            key, value = line.split('=', 1)
            values[key.strip()] = value.strip()
    addresses = [str(ipaddress.IPv4Address(values[k])) for k in
                 ('DB_SERVER_IP', 'CLIENT_1_IP', 'CLIENT_2_IP', 'GATEWAY_IP')]
    if len(set(addresses)) != 4:
        raise ValueError('Configure four distinct IPv4 addresses.')
    for key in ('DB_PORT', 'GATEWAY_PORT'):
        if not 1 <= int(values[key]) <= 65535:
            raise ValueError('Invalid port: ' + key)
    if not values['ALERT_PATH'].startswith('/') or values['ALERT_PATH'].startswith('//'):
        raise ValueError('Set ALERT_PATH to an absolute HTTP path.')
    return values


def main():
    if pwd.getpwuid(os.getuid()).pw_name != 'postgres':
        sys.exit('Run as the postgres OS user.')
    env = settings()
    port = env['DB_PORT']
    os.umask(0o077)
    version = (DATA / 'PG_VERSION').read_text().strip() if (DATA / 'PG_VERSION').exists() else '9.5'
    binary = Path('/usr/lib/postgresql') / version / 'bin'
    ROOT.mkdir(exist_ok=True)
    lock = (ROOT / 'bootstrap.lock').open('a')
    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    SOCKET.mkdir(exist_ok=True)
    if (DATA / 'postmaster.pid').exists():
        sys.exit('Check the existing lab server before starting another instance.')
    if not (DATA / 'PG_VERSION').exists():
        subprocess.check_call([str(binary / 'initdb'), '-D', str(DATA), '-E', 'UTF8',
                               '--no-locale', '--auth-local=peer', '--auth-host=reject'])
    if not (ROOT / 'seeded').exists():
        ctl = [str(binary / 'pg_ctl'), '-D', str(DATA), '-w']
        subprocess.check_call(ctl + ['-l', str(ROOT / 'setup.log'), '-o',
                              "-c listen_addresses='' -k {} -p {}".format(SOCKET, port), 'start'])
        client = [str(binary / 'psql'), '-XAt', '-v', 'ON_ERROR_STOP=1',
                  '-h', str(SOCKET), '-p', port]

        def exists(db, query):
            return subprocess.check_output(client + ['-d', db, '-c', query]).strip() == b'1'

        try:
            if not exists('postgres', "SELECT 1 FROM pg_roles WHERE rolname='business_reader'"):
                subprocess.check_call(client + ['-d', 'postgres', '-c', 'CREATE ROLE business_reader LOGIN'])
            subprocess.check_call(client + ['-d', 'postgres', '-c', r'\password business_reader'])
            for ratio in (2, 5, 10):
                db = 'customers_{}'.format(ratio)
                if not exists('postgres', "SELECT 1 FROM pg_database WHERE datname='{}'".format(db)):
                    subprocess.check_call(client + ['-d', 'postgres', '-c', 'CREATE DATABASE ' + db])
                if not exists(db, "SELECT 1 WHERE to_regclass('honey.tokens') IS NOT NULL"):
                    subprocess.check_call(client + ['-d', db, '-v', 'ratio=' + str(ratio),
                                          '-v', 'seed=' + str(42 + ratio), '-f', str(HERE / 'schema.sql')])
            (ROOT / 'seeded').touch()
        finally:
            subprocess.check_call(ctl + ['-m', 'fast', 'stop'])
    rules = ['local all postgres peer']
    for key in ('CLIENT_1_IP', 'CLIENT_2_IP'):
        rules.append('host customers_2,customers_5,customers_10 business_reader {}/32 md5'.format(env[key]))
    hba = ROOT / 'lab_hba.conf'
    hba.write_text('\n'.join(rules) + '\n')
    args = [str(binary / 'postgres'), '-D', str(DATA), '-k', str(SOCKET), '-p', port,
            '-h', env['DB_SERVER_IP'], '-c', 'hba_file=' + str(hba), '-c', 'logging_collector=on',
            '-c', 'log_destination=csvlog', '-c', 'log_directory=' + str(ROOT),
            '-c', 'log_filename=audit.log', '-c', 'log_rotation_age=0', '-c', 'log_rotation_size=0',
            '-c', 'log_min_messages=warning']
    os.execv(args[0], args)


if __name__ == '__main__':
    main()
