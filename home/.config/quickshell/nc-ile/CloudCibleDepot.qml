import QtQuick

DropArea {
    id: cible
    property var destination: null
    keys: ["nc-cloud-entry"]
    enabled: CloudEtat.enLigne && !CloudEtat.occupe && destination !== null
    function accepte(source) {
        return source && source.entreeCloud && destination
            && source.entreeCloud.id !== destination.id && destination.id !== CloudEtat.dossier.id
    }
    onEntered: drag => { drag.accepted = accepte(drag.source) }
    onDropped: drop => {
        if (accepte(drop.source) && CloudEtat.deplacerEntree(drop.source.entreeCloud, destination))
            drop.accept(Qt.MoveAction)
    }
}
