"""Client protocol tests with an isolated HTTP server and a simulated keyring."""
from contextlib import contextmanager
import hashlib
import importlib.util
import io
import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import os
from pathlib import Path
import tempfile
import threading
import time
import unittest
from unittest.mock import patch
import uuid

SOURCE = Path(__file__).resolve().parents[1] / 'home/.local/share/nc-cloud/client.py'
SPEC = importlib.util.spec_from_file_location('nc_cloud_client_test', SOURCE)
CLOUD = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CLOUD)


class Protocol(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_GET(self):
        self.handle_request()

    def do_POST(self):
        self.handle_request()

    def do_PUT(self):
        self.handle_request()

    def do_DELETE(self):
        self.handle_request()

    def handle_request(self):
        state = self.server.state
        state['calls'].append((self.command, self.path))
        base = dict(api_version=1, server_id=state['server_id'], space_id='personal')
        code, data = 200, {}
        size = int(self.headers.get('Content-Length', '0'))
        payload = self.rfile.read(size)
        if self.path.endswith('/capabilities'):
            data = dict(enabled=state['enabled'], state='ready')
        elif self.path.endswith('/devices'):
            data = dict(device_id='device', token='test-device-token')
        elif self.headers.get('Authorization') != 'Bearer test-device-token':
            code, data = 401, {'error': 'authentication_required'}
        elif self.path.endswith('/status'):
            data = dict(state='ready', max_file_bytes=1000, root={'id': 'root', 'revision': 'r1'})
        elif self.path.endswith('/uploads'):
            spec = json.loads(payload)
            key = self.headers['Idempotency-Key']
            ident = state['idempotency'].get(key)
            if not ident:
                ident = uuid.uuid4().hex
                state['idempotency'][key] = ident
                state['uploads'][ident] = dict(spec=spec, chunks={}, state='pending')
            data = dict(upload_id=ident, chunk_bytes=4, state='pending')
        elif '/uploads/' in self.path:
            ident = self.path.split('/uploads/')[1].split('/')[0]
            upload = state['uploads'][ident]
            if '/chunks/' in self.path:
                index = int(self.path.rsplit('/', 1)[1])
                assert hashlib.sha256(payload).hexdigest() == self.headers.get('X-Content-SHA256')
                upload['chunks'][index] = payload
            elif self.path.endswith('/commit'):
                if state['conflict']:
                    code, data = 412, dict(error='version_conflict', current={'kind': 'file', 'revision': 'r2'})
                else:
                    complete = b''.join(upload['chunks'][i] for i in sorted(upload['chunks']))
                    assert hashlib.sha256(complete).hexdigest() == upload['spec']['sha256']
                    upload.update(state='committed', result={'name': upload['spec']['name']})
                    data = dict(state='committed', result=upload['result'])
            elif self.command == 'DELETE':
                if upload['state'] != 'committed':
                    upload['state'] = 'cancelled'
                data = dict(state=upload['state'], result=upload.get('result'))
            else:
                data = dict(state=upload['state'], chunk_bytes=4, result=upload.get('result'),
                            chunks=[{'idx': i, 'sha256': hashlib.sha256(v).hexdigest()} for i, v in upload['chunks'].items()])
        encoded = json.dumps(base | data).encode()
        self.send_response(code)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)


class CloudClient(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.server = ThreadingHTTPServer(('127.0.0.1', 0), Protocol)
        self.server.state = dict(server_id='server-A', enabled=True, uploads={}, idempotency={}, calls=[], conflict=False)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.addCleanup(self.shutdown)
        self.client = CLOUD.Client({'URL': 'http://127.0.0.1:' + str(self.server.server_port), 'SECRET_KEY': 'admin'}, self.root / 'state')
        self.client.keyring = lambda *args: 'test-device-token'
        self.client.notify = lambda *args: None
        self.client.associate()
        self.file = self.root / 'été 2026.txt'
        self.file.write_bytes(b'hello world')

    def shutdown(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(2)

    def test_round_trip_keeps_source_and_hides_secrets(self):
        manifest = self.client.prepare(self.file.as_uri(), 'root', 'r1')
        self.client.worker(manifest['id'])
        rows = self.client.transfers()
        self.assertEqual(rows[0]['state'], 'committed')
        self.assertEqual(self.file.read_bytes(), b'hello world')
        self.assertNotIn('token', self.client.identity_file.read_text())
        self.assertNotIn('source', rows[0])
        self.assertNotIn('test-device-token', json.dumps(rows))
        self.assertEqual(self.client.identity_file.stat().st_mode & 0o077, 0)

    def test_disabled_refuses_before_preparation(self):
        self.server.state['enabled'] = False
        with patch.dict(os.environ, {'XDG_CONFIG_HOME': str(self.root / 'config')}):
            with self.assertRaisesRegex(CLOUD.Failure, 'Cloud'):
                self.client.prepare(str(self.file), 'root', 'r1')
        self.assertFalse(self.client.transfers_dir.exists())
        self.assertEqual(self.server.state['uploads'], {})

    def test_offline_refuses_before_manifest_or_upload(self):
        with patch.object(self.client.opener, 'open', side_effect=TimeoutError):
            with self.assertRaises(CLOUD.Failure) as caught:
                self.client.prepare(str(self.file), 'root', 'r1')
        self.assertEqual(caught.exception.code, 'cloud_unavailable')
        self.assertFalse(self.client.transfers_dir.exists())

    def test_changed_source_is_not_resumed(self):
        manifest = self.client.prepare(str(self.file), 'root', 'r1')
        self.file.write_bytes(b'changed')
        self.client.worker(manifest['id'])
        self.assertEqual(self.client.transfers()[0]['error'], 'source_changed')
        self.assertEqual(self.server.state['uploads'][manifest['upload_id']]['chunks'], {})

    def test_lost_creation_response_preserves_idempotency_intent(self):
        normal = self.client.request
        def lose_response(path, *args, **kwargs):
            result = normal(path, *args, **kwargs)
            if path == '/api/cloud/v1/uploads':
                raise CLOUD.Failure('cloud_unavailable')
            return result
        with patch.object(self.client, 'request', side_effect=lose_response):
            with self.assertRaises(CLOUD.Failure):
                self.client.prepare(str(self.file), 'root', 'r1')
        manifest = CLOUD.private_read(next(self.client.transfers_dir.glob('*.json')))
        self.assertNotIn('upload_id', manifest)
        self.client.worker(manifest['id'])
        self.assertEqual(len(self.server.state['uploads']), 1)
        self.assertEqual(self.client.transfers()[0]['state'], 'committed')

    def test_stopped_worker_requires_explicit_resume(self):
        manifest = self.client.prepare(str(self.file), 'root', 'r1')
        manifest.update(state='uploading', updated=time.time() - 20)
        CLOUD.private_write(self.client.manifest_path(manifest['id']), manifest)
        self.assertEqual(self.client.transfers()[0]['state'], 'interrupted')
        self.assertEqual(self.server.state['uploads'][manifest['upload_id']]['chunks'], {})

    def test_clear_history_is_local_and_keeps_unfinished_transfers(self):
        complete = self.client.prepare(str(self.file), 'root', 'r1')
        self.client.worker(complete['id'])
        pending = self.client.prepare(str(self.file), 'root', 'r1')
        before = list(self.server.state['calls'])
        result = CLOUD.dispatch(self.client, {'op': 'effacer_transferts'})
        self.assertEqual(result['removed'], 1)
        self.assertEqual([row['id'] for row in result['transfers']], [pending['id']])
        self.assertEqual(self.server.state['calls'], before)
        self.assertEqual(self.server.state['uploads'][complete['upload_id']]['state'], 'committed')
        self.assertEqual(self.file.read_bytes(), b'hello world')
        self.client.worker(pending['id'])
        self.assertEqual(self.client.transfers()[0]['state'], 'committed')

    def test_old_terminal_history_expires_but_errors_and_locked_receipts_stay(self):
        template = self.client.prepare(str(self.file), 'root', 'r1')
        self.client.manifest_path(template['id']).unlink()
        kept = set()
        for state in ('committed', 'cancelled', 'expired', 'interrupted', 'conflict'):
            ident = uuid.uuid4().hex
            manifest = template | {'id': ident, 'state': state, 'updated': time.time() - CLOUD.HISTORY_TTL - 60}
            CLOUD.private_write(self.client.manifest_path(ident), manifest)
            if state in ('interrupted', 'conflict'):
                kept.add(ident)
        recent = template | {'id': uuid.uuid4().hex, 'state': 'committed', 'updated': time.time()}
        CLOUD.private_write(self.client.manifest_path(recent['id']), recent)
        locked = template | {'id': uuid.uuid4().hex, 'state': 'committed', 'updated': time.time() - CLOUD.HISTORY_TTL - 60}
        path = self.client.manifest_path(locked['id'])
        CLOUD.private_write(path, locked)
        with path.with_suffix('.lock').open('w') as handle:
            CLOUD.fcntl.flock(handle, CLOUD.fcntl.LOCK_EX)
            rows = self.client.transfers()
            self.assertEqual({row['id'] for row in rows}, kept | {recent['id'], locked['id']})
            self.assertEqual(self.client.clear_transfers(), 1)  # Recent, unlocked completion only.
            self.assertTrue(path.exists())
        self.assertEqual(self.client.clear_transfers(), 1)
        self.assertEqual({row['id'] for row in self.client.transfers()}, kept)

    def test_committed_receipt_survives_lost_local_result(self):
        manifest = self.client.prepare(str(self.file), 'root', 'r1')
        self.client.worker(manifest['id'])
        manifest.update(state='interrupted')
        self.client.save(manifest)
        self.file.unlink()
        before = len(self.server.state['calls'])
        self.client.worker(manifest['id'])
        self.assertEqual(self.client.transfers()[0]['state'], 'committed')
        self.assertFalse(self.client.transfers()[0].get('message'))
        self.assertEqual(len(self.server.state['calls']) - before, 1)

    def test_interruption_and_explicit_resume(self):
        manifest = self.client.prepare(str(self.file), 'root', 'r1')
        normal = self.client.request
        def cut(path, *args, **kwargs):
            if path.endswith('/chunks/1'):
                raise CLOUD.Failure('cloud_unavailable')
            return normal(path, *args, **kwargs)
        with patch.object(self.client, 'request', side_effect=cut):
            self.client.worker(manifest['id'])
        self.assertEqual(self.client.transfers()[0]['state'], 'interrupted')
        self.assertEqual(list(self.server.state['uploads'][manifest['upload_id']]['chunks']), [0])
        self.client.worker(manifest['id'])
        self.assertEqual(self.client.transfers()[0]['state'], 'committed')

    def test_conflict_resolution_uses_displayed_revision(self):
        self.server.state['conflict'] = True
        manifest = self.client.prepare(str(self.file), 'root', 'r1')
        self.client.worker(manifest['id'])
        self.assertEqual(self.client.transfers()[0]['state'], 'conflict')
        with patch.object(self.client, 'launch') as launch:
            self.client.resolve(manifest['id'], 'replace')
        launch.assert_called_once()
        updated = CLOUD.private_read(self.client.manifest_path(manifest['id']))
        self.assertEqual(updated['expected_revision'], 'r2')
        self.assertEqual(updated['policy'], 'replace')

    def test_server_identity_change_is_refused(self):
        self.server.state['server_id'] = 'different-server'
        with self.assertRaises(CLOUD.Failure) as caught:
            self.client.status()
        self.assertEqual(caught.exception.code, 'server_changed')

    def test_symlink_and_remote_url_are_refused(self):
        link = self.root / 'link'
        link.symlink_to(self.file)
        for path in (str(link), 'file://other-host/etc/passwd', str(self.root)):
            with self.assertRaises(CLOUD.Failure):
                self.client.prepare(path, 'root', 'r1')

    def test_bookmark_preserves_other_entries_and_no_password_in_uri(self):
        with patch.dict(os.environ, {'XDG_CONFIG_HOME': str(self.root / 'config')}):
            path = self.root / 'config/gtk-3.0/bookmarks'
            path.parent.mkdir(parents=True)
            path.write_text('file:///tmp Other\n')
            self.client.bookmark(True)
            self.assertIn('file:///tmp Other', path.read_text())
            self.assertIn(' Cloud JARVIS', path.read_text())
            self.assertNotIn('test-device-token', path.read_text())
            with patch.object(subprocess := CLOUD.subprocess, 'run'):
                self.client.bookmark(False)
            self.assertEqual(path.read_text(), 'file:///tmp Other\n')

    def test_mutation_response_loss_reuses_key_and_never_queues_offline(self):
        keys = []
        def request(path, method, payload, headers, **kwargs):
            keys.append(headers['Idempotency-Key'])
            if len(keys) == 1:
                raise CLOUD.Failure('cloud_unavailable')
            return {'deleted': True}
        with patch.object(self.client, 'status'), patch.object(self.client, 'request', side_effect=request):
            with self.assertRaises(CLOUD.Failure):
                self.client.mutation('/api/cloud/v1/entries/file', 'DELETE', {}, 'revision')
            self.assertTrue(self.client.mutation('/api/cloud/v1/entries/file', 'DELETE', {}, 'revision')['deleted'])
        self.assertEqual(keys[0], keys[1])
        self.assertEqual(list((self.client.root / 'operations').glob('*.json')), [])
        with patch.object(self.client, 'status', side_effect=CLOUD.Failure('cloud_unavailable')):
            with self.assertRaises(CLOUD.Failure):
                self.client.mutation('/api/cloud/v1/entries/other', 'DELETE', {}, 'other')
        self.assertEqual(list((self.client.root / 'operations').glob('*.json')), [])

    def test_open_checks_digest_before_launching_app_and_keeps_private_cache(self):
        ident, revision = uuid.uuid4().hex, uuid.uuid4().hex
        entry = {'id': ident, 'revision': revision, 'kind': 'file', 'name': 'été.txt',
                 'size': 5, 'sha256': hashlib.sha256(b'hello').hexdigest()}
        class Download(io.BytesIO):
            headers = {'ETag': '"' + revision + '"'}
        cache = self.root / 'cache'
        with patch.dict(os.environ, {'XDG_CACHE_HOME': str(cache)}), patch.object(self.client, 'status'), \
                patch.object(self.client, 'request', return_value={'entry': entry}), patch.object(CLOUD.subprocess, 'run') as launch:
            launch.return_value.returncode = 0
            with patch.object(self.client.opener, 'open', return_value=Download(b'wrong')):
                with self.assertRaises(CLOUD.Failure) as failed:
                    self.client.open_file(ident, revision)
            self.assertEqual(failed.exception.code, 'integrity_error')
            launch.assert_not_called()
            with patch.object(self.client.opener, 'open', return_value=Download(b'hello')):
                self.assertTrue(self.client.open_file(ident, revision)['opened'])
            command = launch.call_args.args[0]
            self.assertEqual(command[:2], ['gio', 'open'])
            downloaded = Path(command[2])
            self.assertEqual(downloaded.read_bytes(), b'hello')
            self.assertEqual(downloaded.stat().st_mode & 0o077, 0)
            self.assertEqual(downloaded.parent.stat().st_mode & 0o077, 0)


if __name__ == '__main__':
    unittest.main()
