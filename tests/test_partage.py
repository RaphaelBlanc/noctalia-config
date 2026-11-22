"""Le protocole utilise deux vraies sessions TLS sur une paire de sockets locale."""
from pathlib import Path
import socket
import sys
import tempfile
import threading
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "home/.local/share/nc-partage"))
from partage import Node, read_message, write_message


class PartageTest(unittest.TestCase):
    def setUp(self):
        root = tempfile.TemporaryDirectory()
        self.addCleanup(root.cleanup)
        self.root = Path(root.name)
        self.threads = []
        self.codes = []
        self.a = self.node("a")
        self.b = self.node("b")

    def node(self, name):
        def confirm(text):
            if "Code de connexion : " in text:
                self.codes.append(text.split("Code de connexion : ")[1].splitlines()[0])
            return True
        return Node(self.root/name, self.root/name/"downloads", confirm, lambda text: None)

    def connect(self, receiver):
        client, server = socket.socketpair()
        receiver.slots.acquire()
        thread = threading.Thread(target=receiver.handle, args=(server, "127.0.0.1"))
        self.threads.append(thread)
        thread.start()
        self.addCleanup(thread.join, 3)
        return client

    def exchange(self, sender, receiver, path=None):
        with patch("socket.create_connection", side_effect=lambda *a, **k: self.connect(receiver)):
            sender.exchange("127.0.0.1", receiver.id, path)

    def test_pair_and_send_both_ways_after_restart(self):
        self.exchange(self.a, self.b)
        self.assertEqual(len(self.codes), 2)
        self.assertEqual(*self.codes)
        self.a = self.node("a")
        self.b = self.node("b")
        src = self.root/"échantillon.txt"
        src.write_bytes(bytes(range(256)) * 2000)
        for sender, receiver in [(self.a, self.b), (self.a, self.b), (self.b, self.a)]:
            self.exchange(sender, receiver, src)
            self.assertEqual((receiver.folder/src.name).read_bytes(), src.read_bytes())
        self.assertEqual((self.b.folder/"échantillon (1).txt").read_bytes(), src.read_bytes())

    def test_presence_checks_identity_and_tries_other_routes(self):
        self.exchange(self.a, self.b)
        prompts = len(self.codes)
        with patch("partage.connect_peer", side_effect=[TimeoutError(), self.connect(self.b)]):
            self.assertEqual(self.a.reachable(self.b.id, ("192.0.2.1", "127.0.0.1")), "127.0.0.1")
        with patch("partage.connect_peer", return_value=self.connect(self.b)):
            self.assertEqual(self.a.reachable("0" * 64, ("127.0.0.1",)), "")
        self.assertEqual(len(self.codes), prompts)
        self.assertIn(self.b.id, self.a.paired_routes())

    def test_refusal_and_wrong_token(self):
        self.b.confirm = lambda text: False
        with self.assertRaises((ValueError, OSError)):
            self.exchange(self.a, self.b)
        self.assertFalse(self.b.peers)
        self.b.confirm = lambda text: True
        self.exchange(self.a, self.b)
        src = self.root/"exemple"
        src.touch()
        self.b.confirm = lambda text: False
        with self.assertRaises(ValueError):
            self.exchange(self.a, self.b, src)
        self.b.confirm = lambda text: True
        self.a.peers[self.b.id]["token"] = "incorrect"
        with self.assertRaises(ValueError):
            self.exchange(self.a, self.b, src)
        self.assertFalse(self.b.folder.exists())

    def test_interrupted_transfer_removes_partial_file(self):
        self.exchange(self.a, self.b)
        with self.connect(self.b) as raw, self.a.client.wrap_socket(raw) as sock:
            write_message(sock, op="file", id=self.a.id, token=self.a.peers[self.b.id]["token"],
                          name="incomplet", size=99)
            self.assertTrue(read_message(sock)["ok"])
            sock.sendall(b"x")
        self.threads[-1].join(3)
        self.assertFalse(self.threads[-1].is_alive())
        self.assertEqual(list(self.b.folder.iterdir()), [])

    def test_new_transport_keeps_certificate_and_association(self):
        from partage import RFCOMM_CHANNEL, endpoint
        mac = endpoint("aa:bb:cc:dd:ee:ff")
        self.exchange(self.a, self.b)
        file = self.root / "photo"
        file.write_bytes(b"photo")
        class Radio:
            def __init__(self, sock):
                self.sock = sock
                self.address = None

            def settimeout(self, timeout):
                self.sock.settimeout(timeout)

            def connect(self, address):
                self.address = address

            def __enter__(self):
                return self.sock

            def __exit__(self, *args):
                self.sock.close()

        radio = Radio(self.connect(self.b))
        with patch("partage.bluetooth_socket", return_value=radio):
            self.a.exchange(mac, None, file)
        self.assertEqual(radio.address, (mac, RFCOMM_CHANNEL))
        self.assertEqual((self.b.folder / file.name).read_bytes(), b"photo")
        restored = self.node("a")
        self.assertEqual(restored.devices(True)[self.b.id][1], mac)
        self.assertEqual(restored.devices(False)[self.b.id][1], "127.0.0.1")
        self.assertEqual(endpoint("2001:db8::5"), "2001:db8::5")

    def test_direct_profile_is_bound_to_window_and_has_no_gateway(self):
        from gi.repository import GLib
        from radio import WifiDirect
        direct = WifiDirect.__new__(WifiDirect)
        direct.V = GLib.Variant
        direct.active = None
        with patch.object(direct, "call", return_value=("/settings/1", "/active/1", {})) as call:
            with patch.object(direct, "prop", return_value=2):
                direct.connect("/devices/1", "00:11:22:33:44:55")
            settings, adapter, _, options = call.call_args.args[-1].unpack()
            self.assertEqual(adapter, "/devices/1")
            self.assertEqual(settings["wifi-p2p"]["peer"], "00:11:22:33:44:55")
            self.assertTrue(settings["ipv4"]["never-default"])
            self.assertEqual(settings["ipv4"]["method"], "link-local")
            self.assertEqual(options, {"persist": "volatile", "bind-activation": "dbus-client"})
            direct.disconnect()
            self.assertIsNone(direct.active)
