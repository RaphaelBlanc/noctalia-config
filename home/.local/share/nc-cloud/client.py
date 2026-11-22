"""Cloud JARVIS client: no offline queue, no mirror directory, no AI requests."""
import argparse
import base64
import fcntl
import hashlib
import importlib.machinery
import importlib.util
import json
import os
from pathlib import Path
import re
import socket
import shutil
import stat
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid

HISTORY_TTL = 24 * 60 * 60
TERMINAL_TRANSFERS = ('committed', 'cancelled', 'expired')

MESSAGES = {
    'cloud_unavailable': ('Cloud hors ligne. Aucun nouvel envoi. Réessaie après reconnexion.', 'Cloud offline. No new upload. Try again after reconnecting.'),
    'cloud_disabled': ('Cloud disponible uniquement sur un serveur distant avec cette option activée.', 'Cloud is only available on a remote server with this option enabled.'),
    'not_associated': ('Associe ce PC au cloud dans les réglages.', 'Associate this PC with the cloud in settings.'),
    'device_revoked': ('Accès cloud révoqué : associe à nouveau ce PC.', 'Cloud access revoked: associate this PC again.'),
    'version_conflict': ('Un fichier de ce nom existe ou a changé sur le serveur.', 'A file with this name exists or has changed on the server.'),
    'source_changed': ('Le fichier source a changé. Dépose-le à nouveau.', 'The source file changed. Drop it again.'),
    'keyring_unavailable': ('Le trousseau de session ne répond pas (secret-tool).', 'The session keyring is unavailable (secret-tool).'),
    'server_changed': ('Le serveur cloud a changé. Associe à nouveau ce PC.', 'The cloud server changed. Associate this PC again.'),
    'quota_exceeded': ('Quota cloud dépassé.', 'Cloud quota exceeded.'),
    'storage_full': ('Disque du serveur plein.', 'Server disk is full.'),
    'upload_expired': ('Ce transfert a expiré. Dépose le fichier à nouveau.', 'This upload expired. Drop the file again.'),
    'invalid_source': ('Sélectionne un fichier local ordinaire ; les dossiers et liens ne sont pas envoyés.', 'Select a regular local file; folders and links are not uploaded.'),
    'authentication_required': ('Identifiants cloud refusés. Associe à nouveau ce PC.', 'Cloud credentials rejected. Associate this PC again.'),
    'destination_changed': ('Le dossier distant a changé. Choisis à nouveau la destination.', 'The remote folder changed. Select the destination again.'),
    'mount_failed': ('Impossible d’ouvrir le drive dans Fichiers. Vérifie les composants Gio et GVfs.', 'Unable to open the drive in Files. Check Gio and GVfs components.'),
    'not_configured': ('Configure d’abord la connexion à JARVIS.', 'Configure the JARVIS connection first.'),
    'incompatible': ('Ce serveur ne propose pas cette version du cloud.', 'This server does not provide this cloud version.'),
    'name_conflict': ('Ce nom existe déjà dans ce dossier.', 'This name already exists in this folder.'),
    'tree_changed': ('Le contenu du dossier a changé sur un autre PC. Actualise avant de confirmer à nouveau.', 'The folder contents changed on another PC. Refresh before confirming again.'),
    'invalid_destination': ('Un dossier ne peut pas être déplacé dans lui-même ou un de ses sous-dossiers.', 'A folder cannot be moved into itself or one of its subfolders.'),
    'directory_not_empty': ('Ce dossier contient des éléments. Confirme la suppression de son contenu.', 'This folder has contents. Confirm deleting its contents.'),
    'open_failed': ('Impossible d’ouvrir ce fichier avec son application habituelle.', 'Could not open this file with its default application.'),
    'integrity_error': ('Le téléchargement ne correspond pas au fichier distant. Réessaie.', 'The download does not match the remote file. Try again.'),
}


def language():
    return not (os.environ.get('LANG', '').lower().startswith('fr'))


class Failure(Exception):
    def __init__(self, code, status=0, current=None):
        self.code, self.status, self.current = code, status, current
        super().__init__(MESSAGES.get(code, ('Erreur cloud : ' + code, 'Cloud error: ' + code))[language()])


def private_write(path, data):
    path.parent.mkdir(parents=True, mode=0o700, exist_ok=True)
    if path.is_symlink():
        raise Failure('invalid_source')
    with tempfile.NamedTemporaryFile(mode='w', dir=path.parent, delete=False) as f:
        temporary = Path(f.name)
        json.dump(data, f, ensure_ascii=False)
        f.flush()
        os.fsync(f.fileno())
    os.chmod(temporary, 0o600)
    os.replace(temporary, path)


def private_read(path):
    if path.is_symlink() or path.stat().st_mode & 0o077 or path.stat().st_size > 1024**2:
        raise Failure('invalid_private_file')
    return json.loads(path.read_text())


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def assistant_configuration():
    path = Path(__file__).resolve().parents[2] / 'bin/nc-assistant'
    loader = importlib.machinery.SourceFileLoader('cloud_assistant_configuration', str(path))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    try:
        config = module.configuration()
    except module.Erreur:
        raise Failure('not_configured') from None
    if not module.transport_sur(config['URL']):
        raise Failure('unsafe_transport')
    return config


class Client:
    def __init__(self, config=None, state=None):
        self.config = config or assistant_configuration()
        self.url = self.config['URL'].rstrip('/')
        self.namespace = hashlib.sha256(self.url.encode()).hexdigest()
        root = Path(os.environ.get('XDG_STATE_HOME') or Path.home() / '.local/state')
        self.root = (Path(state) if state else root / 'nc-cloud') / self.namespace
        self.identity_file = self.root / 'connection.json'
        self.transfers_dir = self.root / 'transfers'
        self.opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect())
        self._token = None

    def identity(self):
        try:
            return private_read(self.identity_file)
        except FileNotFoundError:
            raise Failure('not_associated') from None

    def keyring(self, operation, identity, token=None):
        command = ['secret-tool', operation]
        if operation == 'store':
            command += ['--label=Cloud JARVIS']
        command += ['service', 'nc-cloud', 'server', self.namespace, 'device', identity['device_id']]
        try:
            result = subprocess.run(command, input=token, text=True, capture_output=True, timeout=15)
        except (OSError, subprocess.TimeoutExpired):
            raise Failure('keyring_unavailable') from None
        if result.returncode:
            raise Failure('keyring_unavailable')
        return result.stdout.strip()

    def token(self):
        if self._token is None:
            self._token = self.keyring('lookup', self.identity())
            if not self._token:
                raise Failure('not_associated')
        return self._token

    def request(self, path, method='GET', payload=None, binary=None, headers=None, admin=False, timeout=8):
        auth = {'X-Secret-Key': self.config['SECRET_KEY']} if admin else {'Authorization': 'Bearer ' + self.token()}
        auth.update(headers or {})
        data = binary
        if payload is not None:
            data = json.dumps(payload).encode()
            auth['Content-Type'] = 'application/json'
        elif data is not None:
            auth['Content-Type'] = 'application/octet-stream'
        request = urllib.request.Request(self.url + path, data=data, headers=auth, method=method)
        try:
            with self.opener.open(request, timeout=timeout) as response:
                raw = response.read(2 * 1024**2 + 1)
                if len(raw) > 2 * 1024**2:
                    raise Failure('invalid_response')
                result = json.loads(raw)
        except urllib.error.HTTPError as exc:
            try:
                error = json.loads(exc.read(8192))
            except (ValueError, OSError):
                error = {}
            finally:
                exc.close()
            raise Failure(error.get('error', 'authentication_required' if exc.code in (401, 403) else 'cloud_unavailable'),
                          exc.code, error.get('current')) from None
        except (urllib.error.URLError, TimeoutError, OSError):
            raise Failure('cloud_unavailable') from None
        except ValueError:
            raise Failure('incompatible') from None
        if result.get('api_version') != 1:
            raise Failure('incompatible')
        if not admin:
            identity = self.identity()
            if result.get('server_id') != identity['server_id'] or result.get('space_id') != identity['space_id']:
                raise Failure('server_changed')
        return result

    def capability(self):
        active = self.root.parent / 'active.json'
        if active.exists() and private_read(active).get('namespace') != self.namespace:
            self.bookmark(False)
        try:
            result = self.request('/api/cloud/v1/capabilities', admin=True, timeout=3)
        except Failure as exc:
            if exc.status == 404:
                raise Failure('incompatible') from None
            raise
        if not result.get('enabled'):
            # Keep identity for future reactivation, but remove the old Files bookmark.
            self.bookmark(False)
            raise Failure('cloud_disabled')
        if result.get('state') != 'ready':
            raise Failure('cloud_unavailable')
        return result

    def status(self):
        self.capability()
        result = self.request('/api/cloud/v1/status', timeout=3)
        return dict(result, associated=True, enabled=True, configured=True)

    def associate(self):
        capability = self.capability()
        associated = self.request('/api/cloud/v1/devices', 'POST', {'name': socket.gethostname()[:80] or 'PC'}, admin=True)
        if associated['server_id'] != capability['server_id']:
            raise Failure('server_changed')
        identity = {k: associated[k] for k in ('server_id', 'space_id', 'device_id')}
        try:
            self.keyring('store', identity, associated['token'])
        except Failure:
            self.request('/api/cloud/v1/devices/' + identity['device_id'], 'DELETE', admin=True)
            raise
        previous = self.identity() if self.identity_file.exists() else None
        private_write(self.identity_file, identity)
        if previous and previous['device_id'] != identity['device_id']:
            self.request('/api/cloud/v1/devices/' + previous['device_id'], 'DELETE', admin=True)
            self.keyring('clear', previous)
        self._token = associated['token']
        return self.status()

    def listing(self, parent='root', cursor=''):
        return self.request('/api/cloud/v1/entries?' + urllib.parse.urlencode({'parent_id': parent, 'cursor': cursor}))

    def mutation(self, path, method, payload, revision=None, commit=False):
        # No automatic replay: authenticate before creating a journal, and only
        # reuse its idempotency key when the user explicitly repeats this action.
        self.status()
        headers = {'If-Match': '"' + revision + '"'} if revision else {}
        spec = {'path': path, 'method': method, 'payload': payload, 'headers': headers}
        fingerprint = hashlib.sha256(json.dumps(spec, sort_keys=True).encode()).hexdigest()
        journal = self.root / 'operations' / (fingerprint + '.json')
        try:
            operation = private_read(journal)
        except FileNotFoundError:
            operation = {'key': uuid.uuid4().hex, 'request': spec}
            private_write(journal, operation)
        headers['Idempotency-Key'] = operation['key']
        result = self.request(path, method, payload, headers=headers, timeout=60)
        if commit:
            result = self.request('/api/cloud/v1/uploads/' + result['upload_id'] + '/commit', 'POST', timeout=60)
        journal.unlink(missing_ok=True)
        return result

    def open_file(self, ident, revision):
        if not re.fullmatch('[0-9a-f]{32}', ident) or not re.fullmatch('[0-9a-f]{32}', revision):
            raise Failure('invalid_source')
        self.status()
        entry = self.request('/api/cloud/v1/entries/' + ident)['entry']
        if entry['kind'] != 'file' or entry['revision'] != revision:
            raise Failure('version_conflict')
        name = entry['name']
        if name in ('.', '..') or '/' in name or '\\' in name:
            raise Failure('invalid_source')
        cache = Path(os.environ.get('XDG_CACHE_HOME') or Path.home() / '.cache') / 'nc-cloud' / self.namespace
        destination = cache / ident / revision / name
        for directory in (cache.parent, cache, cache / ident, destination.parent):
            if directory.is_symlink():
                raise Failure('invalid_private_file')
            directory.mkdir(mode=0o700, parents=True, exist_ok=True)
            if directory.stat().st_uid != os.getuid():
                raise Failure('invalid_private_file')
            directory.chmod(0o700)
        if destination.is_symlink():
            raise Failure('invalid_private_file')
        digest = hashlib.sha256()
        size = 0
        temporary = None
        try:
            if shutil.disk_usage(destination.parent).free < entry['size'] + 1024**2:
                raise Failure('storage_full')
            request = urllib.request.Request(self.url + '/api/cloud/v1/files/' + ident + '/content',
                headers={'Authorization': 'Bearer ' + self.token(), 'If-Match': '"' + revision + '"'})
            with self.opener.open(request, timeout=60) as response:
                if response.headers.get('ETag') != '"' + revision + '"':
                    raise Failure('version_conflict')
                with tempfile.NamedTemporaryFile(dir=destination.parent, delete=False) as output:
                    temporary = Path(output.name)
                    while chunk := response.read(1024**2):
                        size += len(chunk)
                        if size > entry['size']:
                            raise Failure('integrity_error')
                        output.write(chunk); digest.update(chunk)
                    output.flush(); os.fsync(output.fileno())
            if size != entry['size'] or digest.hexdigest() != entry['sha256']:
                raise Failure('integrity_error')
            os.chmod(temporary, 0o600)
            os.replace(temporary, destination)
            temporary = None
        except (urllib.error.URLError, TimeoutError, OSError):
            raise Failure('cloud_unavailable') from None
        finally:
            if temporary:
                temporary.unlink(missing_ok=True)
        try:
            result = subprocess.run(['gio', 'open', str(destination)], capture_output=True, timeout=15)
        except (OSError, subprocess.SubprocessError):
            raise Failure('open_failed') from None
        if result.returncode:
            raise Failure('open_failed')
        return {'ok': True, 'opened': True}

    @staticmethod
    def source(path):
        if path.startswith('file:'):
            uri = urllib.parse.urlsplit(path)
            if uri.scheme != 'file' or uri.netloc not in ('', 'localhost') or uri.query or uri.fragment:
                raise Failure('invalid_source')
            path = urllib.parse.unquote(uri.path)
        file = Path(path).absolute()
        try:
            initial = file.lstat()
            if not stat.S_ISREG(initial.st_mode):
                raise Failure('invalid_source')
            fd = os.open(file, os.O_RDONLY | os.O_NOFOLLOW | os.O_CLOEXEC)
            source = os.fdopen(fd, 'rb')
            actual = os.fstat(fd)
            if (initial.st_dev, initial.st_ino) != (actual.st_dev, actual.st_ino):
                source.close()
                raise Failure('source_changed')
            return file, source
        except OSError:
            raise Failure('invalid_source') from None

    @staticmethod
    def fingerprint(source):
        info = os.fstat(source.fileno())
        return [info.st_dev, info.st_ino, info.st_size, info.st_mtime_ns, info.st_ctime_ns]

    def manifest_path(self, ident):
        if not re.fullmatch('[0-9a-f]{32}', ident):
            raise Failure('invalid_transfer')
        return self.transfers_dir / (ident + '.json')

    def save(self, manifest):
        manifest['updated'] = time.time()
        private_write(self.manifest_path(manifest['id']), manifest)

    def check_manifest(self, manifest):
        identity = self.identity()
        if any(manifest[k] != identity[k] for k in ('server_id', 'space_id', 'device_id')):
            raise Failure('server_changed')

    def prepare(self, path, parent, revision):
        # A live authenticated round trip must precede preparation. Never queue an offline drop.
        status = self.status()
        file, source = self.source(path)
        with source:
            fingerprint = self.fingerprint(source)
            if fingerprint[2] > status['max_file_bytes']:
                raise Failure('file_too_large')
            digest = hashlib.file_digest(source, 'sha256').hexdigest()
            if self.fingerprint(source) != fingerprint:
                raise Failure('source_changed')
        manifest = dict(self.identity(), id=uuid.uuid4().hex, source=str(file), fingerprint=fingerprint,
                        name=file.name, parent_id=parent, parent_revision=revision, size=fingerprint[2],
                        sha256=digest, policy='create', expected_revision=None, idem=uuid.uuid4().hex,
                        state='preparing', sent=0, created=time.time())
        spec = {k: manifest[k] for k in ('name', 'parent_id', 'parent_revision', 'size', 'sha256', 'policy', 'expected_revision')}
        self.save(manifest)  # Persist intent before an HTTP response can be lost.
        try:
            upload = self.request('/api/cloud/v1/uploads', 'POST', spec, headers={'Idempotency-Key': manifest['idem']})
        except Failure as exc:
            manifest.update(state='interrupted', error=exc.code, message=str(exc))
            self.save(manifest)
            raise
        manifest.update(upload_id=upload['upload_id'], state='ready')
        self.save(manifest)
        return manifest

    def launch(self, ident):
        manifest = private_read(self.manifest_path(ident))
        self.check_manifest(manifest)
        launcher = Path(__file__).resolve().parents[2] / 'bin/nc-cloud'
        # No credentials in argv or log files. A worker ends on the first connection failure.
        subprocess.Popen([sys.executable, str(launcher), 'worker', ident], stdin=subprocess.DEVNULL,
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)

    def worker(self, ident):
        path = self.manifest_path(ident)
        lock = path.with_suffix('.lock')
        lock.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        fd = os.open(lock, os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
        with os.fdopen(fd, 'w') as handle:
            fcntl.flock(handle, fcntl.LOCK_EX)
            manifest = private_read(path)
            try:
                self.check_manifest(manifest)
                if not manifest.get('upload_id'):
                    self.capability()
                    spec = {k: manifest[k] for k in ('name', 'parent_id', 'parent_revision', 'size', 'sha256', 'policy', 'expected_revision')}
                    result = self.request('/api/cloud/v1/uploads', 'POST', spec, headers={'Idempotency-Key': manifest['idem']})
                    manifest['upload_id'] = result['upload_id']
                    self.save(manifest)
                state = self.request('/api/cloud/v1/uploads/' + manifest['upload_id'])
                if state['state'] == 'committed':
                    manifest.update(state='committed', sent=manifest['size'], result=state['result'], error=None, message='', current=None)
                    self.save(manifest)
                    return
                if state['state'] != 'pending':
                    raise Failure('upload_expired' if state['state'] == 'expired' else 'upload_not_pending')
                self.capability()
                _, source = self.source(manifest['source'])
                with source:
                    if self.fingerprint(source) != manifest['fingerprint'] or hashlib.file_digest(source, 'sha256').hexdigest() != manifest['sha256']:
                        raise Failure('source_changed')
                    source.seek(0)
                    received = {r['idx']: r['sha256'] for r in state['chunks']}
                    manifest.update(state='uploading', error=None, message='', current=None, sent=0)
                    self.save(manifest)
                    index = 0
                    while data := source.read(state['chunk_bytes']):
                        checksum = hashlib.sha256(data).hexdigest()
                        if self.manifest_path(ident).with_suffix('.cancel').exists():
                            raise Failure('cancel_requested')
                        if received.get(index) != checksum:
                            self.request('/api/cloud/v1/uploads/' + manifest['upload_id'] + '/chunks/' + str(index),
                                         'PUT', binary=data, headers={'X-Content-SHA256': checksum}, timeout=60)
                        manifest['sent'] += len(data)
                        self.save(manifest)
                        index += 1
                    if self.fingerprint(source) != manifest['fingerprint']:
                        raise Failure('source_changed')
                manifest['state'] = 'verifying'
                self.save(manifest)
                if self.manifest_path(ident).with_suffix('.cancel').exists():
                    raise Failure('cancel_requested')
                result = self.request('/api/cloud/v1/uploads/' + manifest['upload_id'] + '/commit', 'POST', timeout=60)
                manifest.update(state='committed', result=result['result'], error=None, message='', current=None)
                self.save(manifest)
                self.notify(manifest['name'] + (' envoyé.' if not language() else ' uploaded.'))
            except Failure as exc:
                manifest.update(state='conflict' if exc.code == 'version_conflict' else 'interrupted',
                                error=exc.code, message=str(exc), current=exc.current)
                if exc.code in ('cancel_requested', 'upload_not_pending'):
                    manifest['state'] = 'cancelled'
                self.save(manifest)
                self.notify(str(exc))

    @staticmethod
    def notify(message):
        try:
            subprocess.run(['notify-send', '-a', 'Cloud JARVIS', 'Cloud JARVIS', message], timeout=3,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except (OSError, subprocess.TimeoutExpired):
            pass

    def clear_transfers(self, before=None):
        """Remove terminal local receipts only; keep locks stable for workers."""
        removed = 0
        if not self.transfers_dir.exists():
            return removed
        for path in self.transfers_dir.glob('*.json'):
            # Never remove a receipt still held by a worker, even if its last
            # state already says committed (e.g. while notifying the desktop).
            fd = os.open(path.with_suffix('.lock'), os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
            with os.fdopen(fd, 'w') as handle:
                try:
                    fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
                except BlockingIOError:
                    continue
                try:
                    manifest = private_read(path)
                except FileNotFoundError:
                    continue
                if manifest['state'] not in TERMINAL_TRANSFERS:
                    continue
                if before is not None and manifest['updated'] >= before:
                    continue
                path.unlink()
                path.with_suffix('.cancel').unlink(missing_ok=True)
                removed += 1
        return removed

    def transfers(self):
        self.clear_transfers(before=time.time() - HISTORY_TTL)
        rows = []
        if self.transfers_dir.exists():
            for path in self.transfers_dir.glob('*.json'):
                try:
                    manifest = private_read(path)
                except FileNotFoundError:
                    continue  # Another window may have cleared this receipt.
                if manifest['state'] in ('ready', 'preparing', 'uploading', 'verifying') and time.time() - manifest['updated'] > 5:
                    fd = os.open(path.with_suffix('.lock'), os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
                    with os.fdopen(fd, 'w') as handle:
                        try:
                            fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
                        except BlockingIOError:
                            pass
                        else:
                            try:
                                manifest = private_read(path)
                            except FileNotFoundError:
                                continue
                            if manifest['state'] in ('ready', 'preparing', 'uploading', 'verifying'):
                                manifest.update(state='interrupted', error='worker_stopped',
                                                message=('Transfert interrompu. Reprends-le pour vérifier son état.' if not language() else 'Transfer interrupted. Resume to verify its state.'))
                                self.save(manifest)
                # Source paths and device credentials are not passed to QML.
                rows.append({k: manifest.get(k) for k in ('id', 'name', 'state', 'size', 'sent', 'updated', 'message', 'error', 'current')})
        return sorted(rows, key=lambda row: row['updated'], reverse=True)[:100]

    def cancel(self, ident):
        manifest = private_read(self.manifest_path(ident))
        self.check_manifest(manifest)
        private_write(self.manifest_path(ident).with_suffix('.cancel'), {})
        result = self.request('/api/cloud/v1/uploads/' + manifest['upload_id'], 'DELETE')
        # Let an active worker reconcile its own manifest; terminal server state is authoritative.
        manifest.update(state=result['state'], result=result.get('result'), error=None, message='', current=None)
        self.save(manifest)
        return result

    def resolve(self, ident, policy):
        manifest = private_read(self.manifest_path(ident))
        self.check_manifest(manifest)
        if manifest['state'] != 'conflict' or policy not in ('keep_both', 'replace'):
            raise Failure('invalid_resolution')
        current = manifest.get('current') or {}
        if policy == 'replace' and current.get('kind') != 'file':
            raise Failure('invalid_resolution')
        self.cancel(ident)
        manifest.update(policy=policy, expected_revision=current.get('revision') if policy == 'replace' else None,
                        idem=uuid.uuid4().hex, state='ready', error=None, message='', current=None)
        spec = {k: manifest[k] for k in ('name', 'parent_id', 'parent_revision', 'size', 'sha256', 'policy', 'expected_revision')}
        result = self.request('/api/cloud/v1/uploads', 'POST', spec, headers={'Idempotency-Key': manifest['idem']})
        manifest['upload_id'] = result['upload_id']
        self.manifest_path(ident).with_suffix('.cancel').unlink(missing_ok=True)
        self.save(manifest)
        self.launch(ident)
        return {'ok': True}

    def dav_uri(self):
        parsed = urllib.parse.urlsplit(self.url)
        identity = self.identity()
        return urllib.parse.urlunsplit(('davs' if parsed.scheme == 'https' else 'dav',
                                         identity['device_id'] + '@' + parsed.netloc, parsed.path + '/cloud/dav/', '', ''))

    def bookmark(self, add):
        config = Path(os.environ.get('XDG_CONFIG_HOME') or Path.home() / '.config')
        path = config / 'gtk-3.0/bookmarks'
        try:
            lines = path.read_text().splitlines()
        except FileNotFoundError:
            lines = []
        # Only own our label, preserve every other bookmark.
        lines = [line for line in lines if not line.endswith(' Cloud JARVIS')]
        if add:
            lines.append(self.dav_uri() + ' Cloud JARVIS')
        path.parent.mkdir(parents=True, exist_ok=True)
        if path.is_symlink():
            raise Failure('invalid_private_file')
        with tempfile.NamedTemporaryFile(mode='w', dir=path.parent, delete=False) as f:
            f.write('\n'.join(lines) + ('\n' if lines else ''))
            temporary = f.name
        os.replace(temporary, path)
        active = self.root.parent / 'active.json'
        if add:
            private_write(active, {'namespace': self.namespace, 'uri': self.dav_uri()})
        elif active.exists():
            previous = private_read(active)
            if previous.get('uri'):
                try:
                    subprocess.run(['gio', 'mount', '--unmount', previous['uri']], timeout=3,
                                   stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                except (OSError, subprocess.TimeoutExpired):
                    pass
            active.unlink(missing_ok=True)

    def open_files(self):
        status = self.status()
        uri = self.dav_uri()
        # MountOperation answers the actual prompts; piping assumed prompt order to gio is unsafe.
        identity = self.identity()
        try:
            from gi.repository import Gio, GLib
            loop, cancellable = GLib.MainLoop(), Gio.Cancellable()
            operation = Gio.MountOperation()
            token = self.token()
            errors = []

            def password(op, message, user, domain, flags):
                op.set_username(identity['device_id'])
                op.set_domain('')
                op.set_password(token)
                op.set_password_save(Gio.PasswordSave.PERMANENTLY)
                op.reply(Gio.MountOperationResult.HANDLED)

            def finished(file, result):
                try:
                    file.mount_enclosing_volume_finish(result)
                except GLib.Error as exc:
                    if not exc.matches(Gio.io_error_quark(), Gio.IOErrorEnum.ALREADY_MOUNTED):
                        errors.append(True)
                loop.quit()

            operation.connect('ask-password', password)
            file = Gio.File.new_for_uri(uri)
            file.mount_enclosing_volume(Gio.MountMountFlags.NONE, operation, cancellable, finished)
            timer = GLib.timeout_add_seconds(15, lambda: (cancellable.cancel(), loop.quit(), False)[-1])
            loop.run()
            if not cancellable.is_cancelled():
                GLib.source_remove(timer)
            if errors or cancellable.is_cancelled():
                raise Failure('mount_failed')
            self.bookmark(True)
            subprocess.Popen(['gio', 'open', uri], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except (ImportError, OSError):
            raise Failure('mount_failed') from None
        return {'ok': True, 'read_only': status.get('webdav') != 'read_write'}


def dispatch(client, body):
    op = body.get('op')
    if op == 'etat':
        try:
            return client.status()
        except Failure as exc:
            return dict(ok=False, configured=client.identity_file.exists(), enabled=exc.code != 'cloud_disabled',
                        state='unavailable', error=exc.code, message=str(exc))
    if op == 'associer':
        return client.associate()
    if op in ('lister', 'lister_destination'):
        return client.listing(body.get('parent_id', 'root'), body.get('cursor', ''))
    if op == 'lire_parent':
        return client.request('/api/cloud/v1/entries/' + body['id'])
    if op == 'ouvrir_fichier':
        return client.open_file(body['id'], body['revision'])
    if op == 'preparer_suppression':
        return client.request('/api/cloud/v1/entries/' + body['id'] + '/delete-preview')
    if op == 'supprimer':
        return client.mutation('/api/cloud/v1/entries/' + body['id'], 'DELETE',
                               {'recursive': body.get('recursive', False), 'tree_revision': body.get('tree_revision')},
                               body['revision'])
    if op == 'deplacer':
        return client.mutation('/api/cloud/v1/entries/' + body['id'] + '/move', 'POST',
                               {k: body[k] for k in ('parent_id', 'parent_revision', 'name')}, body['revision'])
    if op == 'creer_fichier':
        return client.mutation('/api/cloud/v1/uploads', 'POST',
            {k: body[k] for k in ('parent_id', 'parent_revision', 'name')} |
            {'size': 0, 'sha256': hashlib.sha256(b'').hexdigest(), 'policy': 'create', 'expected_revision': None}, commit=True)
    if op == 'dossier':
        return client.request('/api/cloud/v1/directories', 'POST',
                              {k: body[k] for k in ('name', 'parent_id', 'parent_revision')})
    if op == 'ouvrir':
        return client.open_files()
    if op == 'envoyer':
        files = body.get('files', [])
        if not isinstance(files, list) or not 1 <= len(files) <= 8 or any(not isinstance(p, str) for p in files):
            raise Failure('invalid_source')
        results = []
        for path in files:
            try:
                manifest = client.prepare(path, body['parent_id'], body['parent_revision'])
                client.launch(manifest['id'])
                results.append({'id': manifest['id'], 'ok': True})
            except Failure as exc:
                results.append({'ok': False, 'error': exc.code, 'message': str(exc)})
        return {'results': results, 'ok': all(row['ok'] for row in results)}
    if op == 'transferts':
        return {'transfers': client.transfers()}
    if op == 'effacer_transferts':
        removed = client.clear_transfers()
        return {'ok': True, 'removed': removed, 'transfers': client.transfers()}
    if op == 'reprise':
        client.status()
        client.launch(body['id'])
        return {'ok': True}
    if op == 'annuler':
        return client.cancel(body['id'])
    if op == 'resoudre':
        return client.resolve(body['id'], body['policy'])
    raise Failure('unknown_operation')


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['etat', 'associer', 'ouvrir', 'lister', 'transferts', 'requete', 'worker', 'fenetre', 'deposer', 'verifier'])
    parser.add_argument('arguments', nargs='*')
    args = parser.parse_args(argv)
    if args.action == 'verifier':
        components = {name: bool(shutil.which(name)) for name in ('secret-tool', 'gio', 'qs')}
        components['gio_python'] = importlib.util.find_spec('gi') is not None
        print(json.dumps({'ok': all(components.values()), 'components': components}))
        return 0 if all(components.values()) else 1
    if args.action in ('fenetre', 'deposer'):
        # IPC contains only a bounded file selection. No credentials or local file contents.
        # Quickshell's CLI treats bracketed arguments as argument lists: [] is
        # removed, and a selection may be split. Keep the JSON inside one string.
        data = 'json:' + json.dumps(args.arguments if args.action == 'deposer' else [], ensure_ascii=False)
        if len(data.encode()) > 16384:
            raise Failure('invalid_source')
        return subprocess.run(['qs', '-c', 'nc-ile', 'ipc', 'call', 'ile', 'cloud', data], check=False).returncode
    try:
        client = Client()
        if args.action == 'worker':
            client.worker(args.arguments[0])
            return 0
        if args.action == 'requete':
            raw = sys.stdin.buffer.read(32769)
            if len(raw) > 32768:
                raise Failure('request_too_large')
            body = json.loads(raw)
        else:
            body = {'op': args.action}
        result = dispatch(client, body)
        print(json.dumps(result, ensure_ascii=False))
        return 0
    except (Failure, OSError, ValueError, KeyError, IndexError) as exc:
        result = {'ok': False, 'error': exc.code if isinstance(exc, Failure) else 'client_error',
                  'message': str(exc) if isinstance(exc, Failure) else ('Configuration cloud invalide.' if not language() else 'Invalid cloud configuration.')}
        print(json.dumps(result, ensure_ascii=False))
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
