import QtQuick

Rectangle {
    default property alias enfants: interieur.data
    implicitHeight: interieur.implicitHeight + 36
    height: implicitHeight
    radius: 22
    color: Qt.alpha(Qt.tint(Couleurs.fond, Qt.alpha(Couleurs.texte, 0.08)), 0.85)
    border.width: 1
    border.color: Qt.alpha(Couleurs.texte, 0.09)
    Column { id: interieur; x: 20; y: 18; width: parent.width - 40; spacing: 14 }
}
