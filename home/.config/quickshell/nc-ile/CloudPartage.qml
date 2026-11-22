import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import Quickshell
import Quickshell.Io

CloudCarte {
    id: carte
    objectName: "cloudPartage"
    property bool ouvert: false
    property bool pret: false
    property bool occupe: false
    property bool details: false
    property bool recherche: false
    property bool lien: false
    property string mode: "ip"
    property var fichiers: []
    property var appareils: []
    property var pairs: []
    property bool pairsCharges: false
    property var radios: []
    property var bluetooth: ({})
    property var ecoutes: ({})
    property var adresses: []
    property string adresseBt: ""
    property string dossier: ""
    property string machine: ""
    property string message: ""
    property string question: ""
    property string ticket: ""
    property string ident: ""

    function ouvrir(selection) {
        ouvert = true
        if (!occupe) {
            if (selection.mode) changer(selection.mode)
            if (selection.files && selection.files.length) fichiers = selection.files
        }
        if (!service.running) service.running = true
    }
    function changer(valeur) {
        if (mode !== valeur) { mode = valeur; adresse.clear(); ident = "" }
    }
    function demander(obj) { if (pret) service.write(JSON.stringify(obj) + "\n") }
    function choisir(host, id) { adresse.text = host; ident = id || "" }
    function evenement(e) {
        if ("ready" in e) { pret = true; machine = e.name; dossier = e.folder }
        if ("message" in e) message = e.message
        if ("paired" in e) { pairs = e.paired; pairsCharges = true }
        if ("devices" in e) appareils = e.devices
        if ("addresses" in e) adresses = e.addresses
        if ("btAddress" in e) adresseBt = e.btAddress
        if ("bluetooth" in e) bluetooth = e.bluetooth
        if ("listener" in e) ecoutes = Object.assign({}, ecoutes, { [e.listener]: e.state })
        if ("radios" in e) radios = e.radios
        if ("scanning" in e) recherche = e.scanning
        if ("link" in e) lien = e.link
        if ("busy" in e) occupe = e.busy
        if ("sent" in e) fichiers = []
        if ("question" in e) { ticket = e.ticket; question = e.question }
    }
    Process {
        id: service
        command: ["python3", "-u", Quickshell.env("HOME") + "/.local/share/nc-partage/panneau.py"]
        stdinEnabled: true
        stdout: SplitParser { onRead: ligne => carte.evenement(JSON.parse(ligne)) }
        stderr: SplitParser { onRead: ligne => carte.message = ligne }
        onExited: { carte.pret = false; carte.pairsCharges = false; carte.pairs = []; carte.occupe = false; carte.question = ""; carte.lien = false; carte.message = "Service de partage interrompu. " + carte.message }
    }
    FileDialog {
        id: choix
        title: Reglages.t("Fichiers à envoyer", "Files to send")
        fileMode: FileDialog.OpenFiles
        onAccepted: carte.fichiers = Array.from(selectedFiles, f => String(f))
    }
    Row {
        spacing: 10
        Rectangle {
            width: 40; height: 40; radius: 13; color: Qt.alpha(Couleurs.accent, 0.16)
            Ico { anchors.centerIn: parent; nom: "devices"; taille: 22; color: Couleurs.accent }
        }
        Texte { height: 40; text: Reglages.t("Partage entre appareils", "Device sharing"); font.pixelSize: 19; font.weight: Font.DemiBold }
    }
    Column {
        visible: carte.ouvert; width: parent.width; spacing: 10
        Flow {
            width: parent.width; spacing: 6; enabled: !carte.occupe && !carte.recherche
            Repeater {
                model: [{key:"ip", name:Reglages.t("Réseau IP", "IP network")}, {key:"direct", name:"Wi-Fi Direct"}, {key:"bt", name:"Bluetooth"}]
                CloudBouton { required property var modelData; texte: modelData.name; primaire: carte.mode === modelData.key; onClic: carte.changer(modelData.key) }
            }
        }
        Texte {
            width: parent.width; wrapMode: Text.Wrap
            text: carte.mode === "direct" ? "À proximité, lance la recherche sur les deux PC, puis sélectionne l’autre sur chaque écran pour établir la liaison."
                : carte.mode === "bt" ? "Active le Bluetooth et rends l’autre PC visible pour le rechercher, ou saisis son adresse Bluetooth."
                : "Sur le même réseau, choisis un appareil détecté. À distance, saisis son adresse IP joignable, par exemple via ton VPN."
        }
        Rectangle { width: parent.width; height: 1; color: Qt.alpha(Couleurs.texte, 0.08) }
        Texte { text: Reglages.t("Destinataire", "Recipient"); font.weight: Font.DemiBold; font.pixelSize: 15 }
        Flow {
            width: parent.width; spacing: 6
            CloudBouton {
                visible: carte.mode !== "ip"
                texte: carte.recherche ? "Recherche en cours…" : "Rechercher à proximité"
                enabled: carte.pret && !carte.occupe && !carte.recherche
                onClic: { carte.message = ""; carte.demander({op:"scan", mode:carte.mode}) }
            }
            CloudBouton { visible: carte.lien; enabled: !carte.occupe; texte: "Couper le Wi-Fi Direct"; onClic: carte.demander({op:"disconnect"}) }
        }
        Texte {
            visible: carte.mode === "direct" && !carte.lien && !carte.radios.length
            width: parent.width; wrapMode: Text.Wrap; secondaire: true
            text: carte.recherche ? "Recherche des PC à portée…" : "Aucun pair Wi-Fi Direct détecté. Ouvre la recherche sur les deux appareils."
        }
        Flow {
            visible: carte.mode === "direct" && !carte.lien; width: parent.width; spacing: 6
            Repeater {
                model: carte.radios
                CloudBouton {
                    required property var modelData
                    texte: "Relier · " + modelData.name; enabled: !carte.occupe
                    onClic: carte.demander({op:"connect", mac:modelData.mac, adapter:modelData.adapter})
                }
            }
        }
        Flow {
            visible: carte.mode === "bt"; width: parent.width; spacing: 6
            Repeater {
                model: Object.keys(carte.bluetooth)
                CloudBouton { required property string modelData; texte: carte.bluetooth[modelData]; enabled: !carte.occupe; onClic: carte.choisir(modelData, "") }
            }
        }
        Flow {
            width: parent.width; spacing: 6
            Repeater {
                model: carte.appareils.filter(d => carte.mode === "bt" ? d.bt : (!d.bt && (carte.mode !== "direct" || d.host.startsWith("169.254."))))
                CloudBouton {
                    required property var modelData
                    texte: modelData.name + (modelData.paired ? " · appairé" : " · détecté")
                    primaire: adresse.text === modelData.host; enabled: !carte.occupe
                    onClic: carte.choisir(modelData.host, modelData.id)
                }
            }
        }
        TextField {
            id: adresse; width: parent.width; height: 38
            font.family: "Adwaita Sans"; font.pixelSize: 13
            leftPadding: 12; rightPadding: 12; verticalAlignment: TextInput.AlignVCenter
            enabled: !carte.occupe
            placeholderText: carte.mode === "bt" ? "Adresse Bluetooth de l’autre PC" : "Adresse IP de l’autre PC"
            color: Couleurs.texte; placeholderTextColor: Couleurs.texteSec; selectByMouse: true
            onTextEdited: carte.ident = ""
            background: Rectangle { radius: 12; color: Qt.alpha(Couleurs.fond, 0.5); border.color: adresse.activeFocus ? Couleurs.accent : Qt.alpha(Couleurs.texte, 0.12) }
        }
        Flow {
            width: parent.width; spacing: 6; enabled: carte.pret && !carte.occupe
            CloudBouton { texte: "Appairer un appareil"; enabled: (carte.mode !== "direct" || carte.lien) && adresse.text.trim() !== ""; onClic: carte.demander({op:"pair", mode:carte.mode, host:adresse.text, id:carte.ident}) }
            CloudBouton { texte: "Choisir les fichiers…"; onClic: choix.open() }
            CloudBouton { texte: "Envoyer"; primaire: true; enabled: (carte.mode !== "direct" || carte.lien) && adresse.text.trim() !== "" && carte.fichiers.length > 0; onClic: carte.demander({op:"send", mode:carte.mode, host:adresse.text, id:carte.ident, files:carte.fichiers}) }
            CloudBouton { texte: "Oublier"; visible: carte.appareils.some(d => d.id === carte.ident && d.paired); onClic: carte.demander({op:"forget", id:carte.ident}) }
        }
        Texte { width: parent.width; wrapMode: Text.Wrap; visible: carte.fichiers.length > 0; text: carte.fichiers.map(f => { const nom = String(f).split("/").pop(); try { return decodeURIComponent(nom) } catch (e) { return nom } }).join(" · ") }
        Texte { width: parent.width; wrapMode: Text.Wrap; visible: carte.message !== ""; text: carte.message; color: Couleurs.accent }
        Texte { width: parent.width; wrapMode: Text.Wrap; visible: !!carte.question; text: carte.question; font.weight: Font.DemiBold }
        Row {
            visible: !!carte.question; spacing: 8
            CloudBouton { texte: "Refuser"; onClic: carte.demander({op:"answer", ticket:carte.ticket, accept:false}) }
            CloudBouton { texte: "Confirmer"; primaire: true; onClic: carte.demander({op:"answer", ticket:carte.ticket, accept:true}) }
        }
        Rectangle { width: parent.width; height: 1; color: Qt.alpha(Couleurs.texte, 0.08) }
        Flow {
            width: parent.width; spacing: 8
            CloudBouton {
                icone: "info"; texte: Reglages.t("Détails de connexion", "Connection details"); primaire: carte.details
                onClic: {
                    carte.details = !carte.details
                    if (carte.details && carte.mode !== "bt") carte.demander({op:"scan", mode:"ip"})
                }
            }
            CloudBouton { visible: !service.running; texte: Reglages.t("Relancer le partage", "Restart sharing"); onClic: carte.ouvrir({}) }
        }
        Column {
            visible: carte.details; width: parent.width; spacing: 6
            Repeater {
                model: carte.mode === "bt" ? (carte.adresseBt ? [carte.adresseBt] : []) : carte.adresses
                TextInput {
                    required property string modelData
                    width: parent.width; readOnly: true; selectByMouse: true; clip: true
                    color: Couleurs.texte; font.pixelSize: 13
                    text: (carte.mode === "bt" ? "Bluetooth" : modelData.includes(":") ? "IPv6" : "IPv4") + "   " + modelData
                }
            }
            Texte {
                width: parent.width; wrapMode: Text.Wrap; secondaire: true
                text: carte.mode === "bt" ? "Bluetooth · " + (carte.ecoutes.bluetooth || "…") : "IPv4 · " + (carte.ecoutes.ipv4 || "…") + "     IPv6 · " + (carte.ecoutes.ipv6 || "…")
            }
            Texte { width: parent.width; wrapMode: Text.Wrap; secondaire: true; text: Reglages.t("Réception dans ", "Receive in ") + carte.dossier }
        }
        Texte { width: parent.width; wrapMode: Text.Wrap; secondaire: true; text: Reglages.t("Ouvre le partage sur les deux appareils. Chaque fichier reçu demande ton accord.", "Open sharing on both devices. Each incoming file needs your approval.") }
    }
}
