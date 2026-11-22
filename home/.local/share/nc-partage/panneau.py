"""Relie un panneau Cloud au protocole de partage par lignes JSON sur stdio."""
from concurrent.futures import ThreadPoolExecutor
import json
from pathlib import Path
import sys
import threading
import time
import uuid
from urllib.parse import urlsplit, unquote

from gi.repository import GLib
from partage import Node, MAC, endpoint
from radio import WifiDirect, command, local_addresses, radio_info


class Panel:
    def __init__(self):
        self.output = threading.Lock()
        self.questions = {}
        self.lock = threading.Lock()
        self.operation = threading.Lock()
        self.scanning = threading.Lock()
        self.direct = None
        downloads = GLib.get_user_special_dir(GLib.UserDirectory.DIRECTORY_DOWNLOAD) or Path.home() / "Téléchargements"
        self.node = Node(Path(GLib.get_user_config_dir()) / "nc-partage", Path(downloads) / "Noctalia",
                         self.confirm, self.status)

    def emit(self, **fields):
        with self.output:
            print(json.dumps(fields), flush=True)

    def status(self, message):
        self.emit(message=message)

    def worker(self, action):
        def run():
            try:
                action()
            except Exception as exc:
                self.status(str(exc))
        threading.Thread(target=run, daemon=True).start()

    def confirm(self, question):
        ident = uuid.uuid4().hex
        event = threading.Event()
        with self.lock:
            if self.questions:
                return False
            self.questions[ident] = [event, False]
        self.emit(question=question, ticket=ident)
        event.wait(90)
        with self.lock:
            answer = self.questions.pop(ident)[1]
            self.emit(question="", ticket=ident)
        return answer

    def listen(self, transport):
        try:
            self.node.listen(transport, lambda: self.emit(listener=transport, state="prêt"))
        except OSError as exc:
            self.emit(listener=transport, state=exc.strerror or str(exc))

    def refresh(self):
        previous = None
        while True:
            devices = []
            for bt in (False, True):
                for ident, (name, host, paired) in self.node.devices(bt).items():
                    devices.append(dict(id=ident, name=name, host=host, paired=paired, bt=bt))
            if devices != previous:
                self.emit(devices=devices)
                previous = devices
            time.sleep(1)

    def presence(self):
        previous = None
        pending, results = {}, {}
        with ThreadPoolExecutor(max_workers=3) as pool:
            while True:
                routes = self.node.paired_routes()
                now = time.monotonic()
                for ident in list(results):
                    if ident not in routes:
                        del results[ident]
                for ident, (hosts, future) in list(pending.items()):
                    if future.done():
                        del pending[ident]
                        if ident in routes and routes[ident][1] == hosts:
                            results[ident] = (hosts, future.result(), now)
                rows = []
                for ident, (name, hosts) in sorted(routes.items(), key=lambda item: item[1][0].casefold()):
                    cached = results.get(ident)
                    if cached and cached[0] != hosts:
                        cached = None
                    if ident not in pending and (not cached or now - cached[2] >= 30):
                        pending[ident] = (hosts, pool.submit(self.node.reachable, ident, hosts))
                    host = cached[1] if cached else ""
                    rows.append(dict(id=ident, name=name, host=host, bt=bool(MAC.fullmatch(host)),
                                     online=bool(host) if cached else None))
                if rows != previous:
                    self.emit(paired=rows)
                    previous = rows
                time.sleep(1)

    def addresses(self):
        self.emit(addresses=local_addresses())

    def action(self, req):
        op = req["op"]
        if op == "scan":
            if not self.scanning.acquire(False):
                return
            self.emit(scanning=True)
            try:
                if req["mode"] == "direct":
                    if self.direct is None:
                        self.direct = WifiDirect()
                    self.direct.scan(lambda peers: self.emit(radios=peers))
                elif req["mode"] == "bt":
                    command("bluetoothctl", "--timeout", "6", "scan", "on")
                    addr, devices = radio_info()
                    self.emit(btAddress=addr, bluetooth=devices)
                else:
                    self.addresses()
            finally:
                self.emit(scanning=False)
                self.scanning.release()
            return
        if not self.operation.acquire(False):
            return
        self.emit(busy=True)
        try:
            if op == "connect":
                self.status("Négociation Wi-Fi Direct… Sélectionne aussi ce PC sur l’autre écran.")
                self.direct.connect(req["adapter"], req["mac"])
                self.node.wifi_direct = True
                self.emit(link=True)
                self.addresses()
                self.status("Liaison établie. Choisis le PC dans les appareils détectés pour l’appairer.")
            elif op == "disconnect":
                self.direct.disconnect()
                self.node.wifi_direct = False
                self.emit(link=False)
                self.addresses()
                self.status("Liaison Wi-Fi Direct fermée.")
            elif op == "forget":
                if self.confirm("Oublier cet appareil sur ce PC ?"):
                    self.node.forget(req["id"])
                    self.status("Association supprimée. Pour recommencer, oublie aussi ce PC sur l’autre machine.")
            elif op in ("pair", "send"):
                host = endpoint(req["host"].strip())
                if (req["mode"] == "bt") != bool(MAC.fullmatch(host)):
                    raise ValueError("Adresse incompatible avec le mode de connexion sélectionné.")
                if req["mode"] == "direct" and not (self.direct and self.direct.active and host.startswith("169.254.")):
                    raise ValueError("Établis la liaison puis sélectionne l’adresse Wi-Fi Direct du destinataire.")
                ident = req.get("id") or None
                self.status("Connexion à l’appareil…")
                if op == "pair":
                    self.node.exchange(host, ident)
                    self.status("Appairage confirmé sur les deux machines.")
                else:
                    for url in req["files"]:
                        parts = urlsplit(url)
                        path = Path(unquote(parts.path))
                        if parts.scheme != "file" or parts.netloc not in ("", "localhost") or not path.is_file():
                            raise ValueError("Sélectionne un fichier local disponible.")
                        self.status(f"{path.name} · En attente du destinataire…")
                        self.node.exchange(host, ident, path, lambda n, total:
                                           self.status(f"{path.name} · {n:,} / {total:,} octets"))
                    self.emit(sent=True, message="Envoi terminé.")
        finally:
            self.emit(busy=False)
            self.operation.release()

    def run(self):
        self.emit(ready=True, folder=str(self.node.folder), name=self.node.name)
        for transport in ("ipv4", "ipv6", "bluetooth"):
            self.worker(lambda t=transport: self.listen(t))
        self.worker(self.node.discover)
        self.worker(self.refresh)
        self.worker(self.presence)
        self.worker(self.addresses)
        def bt_info():
            try:
                addr, devices = radio_info()
                self.emit(btAddress=addr, bluetooth=devices)
            except RuntimeError:
                pass
        self.worker(bt_info)
        for line in sys.stdin:
            req = json.loads(line)
            if req["op"] == "answer":
                with self.lock:
                    q = self.questions.get(req["ticket"])
                    if q:
                        q[1] = req["accept"] is True
                        q[0].set()
            else:
                self.worker(lambda r=req: self.action(r))


if __name__ == "__main__":
    Panel().run()
