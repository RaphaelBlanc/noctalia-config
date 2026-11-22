"""Adresses du PC, appareils BlueZ et Wi-Fi Direct NetworkManager."""
import json
import os
import subprocess
import uuid

from partage import MAC


def command(*args, timeout=12):
    try:
        proc = subprocess.run(args, capture_output=True, text=True, timeout=timeout,
                              env={**os.environ, "LC_ALL": "C"})
    except FileNotFoundError:
        raise RuntimeError(f"{args[0]} est indisponible") from None
    except subprocess.TimeoutExpired:
        raise RuntimeError(f"{args[0]} ne répond pas") from None
    if proc.returncode:
        raise RuntimeError(proc.stderr.strip() or proc.stdout.strip() or f"Échec de {args[0]}")
    return proc.stdout


def radio_info():
    info = command("bluetoothctl", "show", timeout=4)
    adapter = next((word for word in info.split() if MAC.fullmatch(word)), "")
    if not adapter or "Powered: yes" not in info:
        raise RuntimeError("Active le Bluetooth sur ce PC")
    devices = {}
    for line in command("bluetoothctl", "devices", timeout=4).splitlines():
        fields = line.split(None, 2)
        if len(fields) == 3 and fields[0] == "Device" and MAC.fullmatch(fields[1]):
            devices[fields[1].upper()] = fields[2]
    return adapter, devices


def local_addresses():
    rows = json.loads(command("ip", "-j", "address", "show", "up"))
    return [addr["local"] for row in rows for addr in row.get("addr_info", [])
            if (addr.get("scope") == "global" or addr.get("family") == "inet" and addr.get("scope") == "link") and addr.get("family") in ("inet", "inet6")]


class WifiDirect:
    """Profil volatile attaché au client D-Bus qui possède la fenêtre."""
    service = "org.freedesktop.NetworkManager"
    root = "/org/freedesktop/NetworkManager"
    device = service + ".Device.WifiP2P"

    def __init__(self):
        from gi.repository import Gio, GLib
        self.bus = Gio.bus_get_sync(Gio.BusType.SYSTEM, None)
        self.V = GLib.Variant
        self.active = None

    def call(self, path, interface, method, args=None):
        return self.bus.call_sync(self.service, path, interface, method, args,
                                  None, 0, 5000, None).unpack()

    def prop(self, path, interface, name):
        return self.call(path, "org.freedesktop.DBus.Properties", "Get",
                         self.V("(ss)", (interface, name)))[0]

    def scan(self, publish):
        import time
        devices = self.call(self.root, self.service, "GetDevices")[0]
        adapters = [d for d in devices if self.prop(d, self.service + ".Device", "DeviceType") == 30]
        if not adapters:
            raise RuntimeError("NetworkManager ne détecte aucune interface Wi-Fi Direct compatible.")
        for adapter in adapters:
            self.call(adapter, self.device, "StartFind", self.V("(a{sv})", ({"timeout": self.V("i", 45)},)))
        for _ in range(10):
            peers = []
            for adapter in adapters:
                for peer in self.prop(adapter, self.device, "Peers"):
                    props = self.call(peer, "org.freedesktop.DBus.Properties", "GetAll",
                                      self.V("(s)", (self.service + ".WifiP2PPeer",)))[0]
                    mac = props.get("HwAddress", "")
                    if MAC.fullmatch(mac):
                        peers.append(dict(name=props.get("Name") or mac, mac=mac, adapter=adapter))
            publish(peers)
            time.sleep(1)

    def connect(self, adapter, mac):
        import time
        v = self.V
        if self.active:
            self.disconnect()
        settings = {
            "connection": {"type": v("s", "wifi-p2p"), "id": v("s", "Noctalia Direct"),
                           "uuid": v("s", str(uuid.uuid4())), "autoconnect": v("b", False)},
            "wifi-p2p": {"peer": v("s", mac), "wps-method": v("u", 4)},
            "ipv4": {"method": v("s", "link-local"), "never-default": v("b", True)},
            "ipv6": {"method": v("s", "link-local"), "never-default": v("b", True)}}
        options = {"persist": v("s", "volatile"), "bind-activation": v("s", "dbus-client")}
        args = v("(a{sa{sv}}ooa{sv})", (settings, adapter, "/", options))
        _, self.active, _ = self.call(self.root, self.service, "AddAndActivateConnection2", args)
        try:
            for _ in range(65):
                state = self.prop(self.active, self.service + ".Connection.Active", "State")
                if state == 2:
                    return
                if state >= 3:
                    break
                time.sleep(1)
            raise RuntimeError("Liaison refusée ou expirée. Sélectionne l’autre PC sur les deux écrans.")
        except Exception:
            try:
                self.disconnect()
            finally:
                self.active = None
            raise

    def disconnect(self):
        if self.active:
            self.call(self.root, self.service, "DeactivateConnection", self.V("(o)", (self.active,)))
            self.active = None
