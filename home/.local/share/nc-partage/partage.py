"""Partage Noctalia v1. Découverte IPv4 et échanges point à point sous TLS."""
import hashlib
import hmac
import ipaddress
import json
import os
from pathlib import Path
import re
import secrets
import socket
import ssl
import struct
import subprocess
import tempfile
import threading
import time

PORT = 43827
RFCOMM_CHANNEL = 22
MAC = re.compile(r"(?:[0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}")
MAGIC = b"NC-PARTAGE/1 "
HEX = re.compile(r"[a-f0-9]{64}")
CHUNK = 262144


def endpoint(address):
    if MAC.fullmatch(address):
        return address.upper()
    return str(ipaddress.ip_address(address))


def connect_peer(host, timeout=None):
    if MAC.fullmatch(host):
        raw = bluetooth_socket()
        try:
            raw.settimeout(20 if timeout is None else timeout)
            raw.connect((host, RFCOMM_CHANNEL))
            return raw
        except OSError:
            raw.close()
            raise
    return socket.create_connection((host, PORT), timeout=10 if timeout is None else timeout)


def bluetooth_socket():
    if not hasattr(socket, "BTPROTO_RFCOMM"):
        raise OSError("Bluetooth classique indisponible sur ce système")
    return socket.socket(socket.AF_BLUETOOTH, socket.SOCK_STREAM, socket.BTPROTO_RFCOMM)


def label(value):
    if not isinstance(value, str) or not value or len(value) > 255 or not value.isprintable():
        raise ValueError("Nom invalide")
    return value


def receive(sock, size):
    data = bytearray()
    while len(data) < size:
        part = sock.recv(size - len(data))
        if not part:
            raise EOFError("Connexion interrompue")
        data.extend(part)
    return bytes(data)


def read_message(sock):
    length, = struct.unpack("!I", receive(sock, 4))
    if length > 4096:
        raise ValueError("Message trop long")
    obj = json.loads(receive(sock, length))
    if not isinstance(obj, dict):
        raise ValueError("Message invalide")
    return obj


def write_message(sock, **fields):
    data = json.dumps(fields).encode()
    sock.sendall(struct.pack("!I", len(data)) + data)


def pairing_code(sock):
    binding = sock.get_channel_binding("tls-unique")
    if not binding:
        raise ValueError("Impossible de vérifier la connexion TLS")
    digits = hashlib.sha256(b"nc-partage/1" + binding).hexdigest()[:10].upper()
    return digits[:5] + " " + digits[5:]


def accepted(sock):
    if read_message(sock).get("ok") is not True:
        raise ValueError("Demande refusée ou expirée")


def save_file(sock, folder, name, size):
    if label(name) != Path(name).name or name in {".", ".."}:
        raise ValueError("Nom de fichier invalide")
    folder.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(dir=folder, prefix=".nc-partage-") as tmp:
        while size:
            block = receive(sock, min(size, CHUNK))
            tmp.write(block)
            size -= len(block)
        tmp.flush()
        os.fsync(tmp.fileno())
        # Publication atomique, même en cas de réception simultanée du même nom.
        path = folder / name
        index = 1
        while True:
            try:
                os.link(tmp.name, path)
                return path
            except FileExistsError:
                path = folder / f"{Path(name).stem} ({index}){Path(name).suffix}"
                index += 1


class Node:
    def __init__(self, state, folder, confirm, status):
        self.state, self.folder = state, folder
        self.confirm, self.status = confirm, status
        state.mkdir(mode=0o700, parents=True, exist_ok=True)
        pem = state / "identite.pem"
        if not pem.exists():
            with tempfile.TemporaryDirectory(dir=state) as d:
                key, cert = Path(d)/"key", Path(d)/"cert"
                subprocess.run(["openssl", "req", "-x509", "-newkey", "rsa:3072", "-nodes",
                                "-days", "3650", "-subj", "/CN=Noctalia", "-keyout", str(key),
                                "-out", str(cert)], check=True, stderr=subprocess.PIPE)
                combined = Path(d)/"identity"
                combined.write_bytes(cert.read_bytes() + key.read_bytes())
                combined.chmod(0o600)
                os.replace(combined, pem)
        cert_text = pem.read_text().split("-----END CERTIFICATE-----")[0] + "-----END CERTIFICATE-----"
        self.id = hashlib.sha256(ssl.PEM_cert_to_DER_cert(cert_text)).hexdigest()
        self.name = socket.gethostname()[:100]
        self.server = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        self.server.minimum_version = ssl.TLSVersion.TLSv1_3
        self.server.load_cert_chain(str(pem))
        self.client = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
        self.client.minimum_version = ssl.TLSVersion.TLSv1_3
        self.client.check_hostname = False
        self.client.verify_mode = ssl.CERT_NONE  # empreinte épinglée ou code comparé sur les deux écrans
        self.lock = threading.Lock()
        path = state / "pairs.json"
        self.peers = json.loads(path.read_text()) if path.exists() else {}
        self.seen = {}
        self.wifi_direct = False
        self.slots = threading.BoundedSemaphore(6)

    def store_peers(self, updated):
        with tempfile.NamedTemporaryFile("w", dir=self.state, delete=False) as tmp:
            json.dump(updated, tmp)
        os.replace(tmp.name, self.state / "pairs.json")
        self.peers = updated

    def remember(self, ident, name, host, token):
        with self.lock:
            if ident in self.peers:
                raise ValueError("Appareil déjà appairé")
            updated = dict(self.peers)
            updated[ident] = dict(name=name, host=host, token=token)
            self.store_peers(updated)

    def remember_route(self, ident, host):
        key = "bt" if MAC.fullmatch(host) else "ip"
        with self.lock:
            peer = self.peers.get(ident)
            if peer and peer.get(key, peer["host"]) != host:
                self.store_peers({**self.peers, ident: {**peer, key: host}})

    def forget(self, ident):
        with self.lock:
            updated = dict(self.peers)
            updated.pop(ident, None)
            self.store_peers(updated)

    def devices(self, bluetooth=False):
        with self.lock:
            result = {}
            for ident, peer in self.peers.items():
                address = peer.get("bt" if bluetooth else "ip", peer["host"])
                if bool(MAC.fullmatch(address)) == bluetooth:
                    result[ident] = (peer["name"], address, True)
            if bluetooth:
                return result
            for i, (name, host, when) in self.seen.items():
                if time.monotonic() - when < 15:
                    result[i] = (self.peers.get(i, {}).get("name", name), host, i in self.peers)
            return result

    def paired_routes(self):
        with self.lock:
            now = time.monotonic()
            routes = {}
            for ident, peer in self.peers.items():
                seen = self.seen.get(ident)
                recent = seen[1] if seen and now - seen[2] < 15 else None
                hosts = (recent, peer.get("ip"), peer["host"], peer.get("bt"))
                routes[ident] = (peer["name"], tuple(dict.fromkeys(h for h in hosts if h)))
            return routes

    def reachable(self, ident, hosts):
        for host in hosts:
            try:
                with connect_peer(host, timeout=4) as raw, self.client.wrap_socket(raw) as sock:
                    if hashlib.sha256(sock.getpeercert(binary_form=True)).hexdigest() != ident:
                        continue
                    write_message(sock, op="presence", id=self.id)
                    # Les versions antérieures répondent ok=false à une opération inconnue.
                    if type(read_message(sock).get("ok")) is bool:
                        return host
            except (OSError, EOFError, ValueError):
                continue
        return ""

    def discover(self):
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as udp:
            udp.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
            udp.bind(("", PORT))
            udp.settimeout(1)
            beacon = MAGIC + json.dumps([self.id, self.name]).encode()
            next_ping = 0
            while True:
                now = time.monotonic()
                if now >= next_ping:
                    destinations = ["255.255.255.255"]
                    if self.wifi_direct:
                        destinations.append("169.254.255.255")
                    for broadcast in destinations:
                        try:
                            udp.sendto(beacon, (broadcast, PORT))
                        except OSError:
                            pass
                    next_ping = now + 3
                    with self.lock:
                        self.seen = {i: p for i, p in self.seen.items() if now - p[2] < 15}
                try:
                    data, (host, _) = udp.recvfrom(1024)
                    if data.startswith(MAGIC):
                        ident, name = json.loads(data[len(MAGIC):])
                        if HEX.fullmatch(ident) and ident != self.id:
                            with self.lock:
                                if len(self.seen) < 256 or ident in self.seen:
                                    self.seen[ident] = (label(name), host, now)
                except (socket.timeout, ValueError, TypeError):
                    continue

    def listen(self, transport="ipv4", ready=None):
        if transport == "bluetooth":
            listener = bluetooth_socket()
            address = (socket.BDADDR_ANY, RFCOMM_CHANNEL)
        else:
            family = socket.AF_INET6 if transport == "ipv6" else socket.AF_INET
            listener = socket.socket(family, socket.SOCK_STREAM)
            address = ("::" if transport == "ipv6" else "", PORT)
        with listener:
            if transport != "bluetooth":
                listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            if transport == "ipv6":
                listener.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 1)
            listener.bind(address)
            listener.listen(6)
            if ready:
                ready()
            while True:
                raw, address = listener.accept()
                if self.slots.acquire(blocking=False):
                    host = address[0]
                    if transport == "ipv6" and address[3]:
                        host += "%" + str(address[3])
                    threading.Thread(target=self.handle, args=(raw, host), daemon=True).start()
                else:
                    raw.close()

    def handle(self, raw, host):
        try:
            with raw:
                raw.settimeout(8)
                with self.server.wrap_socket(raw, server_side=True) as sock:
                    msg = read_message(sock)
                    sock.settimeout(120)
                    ident = msg["id"]
                    if not HEX.fullmatch(ident) or ident == self.id:
                        raise ValueError("Identité invalide")
                    if msg["op"] == "presence":
                        write_message(sock, ok=ident in self.peers)
                        return
                    if msg["op"] == "pair" and ident not in self.peers:
                        name = label(msg["name"])
                        prompt = f"Appairer {name} ({host}) ?\n\nCode de connexion : {pairing_code(sock)}\nValide uniquement si les deux écrans affichent ce code."
                        if self.confirm(prompt) and read_message(sock).get("confirm") is True:
                            token = secrets.token_hex(32)
                            self.remember(ident, name, host, token)
                            write_message(sock, ok=True, token=token, name=self.name)
                            self.status(f"{name} appairé")
                            return
                    elif msg["op"] == "file":
                        peer = self.peers.get(ident)
                        if peer and hmac.compare_digest(peer["token"], msg["token"]):
                            name, size = label(msg["name"]), msg["size"]
                            if Path(name).name != name or name in {".", ".."} or type(size) is not int or size < 0:
                                raise ValueError("Fichier invalide")
                            if self.confirm(f"Recevoir {name} ({size:,} octets) de {peer['name']} ?"):
                                write_message(sock, ok=True)
                                path = save_file(sock, self.folder, name, size)
                                write_message(sock, ok=True)
                                self.remember_route(ident, host)
                                self.status(f"Reçu dans {path}")
                                return
                    write_message(sock, ok=False)
        except (EOFError, OSError, ValueError, KeyError, TypeError) as exc:
            self.status(f"Réception interrompue : {exc}")
        finally:
            self.slots.release()

    def exchange(self, host, ident, path=None, progress=None):
        host = endpoint(host)
        with connect_peer(host) as raw, self.client.wrap_socket(raw) as sock:
            remote = hashlib.sha256(sock.getpeercert(binary_form=True)).hexdigest()
            if remote == self.id or (ident and ident != remote):
                raise ValueError("Identité de l’appareil inattendue")
            sock.settimeout(120)
            if path is None:
                if remote in self.peers:
                    raise ValueError("Cet appareil est déjà appairé")
                write_message(sock, op="pair", id=self.id, name=self.name)
                ok = self.confirm(f"Appairer la machine {host} ?\n\nCode de connexion : {pairing_code(sock)}\nValide uniquement si les deux écrans affichent ce code.")
                write_message(sock, confirm=ok)
                if not ok:
                    raise ValueError("Appairage annulé")
                reply = read_message(sock)
                if reply.get("ok") is not True or not HEX.fullmatch(reply["token"]):
                    raise ValueError("Appairage refusé")
                self.remember(remote, label(reply["name"]), host, reply["token"])
                return
            peer = self.peers.get(remote)
            if not peer:
                raise ValueError("Appaire d’abord cet appareil")
            with path.open("rb") as src:
                total = remaining = os.fstat(src.fileno()).st_size
                next_update = 0
                write_message(sock, op="file", id=self.id, token=peer["token"], name=label(path.name), size=remaining)
                accepted(sock)
                while remaining:
                    data = src.read(min(CHUNK, remaining))
                    if not data:
                        raise EOFError("Fichier source modifié")
                    sock.sendall(data)
                    remaining -= len(data)
                    now = time.monotonic()
                    if progress and (now >= next_update or not remaining):
                        progress(total - remaining, total)
                        next_update = now + 0.25
                accepted(sock)
                self.remember_route(remote, host)
