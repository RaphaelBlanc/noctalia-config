"""NixOS : aucun changement système impératif, chemins des unités et fichiers modifiables."""
from pathlib import Path
import subprocess
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[1]
SOURCE = (REPO / "install.sh").read_text()
GARDE = SOURCE[SOURCE.index('if [ "$FAMILY" = nixos ]; then'):SOURCE.index('# Dépôt Noctalia pour Debian')]
COPIE = SOURCE[SOURCE.index("while IFS= read -r -d '' src; do"):SOURCE.index("relancer_noctalia   # la copie est finie")]


class InstallationNixos(unittest.TestCase):
    def garde(self, mode, manque=""):
        script = '''set -euo pipefail
FAMILY=nixos; MODE="$1"; OUI=1
t() { printf '%s' "$1"; }
die() { echo "$*" >&2; exit 1; }
have() { [ "$1" != "$2" ]; }
'''.replace('have() { [ "$1" != "$2" ]; }', 'have() { [ "$1" != "' + manque + '" ]; }')
        return subprocess.run(["bash", "-c", script + GARDE + '\nprintf "%s" "$MODE"', "x", mode],
                              text=True, capture_output=True, timeout=10)

    def test_oui_ne_permet_pas_les_etapes_systeme(self):
        r = self.garde("full")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(r.stdout, "nosystem")

    def test_modes_explicites_conserves(self):
        for mode in ("files", "restore", "nosystem"):
            with self.subTest(mode=mode):
                r = self.garde(mode)
                self.assertEqual(r.returncode, 0, r.stderr)
                self.assertEqual(r.stdout, mode)

    def test_assistant_root_refuse(self):
        r = self.garde("seulement")
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("docs/nixos.md", r.stderr)

    def test_dependance_absente_arrete_avant_la_copie(self):
        r = self.garde("full", "noctalia")
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("noctalia manque", r.stderr)
        self.assertEqual(self.garde("restore", "noctalia").returncode, 0)
        self.assertEqual(self.garde("files", "noctalia").returncode, 0)

    def test_copie_unites_et_terminal(self):
        for famille, mode in (("nixos", "nosystem"), ("nixos", "files"), ("fedora", "nosystem")):
            with self.subTest(famille=famille, mode=mode), tempfile.TemporaryDirectory() as d:
                base = Path(d)
                root, home, backup = (base / n for n in ("source", "home", "backup"))
                for p in (root, home, backup):
                    p.mkdir()
                for nom in (".zshrc", ".config/nvim/init.lua", ".config/systemd/user/noctalia.service"):
                    p = root / nom
                    p.parent.mkdir(parents=True, exist_ok=True)
                    p.write_text("ExecStart=/usr/bin/noctalia\n")
                script = '''set -euo pipefail
root="$1"; HOME="$2"; BK="$3"; tmp="$4"; FAMILY="$5"; MODE="$6"
SED_ARGS=(-e 's|@HOME@|test|g'); same=0; copied=0; hypr_changed=0
backup() { exit 99; }
''' + COPIE
                r = subprocess.run(["bash", "-c", script, "x", str(root), str(home), str(backup),
                                    str(base / "temp"), famille, mode], text=True, capture_output=True, timeout=10)
                self.assertEqual(r.returncode, 0, r.stderr)
                unite = (home / ".config/systemd/user/noctalia.service").read_text()
                chemin = "/run/current-system/sw/bin/" if famille == "nixos" else "/usr/bin/"
                self.assertIn("ExecStart=" + chemin + "noctalia", unite)
                for nom in (".zshrc", ".config/nvim/init.lua"):
                    self.assertEqual((home / nom).exists(), famille == "nixos" and mode != "files")

    def test_pas_de_repli_vers_un_gestionnaire_etranger(self):
        texte = (REPO / "home/.local/bin/nc-paquets").read_text()
        bloc = texte[texte.index("gestionnaire() {"):texte.index('pm="$(gestionnaire)"')]
        script = '''set -euo pipefail
os_id=nixos
osr() { echo arch; }
pacman() { echo "appel interdit" >&2; exit 99; }
''' + bloc + '\ngestionnaire'
        r = subprocess.run(["bash", "-c", script], text=True, capture_output=True, timeout=10)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(r.stdout, "")


if __name__ == "__main__":
    unittest.main()
