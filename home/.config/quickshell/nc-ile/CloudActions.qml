import QtQuick
import QtQuick.Controls

CloudCarte {
    id: actions
    // Keep the browser in place on first click so a double-click still targets
    // the same row. Forms can grow after an explicit action button is pressed.
    height: CloudEtat.action === "" ? (width < 650 ? 156 : 114) : implicitHeight
    readonly property var selection: CloudEtat.selection || ({})
    readonly property bool libre: CloudEtat.enLigne && !CloudEtat.occupe
    readonly property var capacites: CloudEtat.statut.features || ({})
    Connections {
        target: CloudEtat
        function onActionChanged() {
            if (CloudEtat.action === "renommer") nom.text = actions.selection.name || ""
            if (CloudEtat.action === "creer_fichier") nom.text = "Nouveau fichier.txt"
            if (["renommer", "creer_fichier"].indexOf(CloudEtat.action) >= 0) {
                nom.forceActiveFocus(); nom.selectAll()
            }
        }
    }
    Item {
        width: parent.width; height: 30
        Texte {
            anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
            width: parent.width - fermer.width - 12
            text: CloudEtat.action === "creer_fichier" ? Reglages.t("Créer un fichier vide", "Create an empty file") : (actions.selection.name || Reglages.t("Sélectionne un fichier ou un dossier", "Select a file or folder"))
            font.pixelSize: 16; font.weight: Font.DemiBold
        }
        CloudBouton {
            id: fermer; visible: CloudEtat.selection !== null || CloudEtat.action !== ""; anchors.right: parent.right; texte: Reglages.t("Fermer", "Close")
            enabled: !CloudEtat.occupe
            onClic: { CloudEtat.action = ""; CloudEtat.selection = null; CloudEtat.suppression = null }
        }
    }
    Flow {
        visible: CloudEtat.action === "" && CloudEtat.selection !== null; width: parent.width; spacing: 8
        CloudBouton { visible: actions.selection.kind === "file"; icone: "open_in_new"; texte: Reglages.t("Ouvrir", "Open"); enabled: actions.libre; onClic: CloudEtat.ouvrirFichier(actions.selection) }
        CloudBouton { visible: actions.selection.kind === "directory"; icone: "folder_open"; texte: Reglages.t("Ouvrir le dossier", "Open folder"); enabled: actions.libre; onClic: CloudEtat.entrer(actions.selection) }
        CloudBouton { icone: "edit"; texte: Reglages.t("Renommer", "Rename"); enabled: actions.libre && actions.capacites.entry_move === true; onClic: CloudEtat.action = "renommer" }
        CloudBouton { icone: "drive_file_move"; texte: Reglages.t("Déplacer", "Move"); enabled: actions.libre && actions.capacites.entry_move === true; onClic: CloudEtat.preparerDeplacement() }
        CloudBouton { icone: "delete"; teinte: Couleurs.rouge; texte: Reglages.t("Supprimer", "Delete"); enabled: actions.libre && actions.capacites.directory_delete === true; onClic: CloudEtat.preparerSuppression() }
    }
    Texte {
        visible: CloudEtat.selection === null && CloudEtat.action === ""
        width: parent.width; wrapMode: Text.Wrap; secondaire: true; font.pixelSize: 12
        text: Reglages.t("Un clic affiche les actions. Un double-clic ouvre le fichier ou le dossier.", "Click to show actions. Double-click to open a file or folder.")
    }
    Row {
        visible: ["renommer", "creer_fichier"].indexOf(CloudEtat.action) >= 0
        width: parent.width; spacing: 8
        TextField {
            id: nom; width: parent.width - confirmerNom.width - 8; height: 36
            color: Couleurs.texte; font.family: "Adwaita Sans"; font.pixelSize: 12
            selectByMouse: true; leftPadding: 12; rightPadding: 12
            enabled: actions.libre
            background: Rectangle { radius: 12; color: Qt.alpha(Couleurs.fond, 0.5); border.width: 1; border.color: nom.activeFocus ? Couleurs.accent : Qt.alpha(Couleurs.texte, 0.1) }
            onAccepted: confirmerNom.valider()
        }
        CloudBouton {
            id: confirmerNom; height: 36; primaire: true
            texte: CloudEtat.action === "renommer" ? Reglages.t("Renommer", "Rename") : Reglages.t("Créer", "Create")
            enabled: actions.libre && nom.text.trim() !== ""
            function valider() {
                if (!enabled) return
                if (CloudEtat.action === "renommer") CloudEtat.deplacer(CloudEtat.dossier, nom.text)
                else CloudEtat.demander({ op: "creer_fichier", parent_id: CloudEtat.dossier.id,
                                          parent_revision: CloudEtat.dossier.revision, name: nom.text })
            }
            onClic: valider()
        }
    }
    Column {
        visible: CloudEtat.action === "supprimer" && CloudEtat.suppression !== null
        width: parent.width; spacing: 12
        Texte {
            width: parent.width; wrapMode: Text.Wrap; color: Couleurs.orange
            text: CloudEtat.suppression ? Reglages.t("Supprimer définitivement cette sélection et ses anciennes versions ?", "Permanently delete this selection and its older versions?") +
                  (actions.selection.kind === "directory" ? "\n" + CloudEtat.suppression.files + Reglages.t(" fichier(s) et ", " file(s) and ") + Math.max(0, CloudEtat.suppression.directories - 1) + Reglages.t(" sous-dossier(s) seront supprimés.", " subfolder(s) will be deleted.") : "") : ""
        }
        Flow {
            width: parent.width; spacing: 8
            CloudBouton { primaire: true; teinte: Couleurs.rouge; texte: Reglages.t("Confirmer la suppression", "Confirm deletion"); enabled: actions.libre; onClic: CloudEtat.confirmerSuppression() }
            CloudBouton { texte: Reglages.t("Annuler", "Cancel"); enabled: !CloudEtat.occupe; onClic: { CloudEtat.action = ""; CloudEtat.suppression = null } }
        }
    }
    Column {
        visible: CloudEtat.action === "deplacer"; width: parent.width; spacing: 10
        Texte { text: Reglages.t("Choisis le dossier de destination", "Choose the destination folder"); secondaire: true }
        Row {
            width: parent.width; spacing: 10
            CloudBouton { width: 34; icone: "arrow_upward"; enabled: actions.libre && CloudEtat.destinationChemin.length > 0; onClic: CloudEtat.remonterDestination() }
            Texte { width: parent.width - 44; height: 34; elide: Text.ElideMiddle; text: "/" + CloudEtat.destinationChemin.concat([CloudEtat.destination]).filter(p => p.id !== "root").map(p => p.name).join("/") }
        }
        ListView {
            width: parent.width; height: Math.min(180, contentHeight)
            clip: true; spacing: 4
            model: CloudEtat.destinations.filter(e => e.kind === "directory" && e.id !== actions.selection.id)
            delegate: Rectangle {
                required property var modelData
                width: ListView.view.width; height: 36; radius: 10
                color: survol.containsMouse ? Qt.alpha(Couleurs.accent, 0.14) : Qt.alpha(Couleurs.fond, 0.2)
                Row { x: 10; height: parent.height; width: parent.width - 20; spacing: 8
                    Ico { nom: "folder"; taille: 17; color: Couleurs.accent; anchors.verticalCenter: parent.verticalCenter }
                    Texte { width: parent.width - 25; height: parent.height; text: modelData.name }
                }
                MouseArea { id: survol; anchors.fill: parent; hoverEnabled: true; enabled: actions.libre; onClicked: CloudEtat.entrerDestination(modelData) }
            }
        }
        CloudBouton { visible: CloudEtat.destinationSuite !== ""; texte: Reglages.t("Afficher la suite", "Load more"); enabled: actions.libre; onClic: CloudEtat.choisirDestination(CloudEtat.destination.id, CloudEtat.destinationSuite) }
        CloudBouton { primaire: true; texte: Reglages.t("Déplacer ici", "Move here"); enabled: actions.libre && CloudEtat.destination.revision !== ""; onClic: CloudEtat.deplacer(CloudEtat.destination) }
    }
}
