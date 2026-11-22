"""Opt-in Wayland smoke: actual cloud QML and serialized JSON process requests.

NC_CLOUD_QML=1 python3 -B -m unittest tests.test_cloud_qml -v
Uses an isolated HOME and a fake client; briefly opens a separate test window.
"""
import os
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

SOURCE = Path(__file__).resolve().parents[1] / 'home/.config/quickshell/nc-ile'


@unittest.skipUnless(os.environ.get('NC_CLOUD_QML') == '1' and os.environ.get('WAYLAND_DISPLAY') and shutil.which('qs'),
                     'Opt-in Wayland session and Quickshell required')
class CloudQml(unittest.TestCase):
    def run_cloud(self, shell=None, fake_extra=''):
        display = os.environ['WAYLAND_DISPLAY']
        socket = Path(os.environ.get('NC_CLOUD_WAYLAND_SOCKET') or
                      (display if display.startswith('/') else f'/run/user/{os.getuid()}/{display}'))
        if not socket.exists():
            self.skipTest('Wayland socket unavailable; set NC_CLOUD_WAYLAND_SOCKET')
        with tempfile.TemporaryDirectory(prefix='nc-cloud-qml-') as temporary:
            root = Path(temporary)
            for name in ('Cloud.qml', 'CloudPartage.qml', 'CloudActions.qml', 'CloudCarte.qml', 'CloudBouton.qml', 'CloudCibleDepot.qml', 'CloudDepot.qml', 'CloudEtat.qml', 'JarvisBouton.qml', 'Texte.qml', 'Ico.qml', 'Gabarit.qml'):
                shutil.copyfile(SOURCE / name, root / name)
            (root / 'Couleurs.qml').write_text('pragma Singleton\nimport QtQuick\nQtObject {'
                'readonly property color fond: "#171a24"; readonly property color gris2: "#292e40";'
                'readonly property color carte: "#262b35"; readonly property color vert: "#65c98a"; readonly property color orange: "#edb863"; readonly property color rouge: "#df6464";'
                'readonly property color gris3: "#3c435c"; readonly property color texte: "#f0f1f5";'
                'readonly property color texteSec: "#a9b0c2"; readonly property color accent: "#73d4e8";'
                'readonly property color accentClair: "#9defff"; readonly property color surAccent: "#12151d" }')
            (root / 'Reglages.qml').write_text('pragma Singleton\nimport QtQuick\nQtObject { property bool sobre: false; property bool en: false; function val(k,d) { return d } function t(a,b) { return a } }')
            (root / 'Etat.qml').write_text('pragma Singleton\nimport QtQuick\nQtObject { property bool ecranVu: true }')
            (root / 'shell.qml').write_text(shell or ('import QtQuick\nimport Quickshell\nShellRoot { Cloud { } '
                'CloudDepot { modelData: Quickshell.screens[0] } '
                '''Timer { interval: 500; running: true; onTriggered: { CloudEtat.choisir({id: "file", name: "test.txt", kind: "file", revision: "r1"}); CloudEtat.action = "renommer" } }
                Timer { interval: 800; running: true; onTriggered: CloudEtat.preparerSuppression() }
                Timer { interval: 1150; running: true; onTriggered: { if (CloudEtat.action !== "supprimer") console.error("Delete preview not rendered"); CloudEtat.preparerDeplacement() } }
                Timer { interval: 1600; running: true; onTriggered: { if (CloudEtat.destination.revision !== "r1") console.error("Destination not rendered"); Qt.quit() } } }'''))
            fake = root / 'fake-home'
            command = fake / '.local/bin/nc-cloud'
            command.parent.mkdir(parents=True)
            command.write_text('''#!/usr/bin/env python3
import json,sys
from pathlib import Path
body=json.load(sys.stdin)
with Path(__file__).with_name("calls").open("a") as f: f.write(json.dumps(body)+"\\n")
responses={"etat":{"api_version":1,"server_id":"test","space_id":"personal","enabled":True,"configured":True,"state":"ready"},"transferts":{"transfers":[]},"lister":{"parent":{"id":"root","revision":"r1","name":"Cloud JARVIS"},"entries":[],"next_cursor":None}}
responses["preparer_suppression"]={"entry":{"id":"file","name":"test.txt","kind":"file","revision":"r1"},"tree_revision":"a"*64,"files":1,"directories":0}
responses["lister_destination"]=responses["lister"]
''' + fake_extra + '\nprint(json.dumps(responses.get(body["op"],{"ok":True})))\n')
            command.chmod(0o755)
            config = fake / '.config/nc'
            config.mkdir(parents=True)
            (config / 'assistant.conf').touch()
            result = subprocess.run(['qs', '-p', str(root), '--no-color'], text=True, capture_output=True, timeout=10,
                                    env=dict(os.environ, HOME=str(fake), QT_QPA_PLATFORM='wayland',
                                             XDG_RUNTIME_DIR=str(socket.parent), WAYLAND_DISPLAY=socket.name))
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertNotIn('ERROR:', result.stdout + result.stderr)
            self.assertNotIn('FAIL!', result.stdout + result.stderr)
            return [json.loads(line) for line in command.with_name('calls').read_text().splitlines()]

    def test_window_depot_and_process_queue(self):
        calls = self.run_cloud()
        self.assertEqual([c['op'] for c in calls], ['etat', 'transferts', 'lister', 'preparer_suppression', 'lister_destination'])

    def test_clear_finished_history_works_offline_and_updates_window(self):
        calls = self.run_cloud('''import QtQuick
import Quickshell
import QtTest
ShellRoot {
    Cloud { id: window }
    TestCase { id: finder; when: false }
    Timer { interval: 500; running: true; onTriggered: {
        CloudEtat.enLigne = false
        var button = finder.findChild(window.contentItem, "cloudEffacerTransferts")
        if (!button || !button.enabled) { console.error("Clear history unavailable offline"); Qt.quit(); return }
        button.clic()
    } }
    Timer { interval: 900; running: true; onTriggered: {
        if (CloudEtat.transferts.length !== 1 || CloudEtat.transferts[0].state !== "interrupted") console.error("History not updated or interrupted transfer removed")
        if (finder.findChild(window.contentItem, "cloudEffacerTransferts").enabled) console.error("Clear history still enabled with no finished transfers")
        Qt.quit()
    } }
}''', '''
cleared = Path(__file__).with_name("cleared")
rows = [{"id": "interrupted", "state": "interrupted", "name": "resume.txt", "size": 5, "sent": 0}]
if body["op"] == "effacer_transferts":
    cleared.touch()
    responses["effacer_transferts"] = {"ok": True, "removed": 2, "transfers": rows}
if not cleared.exists():
    rows += [{"id": "done", "state": "committed", "name": "done.txt", "size": 5, "sent": 5},
             {"id": "cancelled", "state": "cancelled", "name": "cancelled.txt", "size": 5, "sent": 0}]
responses["transferts"] = {"transfers": rows}
''')
        self.assertEqual(sum(c['op'] == 'effacer_transferts' for c in calls), 1)

    def check_worker_refresh(self, delay):
        calls = self.run_cloud('''import QtQuick
import Quickshell
ShellRoot {
    Cloud { }
    Timer { interval: 400; running: true; onTriggered: {
        CloudEtat.fichiers = ["file:///tmp/example.txt"]; CloudEtat.envoyer()
    } }
    Timer { interval: 2400; running: true; onTriggered: {
        if (!CloudEtat.dossiers.some(e => e.id === "new-file")) console.error("Committed file missing from listing")
        if (CloudEtat.statut.used_bytes !== 5) console.error("Quota not refreshed")
        CloudEtat.demander({op: "transferts"}); CloudEtat.demander({op: "transferts"})
    } }
    Timer { interval: 2800; running: true; onTriggered: Qt.quit() }
}''', '''
import time
started = Path(__file__).with_name("started")
if body["op"] == "envoyer":
    started.write_text(str(time.monotonic()))
    responses["envoyer"] = {"ok": True, "results": [{"ok": True}]}
if started.exists():
    committed = time.monotonic() - float(started.read_text()) > COMMIT_DELAY
    responses["transferts"] = {"transfers": [{"id": "upload", "state": "committed" if committed else "uploading", "name": "example.txt", "size": 5, "sent": 5}]}
    if committed:
        responses["lister"]["entries"] = [{"id": "new-file", "name": "example.txt", "kind": "file", "revision": "r2", "size": 5}]
        responses["etat"]["used_bytes"] = 5
'''.replace('COMMIT_DELAY', str(delay)))
        self.assertEqual(sum(c['op'] == 'lister' for c in calls), 2)
        self.assertEqual(sum(c['op'] == 'etat' for c in calls), 2)

    def test_finished_worker_refreshes_listing_and_quota_once(self):
        self.check_worker_refresh(0.5)

    def test_commit_before_first_poll_refreshes_listing(self):
        self.check_worker_refresh(0)

    def test_internal_drag_and_file_picker(self):
        calls = self.run_cloud('''import QtQuick
import Quickshell
import QtTest
ShellRoot {
    Cloud { id: window }
    TestCase { id: gestures; when: false }
    function dragEntry(id, target) {
        var source = gestures.findChild(window.contentItem, "cloudEntree-" + id)
        if (!source || !target) throw new Error("Drag source or target missing")
        gestures.mousePress(source, 80, 24, Qt.LeftButton)
        gestures.mouseMove(source, 120, 24, 30, Qt.LeftButton)
        gestures.mouseMove(target, 20, 16, 50, Qt.LeftButton)
        gestures.mouseRelease(target, 20, 16, Qt.LeftButton)
    }
    Timer { interval: 300; running: true; onTriggered: {
        dragEntry("folder", gestures.findChild(window.contentItem, "cloudEntree-folder"))
    } }
    Timer { interval: 500; running: true; onTriggered: {
        dragEntry("file", gestures.findChild(window.contentItem, "cloudEntree-folder"))
    } }
    Timer { interval: 900; running: true; onTriggered: {
        if (CloudEtat.dossiers.some(e => e.id === "file")) console.error("Drag into folder failed")
        gestures.mouseDoubleClickSequence(gestures.findChild(window.contentItem, "cloudEntree-folder"), 80, 24)
    } }
    Timer { interval: 1300; running: true; onTriggered: {
        dragEntry("file", gestures.findChild(window.contentItem, "cloudParent"))
    } }
    Timer { interval: 1700; running: true; onTriggered: {
        if (CloudEtat.dossiers.some(e => e.id === "file")) console.error("Drag to parent failed")
        dragEntry("child-folder", gestures.findChild(window.contentItem, "cloudParent"))
    } }
    Timer { interval: 2100; running: true; onTriggered: {
        if (CloudEtat.dossiers.length) console.error("Second drag to parent failed")
        var picker = gestures.findChild(window, "cloudImportation")
        if (!picker) { console.error("File picker missing"); return }
        picker.options = FileDialog.DontUseNativeDialog
        var button = gestures.findChild(window.contentItem, "cloudImporter")
        CloudEtat.fichiers = ["file:///tmp/previous.txt"]
        gestures.mouseClick(button, button.width / 2, 16)
        if (!picker.visible) console.error("Import button did not open file picker")
        picker.reject()
        if (CloudEtat.fichiers.length !== 1 || CloudEtat.fichiers[0] !== "file:///tmp/previous.txt") console.error("Cancel changed selection")
        picker.selectedFile = "file:///tmp/example.txt"
        picker.accept()
        if (CloudEtat.fichiers.length !== 1 || CloudEtat.fichiers[0] !== "file:///tmp/example.txt") console.error("Picker selection not staged")
        if (CloudEtat.dossier.id !== "folder") console.error("Picker changed destination")
        Qt.quit()
    } }
    Timer { interval: 6000; running: true; onTriggered: { console.error("Gesture test timed out"); Qt.quit() } }
}'''.replace('import QtTest', 'import QtTest\nimport QtQuick.Dialogs'), '''
state_file = Path(__file__).with_name("tree")
tree = json.loads(state_file.read_text()) if state_file.exists() else {
    "root": {"id": "root", "name": "Cloud JARVIS", "kind": "directory", "revision": "r1", "parent": None},
    "file": {"id": "file", "name": "example.txt", "kind": "file", "revision": "r1", "parent": "root", "size": 5},
    "folder": {"id": "folder", "name": "Folder", "kind": "directory", "revision": "r1", "parent": "root"},
    "child-folder": {"id": "child-folder", "name": "Child", "kind": "directory", "revision": "r1", "parent": "folder"}}
if body["op"] == "deplacer":
    entry, parent = tree[body["id"]], tree[body["parent_id"]]
    if body["parent_revision"] != parent["revision"] or body["revision"] != entry["revision"]:
        responses["deplacer"] = {"ok": False, "error": "version_conflict"}
    else:
        for directory in {entry["parent"], parent["id"]}:
            tree[directory]["revision"] += "x"
        entry.update(parent=parent["id"], revision=entry["revision"] + "x")
        state_file.write_text(json.dumps(tree))
        responses["deplacer"] = {"moved": True, "entry": entry}
if body["op"] == "lister":
    parent = body.get("parent_id", "root")
    responses["lister"] = {"parent": tree[parent], "entries": [e for e in tree.values() if e["parent"] == parent]}
if body["op"] == "lire_parent":
    responses["lire_parent"] = {"entry": tree[body["id"]]}
''')
        moves = [c for c in calls if c['op'] == 'deplacer']
        self.assertEqual([(c['id'], c['parent_id']) for c in moves],
                         [('file', 'folder'), ('file', 'root'), ('child-folder', 'root')])
        self.assertNotEqual(moves[1]['parent_revision'], moves[2]['parent_revision'])
        self.assertFalse(any(c['op'] == 'envoyer' for c in calls))


if __name__ == '__main__':
    unittest.main()
