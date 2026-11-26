"""Lab gateway receiver. Run as an ordinary user in a writable directory."""
import json
import sqlite3
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from server import settings


def main():
    config = settings()
    store = sqlite3.connect(str(Path.home() / 'honey-alerts.sqlite'))
    store.execute('CREATE TABLE IF NOT EXISTS alerts (event_id TEXT PRIMARY KEY, payload TEXT NOT NULL)')

    class Receiver(BaseHTTPRequestHandler):
        def do_POST(self):
            if self.path != config['ALERT_PATH']:
                self.send_error(404)
                return
            if self.client_address[0] != config['DB_SERVER_IP']:
                self.send_error(403)
                return
            try:
                size = int(self.headers.get('Content-Length', '0'))
                if not 0 < size <= 8192:
                    raise ValueError()
                body = self.rfile.read(size).decode('utf-8')
                event = json.loads(body)
                if event['event'] not in ('HONEYTOKEN_READ', 'HONEYTOKEN_API_USED') or not isinstance(event['event_id'], str):
                    raise ValueError()
                with store:
                    store.execute('INSERT OR IGNORE INTO alerts VALUES (?,?)', (event['event_id'], body))
            except (KeyError, ValueError, TypeError):
                self.send_error(400)
                return
            self.send_response(204)
            self.end_headers()

    HTTPServer((config['GATEWAY_IP'], int(config['GATEWAY_PORT'])), Receiver).serve_forever()


if __name__ == '__main__':
    main()
