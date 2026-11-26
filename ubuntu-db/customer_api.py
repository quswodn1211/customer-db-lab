"""Customer API and key provisioning for the internal HoneyGen scenario."""
import argparse
import base64
import hashlib
import ipaddress
import json
import os
import re
from http.server import BaseHTTPRequestHandler, HTTPServer

import subprocess
from server import HERE, SOCKET, settings


def query(role, sql):
    cfg = settings()
    database = 'honeygen_{}'.format(int(cfg.get('HONEY_PERCENT', '5')))
    command = ['psql', '-XAtqw', '-v', 'ON_ERROR_STOP=1', '-h', str(SOCKET),
               '-p', cfg['DB_PORT'], '-U', role, '-d', database]
    return subprocess.check_output(command, input=sql.encode('utf-8')).decode('utf-8').splitlines()


def provision():
    # Keys travel via stdin, never via process arguments. Re-running keeps existing keys.
    ids = query('postgres', 'SELECT cno FROM public.customers ORDER BY cno;')
    statements = ["BEGIN;", "SELECT pg_advisory_xact_lock(4825309);",
                  "DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='honey_api') "
                  "THEN CREATE ROLE honey_api LOGIN; END IF; END $$;",
                  (HERE / 'api.sql').read_text()]
    for cno in ids:
        if not re.fullmatch(r'[A-Z]{3}-[0-9]{3}', cno):
            raise ValueError('Invalid CNO')
        key = base64.urlsafe_b64encode(os.urandom(32)).decode('ascii').rstrip('=')
        digest = hashlib.sha256(key.encode('ascii')).hexdigest()
        statements.append("INSERT INTO honey.api_keys VALUES ('{}','{}','{}') "
                          "ON CONFLICT (cno) DO NOTHING;".format(cno, key, digest))
    query('postgres', '\n'.join(statements + ['COMMIT;']))
    print('Provisioned keys for {} customers'.format(len(ids)))

class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        pass

    def do_GET(self):
        if self.path != '/v1/me':
            self.send_error(404)
            return
        auth = re.fullmatch(r'Bearer ([A-Za-z0-9_-]{43})', self.headers.get('Authorization', ''))
        if not auth:
            self.send_error(401)
            return
        digest = hashlib.sha256(auth.group(1).encode('ascii')).hexdigest()
        try:
            peer = ipaddress.IPv4Address(self.client_address[0])
            rows = query('honey_api', "SELECT row_to_json(c) FROM "
                         "public.api_customer('{}','{}'::inet) c;".format(digest, peer))
        except (OSError, subprocess.CalledProcessError):
            self.send_error(503)
            return
        if not rows:
            self.send_error(401)
            return
        body = rows[0].encode('utf-8')
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Cache-Control', 'no-store')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--provision', action='store_true')
    args = parser.parse_args()
    if args.provision:
        provision()
    else:
        cfg = settings()
        HTTPServer((cfg['DB_SERVER_IP'], int(cfg.get('API_PORT', '8090'))), Handler).serve_forever()
