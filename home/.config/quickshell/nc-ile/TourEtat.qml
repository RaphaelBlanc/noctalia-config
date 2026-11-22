pragma Singleton
// État de la Tour (Tour.qml, tuile du Centre de contrôle, indicateur de la pilule).
// Tout passe par ~/.local/bin/nc-tour :
//   - « nc-tour indicateur --json » : léger, pour la pilule et la tuile du Centre de contrôle
//   - « nc-tour etat-json » : télémétrie complète (CPU, RX 7800 XT, VRAM, Sunshine, Ollama, profils), lu quand la fenêtre Tour est ouverte
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: t

    readonly property string bin: Quickshell.env("HOME") + "/.local/bin/nc-tour"
    signal ouvrirPanneau()
    function demanderPanneau() { ouvrirPanneau() }

    property bool panneauOuvert: false
    property bool lu: false
    property bool enLigne: false
    property bool enStream: false
    property bool iaTour: false
    property int pingMs: -1
    property string modeReseau: "hors_ligne"
    property string relais: ""
    property string ip: "198.51.100.10"
    property string nom: "Tour-Exemple"
    property string profil: "equilibre"
    property var profils: [
        { id: "qualite", nom: "Qualité Max (LAN / Fibre)", detail: "1440p · 120 FPS · 50 Mbps · AV1" },
        { id: "equilibre", nom: "Équilibré (60 FPS)", detail: "1440p · 60 FPS · 25 Mbps · AV1" },
        { id: "turquie", nom: "Ultra Basse Latence (Turquie)", detail: "1080p · 60 FPS · 12 Mbps · AV1" }
    ]

    // Télémétrie (lue quand le panneau est ouvert et la tour en ligne)
    property int cpuPct: -1
    property int cpuTemp: -1
    property real ramUtiliseeGo: -1
    property real ramTotaleGo: 31
    property int gpuPct: -1
    property int gpuTemp: -1
    property real vramUtiliseeGo: -1
    property real vramTotaleGo: 16
    property bool sunshineActif: false
    property bool ecranVirtuel: false
    property bool ollamaActif: false
    property var ollamaModeles: []

    property bool occupe: false
    property string message: ""
    property bool erreur: false

    // Indicateur dans la pilule fermée : visible dès que la tour est allumée ou en stream
    readonly property bool indicateur: (enLigne || enStream) && Reglages.val("TOUR_INDICATEUR", "oui") !== "non"
    readonly property string libelle: {
        if (Partage.silence) return "Tour"
        if (enStream) return Reglages.t("Tour · Stream", "Tower · Stream")
        if (enLigne && pingMs > 0) return "Tour · " + pingMs + " ms"
        if (enLigne) return Reglages.t("Tour · En ligne", "Tower · Online")
        return Reglages.t("Tour · Éteinte", "Tower · Off")
    }
    readonly property string sousTitreTuile: {
        if (enStream) return Reglages.t("En stream (Moonlight)", "Streaming (Moonlight)")
        if (enLigne) return (pingMs > 0 ? pingMs + " ms · " : "") + (modeReseau === "direct" ? "Direct" : (modeReseau === "relais" ? "Relais" : "Tailscale"))
        return Reglages.t("Éteinte · Ouvrir", "Off · Open")
    }

    // ── Fichier d'état de la pilule de la barre ($XDG_RUNTIME_DIR/nc-tour-barre.json, 0600, écriture atomique) ──
    readonly property string barreJson: !lu ? "" : JSON.stringify({
        en_ligne: enLigne,
        en_stream: enStream,
        ping_ms: pingMs,
        masque_partage: Partage.silence
    })
    property string barreEcrit: ""
    property string barreEnCours: ""
    onBarreJsonChanged: lancerBarre()
    function lancerBarre() {
        if (ecritureBarre.running || barreJson === barreEcrit) return
        barreEnCours = barreJson
        ecritureBarre.command = ["sh", "-c", "umask 077; d=${XDG_RUNTIME_DIR:-}; [ -n \"$d\" ] && [ -d \"$d\" ] || exit 0; f=\"$d/nc-tour-barre.json\"; "
                                 + "if [ -n \"$1\" ]; then printf '%s\\n' \"$1\" > \"$f.tmp\" && mv -f \"$f.tmp\" \"$f\"; else rm -f \"$f\"; fi", "sh", barreEnCours]
        ecritureBarre.running = true
    }
    Process {
        id: ecritureBarre
        onExited: { t.barreEcrit = t.barreEnCours; t.lancerBarre() }
    }

    function rafraichir() {
        if (!lectureInd.running) lectureInd.running = true
        if (panneauOuvert && !lectureEtat.running) lectureEtat.running = true
    }

    onPanneauOuvertChanged: {
        if (panneauOuvert) {
            message = ""
            erreur = false
            rafraichir()
        }
    }

    // Sondage léger : toutes les 4 s panneau ouvert, sinon toutes les 15 s tant que l'écran est allumé
    Timer {
        id: cadence
        interval: t.panneauOuvert ? 4000 : 15000
        repeat: true
        running: Etat.ecranVu
        triggeredOnStart: true
        onTriggered: t.rafraichir()
    }

    Process {
        id: lectureInd
        command: [t.bin, "indicateur", "--json"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var d = JSON.parse(text)
                    t.enLigne = Boolean(d.en_ligne)
                    t.enStream = Boolean(d.en_stream)
                    t.iaTour = Boolean(d.ia_tour)
                    t.pingMs = typeof d.ping_ms === "number" ? d.ping_ms : -1
                    t.modeReseau = String(d.mode_reseau || "hors_ligne")
                    t.lu = true
                } catch (e) {}
            }
        }
    }

    Process {
        id: lectureEtat
        command: [t.bin, "etat-json"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var d = JSON.parse(text)
                    t.enLigne = Boolean(d.en_ligne)
                    t.enStream = Boolean(d.en_stream)
                    t.iaTour = Boolean(d.ia_tour)
                    t.pingMs = typeof d.ping_ms === "number" ? d.ping_ms : -1
                    t.modeReseau = String(d.mode_reseau || "hors_ligne")
                    t.relais = String(d.relais || "")
                    t.ip = String(d.ip || "198.51.100.10")
                    t.profil = String(d.profil || "equilibre")
                    if (Array.isArray(d.profils) && d.profils.length > 0) t.profils = d.profils
                    t.cpuPct = typeof d.cpu_pct === "number" ? d.cpu_pct : -1
                    t.cpuTemp = typeof d.cpu_temp === "number" ? d.cpu_temp : -1
                    t.ramUtiliseeGo = typeof d.ram_utilisee_go === "number" ? d.ram_utilisee_go : -1
                    t.ramTotaleGo = typeof d.ram_totale_go === "number" ? d.ram_totale_go : 31
                    t.gpuPct = typeof d.gpu_pct === "number" ? d.gpu_pct : -1
                    t.gpuTemp = typeof d.gpu_temp === "number" ? d.gpu_temp : -1
                    t.vramUtiliseeGo = typeof d.vram_utilisee_go === "number" ? d.vram_utilisee_go : -1
                    t.vramTotaleGo = typeof d.vram_totale_go === "number" ? d.vram_totale_go : 16
                    t.sunshineActif = Boolean(d.sunshine_actif)
                    t.ecranVirtuel = Boolean(d.ecran_virtuel)
                    t.ollamaActif = Boolean(d.ollama_actif)
                    t.ollamaModeles = Array.isArray(d.ollama_modeles) ? d.ollama_modeles : []
                    t.lu = true
                } catch (e) {}
            }
        }
    }

    Process {
        id: actionProc
        stdout: StdioCollector {
            onStreamFinished: {
                t.occupe = false
                try {
                    var d = JSON.parse(text)
                    t.message = String(d.message || "")
                    t.erreur = !d.ok
                    if (d.profil) t.profil = String(d.profil)
                    if (typeof d.ia_tour === "boolean") t.iaTour = d.ia_tour
                } catch (e) {}
                t.rafraichir()
            }
        }
        onExited: t.occupe = false
    }

    function lancer(args) {
        if (actionProc.running) return
        t.occupe = true
        t.message = ""
        t.erreur = false
        actionProc.command = [t.bin].concat(args).concat(["--json"])
        actionProc.running = true
    }

    function actionRapide() { lancer(["action-rapide"]) }
    function reveiller() { lancer(["reveiller"]) }
    function mettreEnVeille() { lancer(["veille"]) }
    function redemarrer() { lancer(["redemarrer"]) }
    function eteindre() { lancer(["eteindre"]) }
    function lancerStream(app, modeEcran) { lancer(["stream", app, "--ecran", modeEcran || "principal", "--profil", t.profil]) }
    function couperStream() { lancer(["couper-stream"]) }
    function choisirProfil(id) { lancer(["profil", id]) }
    function basculerIA() { lancer(["ia", "basculer"]) }
    function ouvrirSsh() { Quickshell.execDetached([t.bin, "ssh"]) }
    function ouvrirCode() { Quickshell.execDetached([t.bin, "code"]) }
    function ouvrirMoonlight() { Quickshell.execDetached([t.bin, "moonlight"]) }
}
