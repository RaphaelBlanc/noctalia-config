pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: cloud
    signal ouvrirPanneau()
    signal basculerPanneau()
    readonly property string bin: Quickshell.env("HOME") + "/.local/bin/nc-cloud"
    readonly property bool active: Reglages.val("CLOUD_JARVIS", "non") === "oui"
    property bool visible: false
    property bool enLigne: false
    property bool attenteReponse: false
    readonly property bool occupe: attenteReponse || commande.running
    property bool panneauOuvert: false
    property string message: ""
    property var statut: ({})
    property var dossier: ({ id: "root", revision: "", name: "Cloud JARVIS" })
    property var dossiers: []
    property var chemin: []
    property var fichiers: []
    property var transferts: []
    property string suite: ""
    property var attente: []
    property var courant: ({})
    property var selection: null
    property string action: ""
    property var suppression: null
    property var destination: ({ id: "root", name: "Cloud JARVIS", revision: "" })
    property var destinations: []
    property var destinationChemin: []
    property string destinationSuite: ""

    function demander(body) {
        attente = attente.concat([body])
        executer()
    }
    function executer() {
        if (attenteReponse || commande.running || attente.length === 0) return
        courant = attente[0]; attente = attente.slice(1)
        attenteReponse = true
        commande.stdinEnabled = true
        commande.running = true
    }
    function relire() { demander({ op: "etat" }) }
    function etatTexte(state) {
        var noms = { preparing: ["Préparation", "Preparing"], ready: ["Prêt", "Ready"], uploading: ["Envoi", "Uploading"],
                     verifying: ["Vérification", "Verifying"], committed: ["Enregistré", "Saved"], interrupted: ["Interrompu", "Interrupted"],
                     conflict: ["Conflit", "Conflict"], cancelled: ["Annulé", "Cancelled"], expired: ["Expiré", "Expired"] }
        var nom = noms[state] || [state, state]
        return Reglages.t(nom[0], nom[1])
    }
    function afficherDansBarre() { reglage.running = true }
    function lister(id, cursor) { demander({ op: "lister", parent_id: id || "root", cursor: cursor || "" }) }
    function entrer(entry) {
        selection = null; action = ""
        chemin = chemin.concat([dossier]); lister(entry.id)
    }
    function remonter() {
        if (chemin.length === 0) return
        var parent = chemin[chemin.length - 1]
        selection = null; action = ""
        chemin = chemin.slice(0, -1); lister(parent.id)
    }
    function choisir(entry) { selection = entry; action = ""; suppression = null }
    function ouvrirFichier(entry) { demander({ op: "ouvrir_fichier", id: entry.id, revision: entry.revision }) }
    function preparerSuppression() {
        if (selection) demander({ op: "preparer_suppression", id: selection.id })
    }
    function confirmerSuppression() {
        if (!suppression) return
        demander({ op: "supprimer", id: suppression.entry.id, revision: suppression.entry.revision,
                    recursive: suppression.entry.kind === "directory", tree_revision: suppression.tree_revision })
    }
    function choisirDestination(id, cursor) { demander({ op: "lister_destination", parent_id: id || "root", cursor: cursor || "" }) }
    function preparerDeplacement() {
        if (!selection) return
        action = "deplacer"; destinationChemin = []; destinations = []; destinationSuite = ""
        choisirDestination("root")
    }
    function entrerDestination(entry) { destinationChemin = destinationChemin.concat([destination]); choisirDestination(entry.id) }
    function remonterDestination() {
        if (!destinationChemin.length) return
        var parent = destinationChemin[destinationChemin.length - 1]
        destinationChemin = destinationChemin.slice(0, -1); choisirDestination(parent.id)
    }
    function deplacer(parent, nom) {
        if (!selection) return
        demander({ op: "deplacer", id: selection.id, revision: selection.revision,
                    parent_id: parent.id, parent_revision: parent.revision, name: nom || selection.name })
    }
    function deplacerEntree(entry, parent) {
        if (!enLigne || occupe || !entry || !parent || entry.id === parent.id || parent.id === dossier.id) return false
        demander({ op: "deplacer", id: entry.id, revision: entry.revision,
                    parent_id: parent.id, parent_revision: parent.revision, name: entry.name })
        return true
    }
    function deposer(urls) {
        message = ""
        if (!enLigne) {
            message = Reglages.t("Cloud hors ligne. Aucun fichier envoyé. Réessaie après reconnexion.", "Cloud offline. No file uploaded. Try again after reconnecting.")
        } else if (urls.length > 8) {
            message = Reglages.t("Dépose au plus 8 fichiers à la fois.", "Drop at most 8 files at once.")
        } else {
            fichiers = urls
        }
        ouvrirPanneau()
    }
    function envoyer() {
        if (!enLigne || !fichiers.length) return
        demander({ op: "envoyer", files: fichiers, parent_id: dossier.id, parent_revision: dossier.revision })
        fichiers = []
    }
    function reponse(result) {
        if (courant.op === "etat" || courant.op === "associer") {
            if (result.server_id && statut.server_id !== result.server_id) {
                chemin = []; dossiers = []; fichiers = []
                dossier = { id: "root", revision: "", name: "Cloud JARVIS" }
            }
            statut = result
            enLigne = result.state === "ready"
            visible = active && result.enabled !== false && (result.configured === true || enLigne)
            if (enLigne) {
                message = ""
                if (!dossier.revision) lister("root")
            } else {
                fichiers = []; dossiers = []; chemin = []
                dossier = { id: "root", revision: "", name: "Cloud JARVIS" }
                message = result.message || Reglages.t("Cloud indisponible", "Cloud unavailable")
            }
        } else if (courant.op === "lister" && result.entries) {
            dossier = result.parent
            dossiers = courant.cursor ? dossiers.concat(result.entries) : result.entries
            suite = result.next_cursor || ""
            if (selection) selection = dossiers.find(e => e.id === selection.id) || null
            // Moving an item up changes that parent's revision. Keep the next
            // drag's precondition current without leaving and re-entering here.
            if (chemin.length) demander({ op: "lire_parent", id: chemin[chemin.length - 1].id })
        } else if (courant.op === "lire_parent" && result.entry) {
            chemin = chemin.map(p => p.id === result.entry.id ? result.entry : p)
        } else if (courant.op === "lister_destination" && result.entries) {
            destination = result.parent
            destinations = courant.cursor ? destinations.concat(result.entries) : result.entries
            destinationSuite = result.next_cursor || ""
        } else if (courant.op === "preparer_suppression" && result.entry) {
            suppression = result; selection = result.entry; action = "supprimer"
        } else if (["supprimer", "deplacer", "creer_fichier"].indexOf(courant.op) >= 0 && !result.error && result.ok !== false) {
            selection = null; action = ""; suppression = null; message = ""
            lister(dossier.id); relire()
        } else if (courant.op === "ouvrir_fichier" && result.opened) {
            message = Reglages.t("Copie locale ouverte. Pour publier une modification, dépose à nouveau le fichier.", "Local copy opened. Upload the file again to publish changes.")
        } else if (courant.op === "transferts" || courant.op === "effacer_transferts") {
            var suivants = result.transfers || []
            // Workers commit asynchronously, including while this window is closed.
            // Refresh once for newly observed commits, even if the first poll
            // happens after a short upload has already finished.
            var nouveaux = suivants.some(t => t.state === "committed"
                && !transferts.some(ancien => ancien.id === t.id && ancien.state === "committed"))
            transferts = suivants
            // Clearing may remove a just-finished receipt before its first poll.
            var nettoyage = courant.op === "effacer_transferts" && result.removed > 0
            if ((nouveaux || nettoyage) && enLigne) { lister(dossier.id); relire() }
        } else if (["reprise", "resoudre", "annuler"].indexOf(courant.op) >= 0 && !result.error) {
            demander({ op: "transferts" })
        } else if (courant.op === "dossier") {
            if (result.entry) lister(dossier.id)
        } else if (courant.op === "envoyer") {
            var errors = (result.results || []).filter(r => !r.ok)
            message = errors.map(r => r.message).join("\n")
            demander({ op: "transferts" })
        }
        if (result.ok === false || result.error) {
            message = result.message || result.error || Reglages.t("Erreur cloud", "Cloud error")
            if (["cloud_unavailable", "cloud_disabled", "device_revoked", "server_changed"].indexOf(result.error) >= 0) enLigne = false
        }
    }
    Process {
        id: commande
        command: [cloud.bin, "requete"]
        stdinEnabled: true
        onStarted: { write(JSON.stringify(cloud.courant)); stdinEnabled = false }
        stdout: StdioCollector {
            onStreamFinished: {
                try { cloud.reponse(JSON.parse(text)) }
                catch (e) { cloud.message = Reglages.t("Réponse cloud illisible", "Invalid cloud response") }
            }
        }
        onExited: Qt.callLater(() => { cloud.attenteReponse = false; cloud.executer() })
    }
    Process {
        id: reglage
        command: [Quickshell.env("HOME") + "/.local/bin/nc-reglages", "set", "CLOUD_JARVIS", "oui"]
    }
    Process {
        command: ["nmcli", "monitor"]
        running: cloud.active && cloud.visible && Etat.ecranVu
        stdout: SplitParser { onRead: reseau.restart() }
    }
    Timer { id: reseau; interval: 600; onTriggered: cloud.relire() }
    // No network loop: configured users refresh on wake, connection changes, or an explicit action.
    FileView {
        path: Quickshell.env("HOME") + "/.config/nc/assistant.conf"
        watchChanges: cloud.active
        onFileChanged: { reload(); if (cloud.active) cloud.relire() }
    }
    Connections { target: Etat; function onEcranVuChanged() { if (cloud.active && Etat.ecranVu) cloud.relire() } }
    onActiveChanged: { if (active) relire(); else { visible = false; enLigne = false; fichiers = [] } }
    Component.onCompleted: if (active) relire()
    Timer {
        interval: 1000; repeat: true
        running: cloud.panneauOuvert && Etat.ecranVu && !cloud.occupe
                 && cloud.transferts.some(t => ["ready", "preparing", "uploading", "verifying"].indexOf(t.state) >= 0)
        onTriggered: cloud.demander({ op: "transferts" })
    }
}
