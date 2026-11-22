// Dedicated Wayland surface: hidden means no surface and no input region.
import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: depot
    required property var modelData
    screen: modelData
    anchors.top: true
    anchors.left: true
    margins.left: Math.max(0, Math.round((modelData.width - 36) / 2 + Number(Reglages.val("CLOUD_BARRE_DECALAGE", "100"))))
    implicitWidth: 36; implicitHeight: Gabarit.barre
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "nc-cloud"
    Rectangle {
        anchors.centerIn: parent
        width: 32; height: 28; radius: 14
        color: zone.containsDrag ? Couleurs.accent : Couleurs.gris2
        opacity: CloudEtat.enLigne ? 1 : 0.5
        Ico { anchors.centerIn: parent; nom: "cloud"; taille: 20; color: Couleurs.texte }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { CloudEtat.basculerPanneau() } }
    }
    DropArea {
        id: zone
        anchors.fill: parent
        onEntered: drag => { if (!drag.hasUrls) drag.accepted = false }
        onDropped: drop => {
            if (!drop.hasUrls) return
            var urls = []
            for (let i = 0; i < drop.urls.length; ++i) urls.push(String(drop.urls[i]))
            CloudEtat.deposer(urls)
            drop.accept(Qt.CopyAction)
        }
    }
}
