import QtQuick

Rectangle {
    id: bouton
    property string texte: ""
    property string icone: ""
    property bool primaire: false
    property color teinte: Couleurs.accent
    signal clic()
    implicitWidth: libelle.implicitWidth + 28
    implicitHeight: 34
    width: implicitWidth; height: implicitHeight; radius: height / 2
    opacity: enabled ? 1 : 0.4
    color: primaire ? (zone.containsMouse ? Qt.lighter(teinte, 1.08) : teinte)
                    : (zone.containsMouse ? Qt.alpha(teinte, 0.22) : Qt.alpha(Couleurs.carte, 0.65))
    border.width: 1
    border.color: activeFocus ? Couleurs.accent : (primaire ? "transparent" : Qt.alpha(Couleurs.texte, 0.1))
    Behavior on color { enabled: !Reglages.sobre; ColorAnimation { duration: 120 } }
    Row {
        id: libelle
        anchors.centerIn: parent; spacing: 7
        Ico { visible: bouton.icone !== ""; nom: bouton.icone; taille: 16; anchors.verticalCenter: parent.verticalCenter; color: bouton.primaire ? Couleurs.surAccent : bouton.teinte }
        Texte { text: bouton.texte; font.pixelSize: 12; font.weight: Font.DemiBold; anchors.verticalCenter: parent.verticalCenter; color: bouton.primaire ? Couleurs.surAccent : Couleurs.texte }
    }
    MouseArea { id: zone; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: bouton.clic() }
    Accessible.role: Accessible.Button
    Accessible.name: texte
    activeFocusOnTab: true
    Keys.onSpacePressed: clic()
    Keys.onReturnPressed: clic()
}
