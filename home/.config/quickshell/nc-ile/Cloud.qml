// Prototype local : fenêtre de verre et cartes communes au style VPN / Tour / Garmin.
import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import Quickshell

FloatingWindow {
    id: fen
    signal fermer()
    title: partageLocal.ouvert ? "Cloud JARVIS · Partage de proximité" : "Cloud JARVIS"
    color: "transparent"
    implicitWidth: Math.min(900, Math.round((screen ? screen.width : 1600) * 0.92))
    implicitHeight: Math.min(780, Math.round((screen ? screen.height : 1000) * 0.9))
    minimumSize: Qt.size(420, 260)
    onClosed: fen.fermer()
    readonly property bool verre: Reglages.val("FENETRES_FLOU", "oui") !== "non" && !Reglages.sobre
    readonly property real utilise: Number(CloudEtat.statut.used_bytes || 0)
    readonly property real reserve: Number(CloudEtat.statut.reserved_bytes || 0)
    readonly property real quota: Number(CloudEtat.statut.quota_bytes || 0)
    readonly property real occupation: quota > 0 ? Math.min(1, (utilise + reserve) / quota) : 0
    property bool nouveauDossier: false

    FileDialog {
        id: importation
        objectName: "cloudImportation"
        title: Reglages.t("Importer des fichiers dans Cloud JARVIS", "Import files into Cloud JARVIS")
        fileMode: FileDialog.OpenFiles
        onAccepted: {
            var urls = []
            for (let i = 0; i < selectedFiles.length; ++i) urls.push(String(selectedFiles[i]))
            if (urls.length) CloudEtat.deposer(urls)
        }
    }

    function ouvrirPartage(selection) {
        partageLocal.ouvrir(selection)
        defilePartage.contentY = 0
    }

    function taille(octets) {
        var unites = Reglages.en ? ["B", "KiB", "MiB", "GiB", "TiB"] : ["o", "Kio", "Mio", "Gio", "Tio"]
        var valeur = Math.max(0, Number(octets) || 0), i = 0
        while (valeur >= 1024 && i < unites.length - 1) { valeur /= 1024; i++ }
        return (i === 0 ? Math.round(valeur) : valeur.toLocaleString(Qt.locale(), "f", 1)) + " " + unites[i]
    }
    function nomFichier(url) {
        var nom = String(url).split("/").pop()
        try { return decodeURIComponent(nom) } catch (e) { return nom }
    }
    function progression(t) {
        return t.state === "committed" ? 1 : Math.max(0, Math.min(1, Number(t.sent || 0) / Math.max(1, Number(t.size || 0))))
    }
    function actualiser() {
        CloudEtat.relire()
        if (CloudEtat.enLigne) CloudEtat.lister(CloudEtat.dossier.id)
        CloudEtat.demander({ op: "transferts" })
    }
    function creerDossier() {
        if (!CloudEtat.enLigne || CloudEtat.occupe || !nomDossier.text.trim()) return
        CloudEtat.demander({ op: "dossier", parent_id: CloudEtat.dossier.id,
                              parent_revision: CloudEtat.dossier.revision, name: nomDossier.text })
        nomDossier.text = ""; nouveauDossier = false
    }
    Component.onCompleted: { CloudEtat.panneauOuvert = true; actualiser() }
    Component.onDestruction: CloudEtat.panneauOuvert = false

    Item {
        id: surface
        anchors.fill: parent; focus: true
        Keys.onEscapePressed: fen.fermer()
        Item { id: coucheGlisser; anchors.fill: parent; z: 100 }
        Rectangle { anchors.fill: parent; color: Qt.alpha(Couleurs.fond, fen.verre ? 0.62 : 0.92) }
        readonly property bool coteACote: partageLocal.ouvert && (fen.screen ? fen.screen.width : width) >= 920
        Row {
            id: entete
            x: 22; y: 16; spacing: 10
            Rectangle {
                width: 42; height: 42; radius: 14; color: Qt.alpha(Couleurs.accent, 0.16)
                Ico { anchors.centerIn: parent; nom: "cloud"; taille: 25; color: Couleurs.accent }
            }
            Texte { height: 42; text: "Cloud JARVIS"; font.pixelSize: 22; font.weight: Font.Bold }
        }
        Row {
            id: commandes
            anchors.right: parent.right; anchors.rightMargin: 22
            y: surface.width < 550 ? 68 : 20; spacing: 8
            CloudBouton {
                objectName: "cloudOuvrirPartage"; icone: "devices"; primaire: partageLocal.ouvert
                texte: partageLocal.question && !partageLocal.ouvert ? Reglages.t("Demande de partage", "Sharing request") : Reglages.t("Partage de proximité", "Nearby sharing")
                onClic: { if (partageLocal.ouvert) partageLocal.ouvert = false; else fen.ouvrirPartage({}) }
            }
            CloudBouton { texte: Reglages.t("Fermer", "Close"); onClic: fen.fermer() }
        }
        readonly property real debut: Math.max(entete.y + entete.height, commandes.y + commandes.height) + 4
        Flickable {
            id: defile
            visible: !partageLocal.ouvert || surface.coteACote
            y: surface.debut; height: parent.height - y
            width: surface.coteACote ? Math.round(parent.width * 0.53) : parent.width
            contentWidth: width; contentHeight: contenu.implicitHeight + 48
            clip: true; boundsBehavior: Flickable.StopAtBounds; flickableDirection: Flickable.VerticalFlick
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
            Column {
                id: contenu
                x: 26; y: 24; width: defile.width - 52; spacing: 14
                CloudCarte {
                    width: parent.width
                    Flow {
                        width: parent.width; spacing: 12
                        Row {
                            width: Math.max(180, parent.width - actionsEtat.width - 12); height: 42; spacing: 10
                            Rectangle { width: 10; height: 10; radius: 5; anchors.verticalCenter: parent.verticalCenter; color: CloudEtat.enLigne ? Couleurs.vert : Couleurs.orange }
                            Column {
                                anchors.verticalCenter: parent.verticalCenter; spacing: 3
                                Texte { text: CloudEtat.enLigne ? Reglages.t("Connecté à ton serveur", "Connected to your server") : Reglages.t("Cloud indisponible", "Cloud unavailable"); font.pixelSize: 17; font.weight: Font.DemiBold }
                                Texte { text: CloudEtat.occupe ? Reglages.t("Actualisation…", "Refreshing…") : (CloudEtat.enLigne ? Reglages.t("Un espace pour tous tes PC associés", "One space for all your paired PCs") : Reglages.t("Vérifie ta connexion ou associe ce PC", "Check your connection or pair this PC")); secondaire: true; font.pixelSize: 12 }
                            }
                        }
                        Row {
                            id: actionsEtat; height: 42; spacing: 8
                            CloudBouton { anchors.verticalCenter: parent.verticalCenter; icone: "refresh"; texte: Reglages.t("Actualiser", "Refresh"); enabled: !CloudEtat.occupe; onClic: fen.actualiser() }
                            CloudBouton { anchors.verticalCenter: parent.verticalCenter; visible: !CloudEtat.statut.associated; texte: Reglages.t("Associer ce PC", "Pair this PC"); enabled: !CloudEtat.occupe; onClic: CloudEtat.demander({ op: "associer" }) }
                        }
                    }
                    Rectangle { width: parent.width; height: 1; color: Qt.alpha(Couleurs.texte, 0.07) }
                    Row {
                        width: parent.width
                        Texte { width: parent.width * 0.55; text: Reglages.t("Stockage utilisé", "Storage used"); secondaire: true; font.pixelSize: 12 }
                        Texte { width: parent.width * 0.45; horizontalAlignment: Text.AlignRight; text: CloudEtat.enLigne ? fen.taille(fen.utilise) + " / " + fen.taille(fen.quota) : "—"; font.pixelSize: 12; font.weight: Font.DemiBold }
                    }
                    Rectangle {
                        width: parent.width; height: 6; radius: 3; color: Qt.alpha(Couleurs.texte, 0.08)
                        Rectangle { width: parent.width * fen.occupation; height: parent.height; radius: 3; color: fen.occupation > 0.9 ? Couleurs.orange : Couleurs.accent }
                    }
                    Flow {
                        width: parent.width; spacing: 8
                        CloudBouton { icone: "folder_open"; texte: Reglages.t("Ouvrir dans Fichiers", "Open in Files"); enabled: CloudEtat.enLigne && !CloudEtat.occupe; onClic: CloudEtat.demander({ op: "ouvrir" }) }
                        CloudBouton { visible: !CloudEtat.active; icone: "cloud"; texte: Reglages.t("Afficher dans la barre", "Show in the bar"); onClic: CloudEtat.afficherDansBarre() }
                        Texte { width: Math.min(implicitWidth, parent.width); height: Math.max(34, implicitHeight); wrapMode: Text.Wrap; text: fen.reserve > 0 ? fen.taille(fen.reserve) + Reglages.t(" réservés", " reserved") : (CloudEtat.statut.webdav === "read_write" ? Reglages.t("Fichiers : créer, déplacer et supprimer", "Files: create, move and delete") : Reglages.t("Fichiers : consultation et téléchargement", "Files: browse and download")); secondaire: true; font.pixelSize: 11 }
                    }
                }
                Rectangle {
                    visible: CloudEtat.message !== ""
                    width: parent.width; height: message.implicitHeight + 26; radius: 16
                    color: Qt.alpha(Couleurs.orange, 0.1); border.width: 1; border.color: Qt.alpha(Couleurs.orange, 0.2)
                    Texte { id: message; x: 14; y: 13; width: parent.width - 28; text: CloudEtat.message; wrapMode: Text.Wrap; color: Couleurs.orange }
                }
                CloudActions { width: parent.width }
                Flow {
                    id: zones
                    width: parent.width; spacing: 14
                    readonly property bool large: width >= 700
                    CloudCarte {
                        width: zones.large ? Math.round((zones.width - 14) * 0.55) : zones.width
                        Item {
                            width: parent.width; height: 34
                            Texte { anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; text: Reglages.t("Mes fichiers", "My files"); font.pixelSize: 17; font.weight: Font.DemiBold }
                            Row {
                                anchors.right: parent.right; spacing: 6
                                CloudBouton { icone: "note_add"; texte: Reglages.t("Fichier", "File"); enabled: CloudEtat.enLigne && !CloudEtat.occupe; onClic: { CloudEtat.selection = null; CloudEtat.action = "creer_fichier" } }
                                CloudBouton { icone: "create_new_folder"; texte: Reglages.t("Dossier", "Folder"); enabled: CloudEtat.enLigne && !CloudEtat.occupe; onClic: { fen.nouveauDossier = !fen.nouveauDossier; if (fen.nouveauDossier) nomDossier.forceActiveFocus() } }
                            }
                        }
                        Rectangle {
                            width: parent.width; height: 38; radius: 12; color: Qt.alpha(Couleurs.texte, 0.04)
                            CloudBouton {
                                objectName: "cloudParent"
                                x: 3; y: 3; width: 34; height: 32; icone: "arrow_upward"
                                enabled: CloudEtat.chemin.length > 0 && !CloudEtat.occupe
                                border.color: depotParent.containsDrag ? Couleurs.accent : Qt.alpha(Couleurs.texte, 0.1)
                                onClic: CloudEtat.remonter()
                                CloudCibleDepot {
                                    id: depotParent; anchors.fill: parent
                                    destination: CloudEtat.chemin.length ? CloudEtat.chemin[CloudEtat.chemin.length - 1] : null
                                }
                            }
                            Texte { x: 46; width: parent.width - 58; height: parent.height; font.pixelSize: 12; elide: Text.ElideMiddle; text: "/" + CloudEtat.chemin.concat([CloudEtat.dossier]).filter(p => p.id !== "root").map(p => p.name || "").filter(p => p !== "").join("/") }
                        }
                        Row {
                            visible: fen.nouveauDossier; width: parent.width; spacing: 8
                            TextField {
                                id: nomDossier
                                width: parent.width - creer.width - 8; height: 36; enabled: CloudEtat.enLigne && !CloudEtat.occupe
                                color: Couleurs.texte; font.family: "Adwaita Sans"; font.pixelSize: 12
                                placeholderText: Reglages.t("Nom du dossier", "Folder name"); placeholderTextColor: Couleurs.texteSec
                                leftPadding: 12; rightPadding: 12; selectByMouse: true
                                background: Rectangle { radius: 12; color: Qt.alpha(Couleurs.fond, 0.5); border.width: 1; border.color: nomDossier.activeFocus ? Couleurs.accent : Qt.alpha(Couleurs.texte, 0.1) }
                                onAccepted: fen.creerDossier()
                            }
                            CloudBouton { id: creer; height: 36; texte: Reglages.t("Créer", "Create"); enabled: CloudEtat.enLigne && !CloudEtat.occupe && nomDossier.text.trim() !== ""; onClic: fen.creerDossier() }
                        }
                        Column {
                            visible: CloudEtat.dossiers.length === 0; width: parent.width; spacing: 10
                            Ico { anchors.horizontalCenter: parent.horizontalCenter; nom: "folder_open"; taille: 34; color: Qt.alpha(Couleurs.texteSec, 0.65) }
                            Texte { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: CloudEtat.enLigne ? Reglages.t("Ce dossier est vide", "This folder is empty") : Reglages.t("Tes fichiers apparaîtront ici", "Your files will appear here"); secondaire: true; wrapMode: Text.Wrap; font.pixelSize: 12 }
                        }
                        Column {
                            width: parent.width; spacing: 4
                            Repeater {
                                model: CloudEtat.dossiers
                                delegate: Rectangle {
                                    id: entree
                                    required property var modelData
                                    objectName: "cloudEntree-" + modelData.id
                                    width: parent.width; height: 48; radius: 12
                                    color: depotDossier.containsDrag ? Qt.alpha(Couleurs.accent, 0.32) : (CloudEtat.selection && CloudEtat.selection.id === modelData.id ? Qt.alpha(Couleurs.accent, 0.22) : (sourisEntree.containsMouse ? Qt.alpha(Couleurs.accent, 0.10) : "transparent"))
                                    border.width: depotDossier.containsDrag ? 1 : 0
                                    border.color: Couleurs.accent
                                    Rectangle {
                                        x: 6; anchors.verticalCenter: parent.verticalCenter; width: 34; height: 34; radius: 10
                                        color: Qt.alpha(entree.modelData.kind === "directory" ? Couleurs.accent : Couleurs.texte, 0.08)
                                        Ico { anchors.centerIn: parent; nom: entree.modelData.kind === "directory" ? "folder" : "description"; taille: 19; color: entree.modelData.kind === "directory" ? Couleurs.accent : Couleurs.texteSec }
                                    }
                                    Column {
                                        x: 50; width: parent.width - 76; anchors.verticalCenter: parent.verticalCenter; spacing: 3
                                        Texte { width: parent.width; text: entree.modelData.name; font.pixelSize: 12; font.weight: Font.DemiBold }
                                        Texte { width: parent.width; text: entree.modelData.kind === "directory" ? Reglages.t("Ouvrir le dossier", "Open folder") : fen.taille(entree.modelData.size); secondaire: true; font.pixelSize: 10 }
                                    }
                                    Ico { visible: entree.modelData.kind === "directory"; anchors.right: parent.right; anchors.rightMargin: 6; anchors.verticalCenter: parent.verticalCenter; nom: "chevron_right"; taille: 18; color: Couleurs.texteSec }
                                    MouseArea {
                                        id: sourisEntree; anchors.fill: parent; hoverEnabled: true; enabled: !CloudEtat.occupe
                                        cursorShape: drag.active ? Qt.ClosedHandCursor : Qt.PointingHandCursor
                                        drag.target: apercuGlisser
                                        drag.axis: Drag.XAndYAxis
                                        drag.smoothed: false
                                        onPressed: mouse => {
                                            var point = mapToItem(coucheGlisser, mouse.x, mouse.y)
                                            apercuGlisser.x = point.x - 16; apercuGlisser.y = point.y - 16
                                        }
                                        onReleased: if (drag.active) apercuGlisser.Drag.drop()
                                        onCanceled: apercuGlisser.Drag.cancel()
                                        onClicked: CloudEtat.choisir(entree.modelData)
                                        onDoubleClicked: entree.modelData.kind === "directory" ? CloudEtat.entrer(entree.modelData) : CloudEtat.ouvrirFichier(entree.modelData)
                                    }
                                    CloudCibleDepot {
                                        id: depotDossier; anchors.fill: parent
                                        destination: entree.modelData.kind === "directory" ? entree.modelData : null
                                    }
                                    Rectangle {
                                        id: apercuGlisser
                                        parent: coucheGlisser
                                        property var entreeCloud: entree.modelData
                                        width: Math.min(220, libelleGlisser.implicitWidth + 28); height: 34; radius: 12
                                        visible: sourisEntree.drag.active
                                        color: Couleurs.carte; border.width: 1; border.color: Couleurs.accent
                                        Drag.active: sourisEntree.drag.active
                                        Drag.source: apercuGlisser
                                        Drag.keys: ["nc-cloud-entry"]
                                        Drag.supportedActions: Qt.MoveAction
                                        Drag.hotSpot.x: 16; Drag.hotSpot.y: 16
                                        Texte { id: libelleGlisser; anchors.centerIn: parent; width: Math.min(192, implicitWidth); text: entree.modelData.name; elide: Text.ElideMiddle; font.pixelSize: 12 }
                                    }
                                }
                            }
                        }
                        CloudBouton { visible: CloudEtat.suite !== ""; texte: Reglages.t("Afficher la suite", "Load more"); enabled: !CloudEtat.occupe; onClic: CloudEtat.lister(CloudEtat.dossier.id, CloudEtat.suite) }
                        Texte { width: parent.width; wrapMode: Text.Wrap; secondaire: true; font.pixelSize: 11; text: Reglages.t("Glisse un fichier ou un dossier vers un dossier ou la flèche ↑ pour le déplacer.", "Drag a file or folder onto a folder or the ↑ arrow to move it.") }
                    }
                    CloudCarte {
                        width: zones.large ? zones.width - Math.round((zones.width - 14) * 0.55) - 14 : zones.width
                        Texte { text: Reglages.t("Déposer des fichiers", "Upload files"); font.pixelSize: 17; font.weight: Font.DemiBold }
                        CloudBouton {
                            objectName: "cloudImporter"
                            width: parent.width; icone: "add"; texte: Reglages.t("Importer des fichiers…", "Import files…")
                            enabled: CloudEtat.enLigne && !CloudEtat.occupe
                            onClic: importation.open()
                        }
                        Rectangle {
                            width: parent.width; height: 148; radius: 18
                            color: Qt.alpha(Couleurs.accent, zoneDepot.containsDrag ? 0.19 : 0.06)
                            border.width: 1; border.color: Qt.alpha(Couleurs.accent, zoneDepot.containsDrag ? 0.75 : 0.25)
                            Behavior on color { enabled: !Reglages.sobre; ColorAnimation { duration: 120 } }
                            Column {
                                anchors.centerIn: parent; width: parent.width - 28; spacing: 9
                                Ico { anchors.horizontalCenter: parent.horizontalCenter; nom: "cloud_upload"; taille: 34; color: Couleurs.accent }
                                Texte { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: zoneDepot.containsDrag ? Reglages.t("Relâche tes fichiers ici", "Drop your files here") : Reglages.t("Glisse tes fichiers ici", "Drag your files here"); font.weight: Font.DemiBold; wrapMode: Text.Wrap }
                                Texte { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: Reglages.t("Jusqu’à 8 fichiers · sources conservées", "Up to 8 files · originals kept"); secondaire: true; font.pixelSize: 11; wrapMode: Text.Wrap }
                            }
                            DropArea {
                                id: zoneDepot; anchors.fill: parent
                                onEntered: drag => { if (!drag.hasUrls) drag.accepted = false }
                                onDropped: drop => {
                                    if (!drop.hasUrls) return
                                    var urls = []; for (let i = 0; i < drop.urls.length; ++i) urls.push(String(drop.urls[i]))
                                    CloudEtat.deposer(urls); drop.accept(Qt.CopyAction)
                                }
                            }
                        }
                        Column {
                            width: parent.width; spacing: 8; visible: CloudEtat.fichiers.length > 0
                            Repeater {
                                model: CloudEtat.fichiers
                                delegate: Row {
                                    required property var modelData
                                    width: parent.width; spacing: 7
                                    Ico { nom: "description"; taille: 16; color: Couleurs.accent; anchors.verticalCenter: parent.verticalCenter }
                                    Texte { width: parent.width - 23; text: fen.nomFichier(parent.modelData); font.pixelSize: 12 }
                                }
                            }
                        }
                        Texte { width: parent.width; wrapMode: Text.Wrap; secondaire: true; font.pixelSize: 12; text: Reglages.t("Choisis la destination dans « Mes fichiers », puis envoie ta sélection.", "Choose a destination in “My files”, then upload your selection.") }
                        CloudBouton { width: parent.width; height: 38; primaire: true; icone: "upload"; texte: Reglages.t("Envoyer ici", "Upload here") + (CloudEtat.fichiers.length > 0 ? " · " + CloudEtat.fichiers.length : ""); enabled: CloudEtat.enLigne && CloudEtat.fichiers.length > 0 && !CloudEtat.occupe; onClic: CloudEtat.envoyer() }
                        CloudBouton { visible: CloudEtat.fichiers.length > 0; texte: Reglages.t("Vider la sélection", "Clear selection"); onClic: CloudEtat.fichiers = [] }
                    }
                }
                CloudCarte {
                    width: parent.width
                    Flow {
                        width: parent.width; spacing: 8
                        Texte { width: Math.max(120, parent.width - actionsTransferts.width - 8); height: 34; verticalAlignment: Text.AlignVCenter; text: Reglages.t("Transferts", "Transfers"); font.pixelSize: 17; font.weight: Font.DemiBold }
                        Row {
                            id: actionsTransferts; spacing: 8
                            CloudBouton {
                                objectName: "cloudEffacerTransferts"
                                icone: "delete_sweep"; texte: Reglages.t("Effacer les terminés", "Clear finished")
                                enabled: !CloudEtat.occupe && CloudEtat.transferts.some(t => ["committed", "cancelled", "expired"].indexOf(t.state) >= 0)
                                onClic: CloudEtat.demander({ op: "effacer_transferts" })
                            }
                            CloudBouton { icone: "refresh"; texte: Reglages.t("Actualiser", "Refresh"); enabled: !CloudEtat.occupe; onClic: CloudEtat.demander({ op: "transferts" }) }
                        }
                    }
                    Texte { visible: CloudEtat.transferts.length === 0; width: parent.width; wrapMode: Text.Wrap; text: Reglages.t("Aucun transfert pour le moment. Tes prochains envois apparaîtront ici.", "No transfers yet. Your next uploads will appear here."); secondaire: true; font.pixelSize: 12 }
                    Repeater {
                        model: CloudEtat.transferts
                        delegate: Rectangle {
                            id: transfert
                            required property var modelData
                            readonly property color teinte: modelData.state === "committed" ? Couleurs.vert : (["conflict", "interrupted"].indexOf(modelData.state) >= 0 ? Couleurs.orange : Couleurs.accent)
                            width: parent.width; height: details.implicitHeight + 24; radius: 14; color: Qt.alpha(Couleurs.fond, 0.25)
                            Column {
                                id: details
                                x: 12; y: 12; width: parent.width - 24; spacing: 9
                                Row {
                                    width: parent.width; spacing: 8
                                    Ico { nom: transfert.modelData.state === "committed" ? "check_circle" : "description"; taille: 18; color: transfert.teinte }
                                    Texte { width: Math.max(0, parent.width - statutTransfert.implicitWidth - 34); text: transfert.modelData.name; font.weight: Font.DemiBold; font.pixelSize: 12 }
                                    Texte { id: statutTransfert; text: CloudEtat.etatTexte(transfert.modelData.state); color: transfert.teinte; font.pixelSize: 11 }
                                }
                                Rectangle {
                                    width: parent.width; height: 4; radius: 2; color: Qt.alpha(Couleurs.texte, 0.08)
                                    Rectangle { width: parent.width * fen.progression(transfert.modelData); height: parent.height; radius: 2; color: transfert.teinte }
                                }
                                Texte { width: parent.width; text: Math.round(fen.progression(transfert.modelData) * 100) + " % · " + fen.taille(transfert.modelData.size); secondaire: true; font.pixelSize: 11 }
                                Texte { width: parent.width; visible: text !== ""; text: transfert.modelData.message || ""; wrapMode: Text.Wrap; color: Couleurs.orange; font.pixelSize: 12 }
                                Texte { width: parent.width; wrapMode: Text.Wrap; secondaire: true; font.pixelSize: 11; visible: transfert.modelData.state === "conflict" && !!transfert.modelData.current; text: transfert.modelData.current ? Reglages.t("Version distante : ", "Remote version: ") + new Date(transfert.modelData.current.modified * 1000).toLocaleString(Qt.locale()) + " · " + fen.taille(transfert.modelData.current.size) : "" }
                                Flow {
                                    width: parent.width; spacing: 8
                                    CloudBouton { visible: transfert.modelData.state === "interrupted"; texte: Reglages.t("Reprendre / vérifier", "Resume / verify"); enabled: CloudEtat.enLigne; onClic: CloudEtat.demander({ op: "reprise", id: transfert.modelData.id }) }
                                    CloudBouton { visible: transfert.modelData.state === "conflict"; texte: Reglages.t("Conserver les deux", "Keep both"); enabled: CloudEtat.enLigne; onClic: CloudEtat.demander({ op: "resoudre", id: transfert.modelData.id, policy: "keep_both" }) }
                                    CloudBouton { visible: transfert.modelData.state === "conflict" && transfert.modelData.current && transfert.modelData.current.kind === "file"; texte: Reglages.t("Remplacer", "Replace"); enabled: CloudEtat.enLigne; onClic: CloudEtat.demander({ op: "resoudre", id: transfert.modelData.id, policy: "replace" }) }
                                    CloudBouton { visible: ["committed", "cancelled", "expired"].indexOf(transfert.modelData.state) < 0; texte: Reglages.t("Annuler", "Cancel"); enabled: CloudEtat.enLigne; onClic: CloudEtat.demander({ op: "annuler", id: transfert.modelData.id }) }
                                }
                            }
                        }
                    }
                }
                Texte { width: parent.width; wrapMode: Text.Wrap; horizontalAlignment: Text.AlignHCenter; font.pixelSize: 11; secondaire: true; text: Reglages.t("Double-clique pour ouvrir. Les fichiers s’ouvrent en copie locale ; dépose-les à nouveau pour publier une modification.", "Double-click to open. Files open as local copies; upload them again to publish changes.") }
            }
        }
        Flickable {
            id: defilePartage
            visible: partageLocal.ouvert
            x: surface.coteACote ? defile.width : 0
            y: surface.debut; height: parent.height - y; width: parent.width - x
            contentWidth: width; contentHeight: colonnePartage.implicitHeight + 48
            clip: true; boundsBehavior: Flickable.StopAtBounds
            flickableDirection: Flickable.VerticalFlick
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
            Column {
                id: colonnePartage
                x: surface.coteACote ? 4 : 26; y: 24; width: parent.width - x - 26; spacing: 14
                CloudPartage { id: partageLocal; width: parent.width }
                CloudCarte {
                    width: parent.width
                    Texte { text: Reglages.t("Appareils appairés", "Paired devices"); font.pixelSize: 17; font.weight: Font.DemiBold }
                    Texte {
                        visible: partageLocal.pairs.length === 0; width: parent.width; wrapMode: Text.Wrap; secondaire: true
                        text: partageLocal.pairsCharges ? Reglages.t("Aucun appareil appairé. Choisis un destinataire ci-dessus pour l’ajouter.", "No paired devices. Choose a recipient above to add one.")
                             : (partageLocal.pret ? Reglages.t("Chargement…", "Loading…") : Reglages.t("En attente du service de partage", "Waiting for the sharing service"))
                    }
                    Repeater {
                        model: partageLocal.pairs
                        delegate: Item {
                            required property var modelData
                            width: parent.width; height: 42
                            Rectangle {
                                id: voyant; width: 9; height: 9; radius: 5; anchors.verticalCenter: parent.verticalCenter
                                color: modelData.online === true ? Couleurs.vert : modelData.online === false ? Couleurs.texteSec : Couleurs.orange
                            }
                            Column {
                                anchors.left: voyant.right; anchors.leftMargin: 10; anchors.right: utiliser.left; anchors.rightMargin: 8
                                anchors.verticalCenter: parent.verticalCenter; spacing: 3
                                Texte { width: parent.width; text: modelData.name; font.weight: Font.DemiBold }
                                Texte {
                                    width: parent.width; secondaire: true; font.pixelSize: 12
                                    text: modelData.online === true ? Reglages.t("Joignable", "Reachable") + " · " + (modelData.bt ? "Bluetooth" : "IP")
                                        : modelData.online === false ? Reglages.t("Injoignable", "Unreachable") : Reglages.t("Vérification…", "Checking…")
                                }
                            }
                            CloudBouton {
                                id: utiliser; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                                visible: modelData.online === true; enabled: !partageLocal.occupe && !partageLocal.recherche
                                texte: Reglages.t("Sélectionner", "Select")
                                onClic: { partageLocal.changer(modelData.bt ? "bt" : "ip"); partageLocal.choisir(modelData.host, modelData.id); defilePartage.contentY = 0 }
                            }
                        }
                    }
                }
            }
        }
    }
}
