// Fenêtre « Santé Garmin » (Super + Alt + S si GARMIN_ACTIF=oui, ou clic sur la pastille de la barre).
// Dashboard Bento complet sur le moteur officiel nc-garmin / GarminEtat.qml :
//   1. En-tête : titre, heure de dernière synchro, « Personnaliser », « Actualiser » (avec état « Synchro… »), ⚙, « Fermer » ;
//   2. Tiroir « Personnaliser » (GarminTiroir.qml) : cocher/décocher, ↑ / ↓, mode Démo, compte ;
//   3. Carte d'accueil hors connexion (GarminAccueil.qml) si non connecté et hors démo ;
//   4. Rangée supérieure de 5 jauges en arc (Body Battery, Cœur, Sommeil, Stress, Pas avec distance en km) ;
//   5. Cartes Bento détaillées avec courbes lissées Canvas (bb_serie, fc_serie, stress_serie) et barre 4 phases du sommeil.
import QtQuick
import Quickshell

FloatingWindow {
    id: garmin
    signal fermer()
    title: Reglages.t("Garmin", "Garmin")
    color: "transparent"
    implicitWidth: garmin.largeurCarte
    implicitHeight: Math.min(Math.round(garmin.hauteurEcran * 0.9), contenu.implicitHeight + 52)
    minimumSize: Qt.size(520, 340)
    onClosed: garmin.fermer()
    onVisibleChanged: if (!visible) garmin.fermer()

    readonly property real largeurEcran: garmin.screen ? garmin.screen.width : 1600
    readonly property real hauteurEcran: garmin.screen ? garmin.screen.height : 1000
    readonly property bool verre: Reglages.val("FENETRES_FLOU", "oui") !== "non" && !Reglages.sobre
    readonly property int largeurCarte: Math.min(920, Math.round(largeurEcran * 0.92))
    property bool tiroir: false
    readonly property var m: GarminEtat.metriquesVisibles

    function quitter() { garmin.fermer() }
    Component.onCompleted: GarminEtat.panneauOuvert = true
    Component.onDestruction: GarminEtat.panneauOuvert = false

    function a(v) { return v !== undefined && v !== null }
    function nb(v) { return a(v) ? String(v) : "—" }
    function valOu(v, suffixe) { return a(v) ? (String(v) + suffixe) : "—" }
    function heures(s) {
        if (!a(s)) return "—"
        return Math.floor(s / 3600) + "h " + String(Math.floor((s % 3600) / 60)).padStart(2, "0") + "m"
    }
    function heureMaj(ts) {
        if (!ts || ts <= 0) return ""
        return Qt.formatTime(new Date(ts * 1000), "hh:mm")
    }
    function fcCourante() {
        var s = garmin.m.fc_serie
        if (Array.isArray(s) && s.length > 0) return s[s.length - 1]
        return garmin.m.fc_repos
    }
    function qualStress(v) {
        if (!a(v)) return ""
        if (v < 26) return Reglages.t("Calme", "Rest")
        if (v < 51) return Reglages.t("Faible", "Low")
        if (v < 76) return Reglages.t("Moyen", "Medium")
        return Reglages.t("Élevé", "High")
    }

    // ── Composant : Bouton pilule ──
    component BoutonPilule: Rectangle {
        id: bp
        property string texte: ""
        property string icone: ""
        property bool choisi: false
        property color teinte: Couleurs.accent
        property bool actif: true
        signal clic()

        width: rangeeBp.implicitWidth + 26
        height: 32
        radius: 16
        opacity: actif ? 1 : 0.45
        color: choisi
               ? Qt.alpha(teinte, 0.28)
               : (zoneBp.containsMouse ? Qt.alpha(teinte, 0.20) : Qt.alpha(Couleurs.carte, 0.65))
        border.width: 1
        border.color: choisi ? Qt.alpha(teinte, 0.65) : Qt.alpha(Couleurs.texte, 0.1)
        Behavior on color { enabled: !Reglages.sobre; ColorAnimation { duration: 120 } }

        Row {
            id: rangeeBp
            anchors.centerIn: parent
            spacing: 6
            Ico {
                visible: bp.icone !== ""
                anchors.verticalCenter: parent.verticalCenter
                nom: bp.icone
                taille: 15
                color: bp.choisi || zoneBp.containsMouse ? bp.teinte : Couleurs.texteSec
            }
            Texte {
                anchors.verticalCenter: parent.verticalCenter
                text: bp.texte
                font.pixelSize: 12
                font.weight: bp.choisi ? Font.DemiBold : Font.Normal
                color: bp.choisi ? bp.teinte : Couleurs.texte
            }
        }
        MouseArea {
            id: zoneBp
            anchors.fill: parent
            hoverEnabled: true
            enabled: bp.actif
            onClicked: bp.clic()
        }
    }

    // ── Composant : Jauge en arc Bento ──
    component JaugeBento: Rectangle {
        id: jg
        property string titre: ""
        property string valeur: "—"
        property string sousValeur: ""
        property string icone: ""
        property real taux: 0
        property color teinte: Couleurs.vert

        height: 136
        radius: 20
        color: Qt.alpha(Qt.tint(Couleurs.fond, Qt.alpha(Couleurs.texte, 0.08)), 0.85)
        border.width: 1
        border.color: Qt.alpha(Couleurs.texte, 0.09)

        readonly property real plein: Math.max(0, Math.min(1, taux))
        property real anime: plein
        Behavior on anime { enabled: !Reglages.sobre; NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }

        Canvas {
            id: arcCanvas
            anchors.horizontalCenter: parent.horizontalCenter
            y: 10
            width: 82; height: 82
            readonly property real f: jg.anime
            readonly property color t: jg.teinte
            readonly property color fondArc: Couleurs.gris3
            onFChanged: requestPaint()
            onTChanged: requestPaint()
            onFondArcChanged: requestPaint()
            onPaint: {
                var c = getContext("2d"); c.reset()
                c.lineWidth = 7.5; c.lineCap = "round"
                var a0 = Math.PI * 0.75, a1 = Math.PI * 2.25
                c.strokeStyle = String(fondArc); c.beginPath(); c.arc(41, 41, 34, a0, a1); c.stroke()
                if (f > 0.004) {
                    c.strokeStyle = String(t); c.beginPath(); c.arc(41, 41, 34, a0, a0 + (a1 - a0) * f); c.stroke()
                }
            }
            Column {
                anchors.centerIn: parent
                anchors.verticalCenterOffset: 1
                spacing: 0
                Texte {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: jg.valeur
                    font.pixelSize: jg.valeur.length > 5 ? 13 : 16
                    font.weight: Font.Bold
                    font.features: { "tnum": 1 }
                    color: jg.valeur === "—" ? Couleurs.texteSec : jg.teinte
                }
                Texte {
                    visible: jg.sousValeur !== ""
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: jg.sousValeur
                    font.pixelSize: 9
                    secondaire: true
                }
            }
        }

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 10
            spacing: 5
            Ico { nom: jg.icone; taille: 14; color: jg.teinte; anchors.verticalCenter: parent.verticalCenter }
            Texte {
                text: jg.titre
                font.pixelSize: 12
                font.weight: Font.DemiBold
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    // ── Composant : Courbe lissée avec dégradé ──
    component CourbeBento: Canvas {
        id: cb
        property var points: []
        property color teinte: Couleurs.accent
        property real minVal: -1
        property real maxVal: -1
        height: 66
        onPointsChanged: requestPaint()
        onTeinteChanged: requestPaint()
        onWidthChanged: requestPaint()
        onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            var pts = cb.points || []
            if (pts.length < 2 || width <= 4 || height <= 4) return
            var lo = cb.minVal >= 0 ? cb.minVal : pts[0]
            var hi = cb.maxVal >= 0 ? cb.maxVal : pts[0]
            for (var i = 0; i < pts.length; i++) {
                if (pts[i] < lo) lo = pts[i]
                if (pts[i] > hi) hi = pts[i]
            }
            if (hi <= lo) hi = lo + 1
            var padY = 6
            var hUtile = height - padY * 2
            var coords = []
            for (var j = 0; j < pts.length; j++) {
                var px = (j / (pts.length - 1)) * (width - 8) + 4
                var py = padY + hUtile * (1 - (pts[j] - lo) / (hi - lo))
                coords.push({ x: px, y: py })
            }
            var grad = ctx.createLinearGradient(0, 0, 0, height)
            grad.addColorStop(0, String(Qt.alpha(cb.teinte, 0.35)))
            grad.addColorStop(1, String(Qt.alpha(cb.teinte, 0.0)))
            ctx.beginPath()
            ctx.moveTo(coords[0].x, height)
            for (var k = 0; k < coords.length; k++) ctx.lineTo(coords[k].x, coords[k].y)
            ctx.lineTo(coords[coords.length - 1].x, height)
            ctx.closePath()
            ctx.fillStyle = grad
            ctx.fill()

            ctx.beginPath()
            ctx.moveTo(coords[0].x, coords[0].y)
            for (var n = 1; n < coords.length; n++) {
                var xc = (coords[n - 1].x + coords[n].x) / 2
                var yc = (coords[n - 1].y + coords[n].y) / 2
                ctx.quadraticCurveTo(coords[n - 1].x, coords[n - 1].y, xc, yc)
            }
            ctx.lineTo(coords[coords.length - 1].x, coords[coords.length - 1].y)
            ctx.strokeStyle = String(cb.teinte)
            ctx.lineWidth = 2.4
            ctx.lineCap = "round"
            ctx.stroke()

            var der = coords[coords.length - 1]
            ctx.beginPath()
            ctx.arc(der.x, der.y, 4, 0, Math.PI * 2)
            ctx.fillStyle = String(cb.teinte)
            ctx.fill()
        }
    }

    // ── Composant : Carte de section Bento ──
    component CarteBento: Rectangle {
        default property alias enfants: colBento.data
        width: parent.width
        height: colBento.implicitHeight + 34
        radius: 22
        color: Qt.alpha(Qt.tint(Couleurs.fond, Qt.alpha(Couleurs.texte, 0.08)), 0.85)
        border.width: 1
        border.color: Qt.alpha(Couleurs.texte, 0.09)
        Column {
            id: colBento
            x: 20; y: 17
            width: parent.width - 40
            spacing: 11
        }
    }

    Item {
        id: carte
        anchors.fill: parent
        Keys.onEscapePressed: garmin.quitter()

        Rectangle {
            id: fondVerre
            anchors.fill: parent
            color: Qt.alpha(Couleurs.fond, garmin.verre ? 0.62 : 0.92)
        }
        Item { id: clavier; objectName: "nc-garmin-clavier"; anchors.fill: parent; focus: true }

        Flickable {
            id: defile
            objectName: "nc-garmin-defile"
            anchors.fill: parent; anchors.margins: 1
            contentWidth: width; contentHeight: contenu.implicitHeight + 52
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            flickableDirection: Flickable.VerticalFlick

            Column {
                id: contenu
                objectName: "nc-garmin-contenu"
                x: 26; y: 24; width: defile.width - 52
                spacing: 14

                // ── 1. EN-TÊTE ──
                Item {
                    width: parent.width; height: 52
                    Row {
                        anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                        spacing: 12
                        GarminIcone { anchors.verticalCenter: parent.verticalCenter; taille: 26; color: GarminEtat.pret ? Couleurs.accent : Couleurs.gris5 }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter; spacing: 2
                            Row {
                                spacing: 8
                                Texte {
                                    objectName: "nc-garmin-titre"
                                    text: Reglages.t("Santé Garmin", "Garmin Health")
                                    font.pixelSize: 24; font.weight: Font.Bold
                                }
                                Rectangle {
                                    visible: GarminEtat.demo
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: txtDemo.implicitWidth + 14; height: 20; radius: 10
                                    color: Qt.alpha(Couleurs.orange, 0.22)
                                    border.width: 1; border.color: Qt.alpha(Couleurs.orange, 0.5)
                                    Texte { id: txtDemo; anchors.centerIn: parent; text: Reglages.t("DÉMO", "DEMO"); font.pixelSize: 10; font.weight: Font.Bold; color: Couleurs.orange }
                                }
                            }
                            Texte {
                                objectName: "nc-garmin-sous-titre"
                                secondaire: true; font.pixelSize: 12
                                text: !GarminEtat.actif
                                      ? Reglages.t("Fonction désactivée (nc-reglages → Santé Garmin)", "Disabled (nc-reglages → Garmin health)")
                                      : (!GarminEtat.pret
                                         ? Reglages.t("Connecteur non officiel · Aucun compte connecté", "Unofficial connector · No account connected")
                                         : (GarminEtat.masque
                                            ? Reglages.t("Indicateurs masqués (partage d'écran)", "Metrics hidden (screen sharing)")
                                            : (GarminEtat.demo
                                               ? Reglages.t("Données de démonstration", "Demo data")
                                               : (Reglages.t("Garmin Connect", "Garmin Connect")
                                                  + (GarminEtat.maj > 0 ? " · " + Reglages.t("Synchro ", "Synced ") + garmin.heureMaj(GarminEtat.maj) : "")))
                                              + " · " + GarminEtat.widgetsActifs.length + " " + Reglages.t("indicateurs actifs", "active widgets")))
                            }
                        }
                    }

                    Row {
                        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                        spacing: 8
                        BoutonPilule {
                            objectName: "nc-garmin-personnaliser"
                            visible: GarminEtat.actif
                            icone: "tune"
                            texte: Reglages.t("Personnaliser", "Customize")
                            choisi: garmin.tiroir
                            onClic: garmin.tiroir = !garmin.tiroir
                        }
                        BoutonPilule {
                            objectName: "nc-garmin-actualiser"
                            visible: GarminEtat.actif && GarminEtat.pret
                            icone: "refresh"
                            texte: GarminEtat.occupe ? Reglages.t("Synchro…", "Syncing…") : Reglages.t("Actualiser", "Refresh")
                            actif: !GarminEtat.occupe
                            onClic: GarminEtat.actualiser()
                        }
                        BoutonReglages {
                            objectName: "nc-garmin-reglages"
                            anchors.verticalCenter: parent.verticalCenter
                            section: "Santé Garmin"
                        }
                        BoutonPilule {
                            objectName: "nc-garmin-fermer"
                            icone: "close"
                            texte: Reglages.t("Fermer", "Close")
                            onClic: garmin.quitter()
                        }
                    }
                }

                // ── 2. TIROIR PERSONNALISER (natif Théo) ──
                GarminTiroir { width: parent.width; visible: garmin.tiroir && GarminEtat.actif }

                // ── 3. CARTE D'ACCUEIL HORS CONNEXION (natif Théo) ──
                GarminAccueil { width: parent.width; visible: GarminEtat.lu && (!GarminEtat.actif || !GarminEtat.pret) }

                // ── 4. RANGÉE SUPÉRIEURE : 5 JAUGES EN ARC BENTO ──
                Row {
                    id: rangeeJauges
                    objectName: "nc-garmin-jauges"
                    visible: GarminEtat.actif && GarminEtat.pret && !GarminEtat.masque
                    width: parent.width
                    spacing: 12

                    readonly property var jaugesVisibles: {
                        var l = []
                        var ordre = GarminEtat.widgetsActifs || []
                        for (var i = 0; i < ordre.length; i++) {
                            var id = ordre[i]
                            if (id === "body_battery" || id === "frequence_cardiaque" || id === "sommeil" || id === "stress" || id === "pas") {
                                l.push(id)
                            }
                        }
                        return l
                    }
                    readonly property int nbJauges: Math.max(1, jaugesVisibles.length)
                    readonly property real largeurJauge: Math.floor((width - (nbJauges - 1) * spacing) / nbJauges)

                    Repeater {
                        model: rangeeJauges.jaugesVisibles
                        JaugeBento {
                            width: rangeeJauges.largeurJauge
                            titre: modelData === "body_battery" ? "Body Battery"
                                 : (modelData === "frequence_cardiaque" ? Reglages.t("Cœur", "Heart Rate")
                                 : (modelData === "sommeil" ? Reglages.t("Sommeil", "Sleep")
                                 : (modelData === "stress" ? "Stress"
                                 : Reglages.t("Pas", "Steps"))))
                            icone: modelData === "body_battery" ? "bolt"
                                 : (modelData === "frequence_cardiaque" ? "favorite"
                                 : (modelData === "sommeil" ? "bedtime"
                                 : (modelData === "stress" ? "self_improvement"
                                 : "directions_walk")))
                            valeur: modelData === "body_battery" ? garmin.valOu(garmin.m.body_battery, "%")
                                  : (modelData === "frequence_cardiaque" ? garmin.valOu(garmin.fcCourante(), " bpm")
                                  : (modelData === "sommeil" ? (garmin.a(garmin.m.sommeil_score) ? (garmin.m.sommeil_score + "/100") : garmin.heures(garmin.m.sommeil_s))
                                  : (modelData === "stress" ? garmin.nb(garmin.m.stress_moyen)
                                  : garmin.nb(garmin.m.pas))))
                            sousValeur: modelData === "body_battery" ? ""
                                      : (modelData === "frequence_cardiaque" ? (garmin.a(garmin.m.fc_repos) ? Reglages.t("Repos ", "Rest ") + garmin.m.fc_repos : "")
                                      : (modelData === "sommeil" ? (garmin.a(garmin.m.sommeil_s) ? garmin.heures(garmin.m.sommeil_s) : "")
                                      : (modelData === "stress" ? garmin.qualStress(garmin.m.stress_moyen)
                                      : (garmin.a(garmin.m.distance_m) ? ((garmin.m.distance_m / 1000).toFixed(2).replace(/\.00$/, "") + " km") : ""))))
                            taux: modelData === "body_battery" ? ((garmin.m.body_battery || 0) / 100)
                                : (modelData === "frequence_cardiaque" ? (garmin.a(garmin.fcCourante()) ? Math.min(1, Math.max(0.15, (garmin.fcCourante() - 40) / 140)) : 0)
                                : (modelData === "sommeil" ? ((garmin.m.sommeil_score || 0) / 100)
                                : (modelData === "stress" ? ((garmin.m.stress_moyen || 0) / 100)
                                : (garmin.m.pas_objectif ? (garmin.m.pas || 0) / garmin.m.pas_objectif : 0))))
                            teinte: modelData === "body_battery" ? "#00a8e8"
                                  : (modelData === "frequence_cardiaque" ? "#ff375f"
                                  : (modelData === "sommeil" ? "#bf5af2"
                                  : (modelData === "stress" ? ((garmin.m.stress_moyen || 0) < 30 ? Couleurs.vert : ((garmin.m.stress_moyen || 0) < 55 ? Couleurs.orange : Couleurs.rouge))
                                  : Couleurs.vert)))
                        }
                    }
                }

                // ── 5. CARTES DÉTAILLÉES BENTO (dans l'ordre choisi) ──
                Repeater {
                    model: GarminEtat.actif && GarminEtat.pret && !GarminEtat.masque ? GarminEtat.widgetsActifs : []
                    Loader {
                        width: contenu.width
                        property string widgetId: modelData
                        sourceComponent: {
                            if (widgetId === "body_battery") return carteBodyBattery
                            if (widgetId === "frequence_cardiaque") return carteCoeur
                            if (widgetId === "sommeil") return carteSommeil
                            if (widgetId === "stress") return carteStress
                            if (widgetId === "pas") return cartePas
                            if (widgetId === "vfc") return carteVfc
                            if (widgetId === "activite") return carteActivite
                            if (widgetId === "calories") return carteCalories
                            if (widgetId === "oxygene") return carteOxygene
                            if (widgetId === "forme") return carteForme
                            if (widgetId === "hydratation") return carteHydratation
                            return null
                        }
                    }
                }

                // Message d'erreur éventuel
                Texte {
                    objectName: "nc-garmin-erreur"
                    visible: GarminEtat.erreur !== ""
                    width: parent.width; wrapMode: Text.Wrap
                    color: Couleurs.orange; font.pixelSize: 12
                    text: GarminEtat.erreur
                }
            }
        }
    }

    // ── CARTES DÉTAILLÉES ──
    Component {
        id: carteBodyBattery
        CarteBento {
            Row {
                width: parent.width
                Column {
                    width: parent.width * 0.65; spacing: 2
                    Row {
                        spacing: 8
                        Ico { nom: "bolt"; taille: 18; color: "#00a8e8"; anchors.verticalCenter: parent.verticalCenter }
                        Texte { text: "Body Battery"; font.pixelSize: 16; font.weight: Font.Bold }
                    }
                    Texte {
                        secondaire: true; font.pixelSize: 12
                        text: Reglages.t("Réserve d'énergie corporelle", "Body energy reserve")
                    }
                }
                Texte {
                    width: parent.width * 0.35; horizontalAlignment: Text.AlignRight; anchors.verticalCenter: parent.verticalCenter
                    text: garmin.a(garmin.m.body_battery) ? (garmin.m.body_battery + " / 100") : "—"
                    font.pixelSize: 22; font.weight: Font.Bold; color: garmin.a(garmin.m.body_battery) ? "#00a8e8" : Couleurs.texteSec
                }
            }
            CourbeBento {
                visible: (garmin.m.bb_serie || []).length >= 2
                width: parent.width; points: garmin.m.bb_serie || []; teinte: "#00a8e8"; minVal: 0; maxVal: 100
            }
        }
    }

    Component {
        id: carteCoeur
        CarteBento {
            Row {
                width: parent.width
                Column {
                    width: parent.width * 0.65; spacing: 2
                    Row {
                        spacing: 8
                        Ico { nom: "favorite"; taille: 18; color: "#ff375f"; anchors.verticalCenter: parent.verticalCenter }
                        Texte { text: Reglages.t("Fréquence cardiaque", "Heart Rate"); font.pixelSize: 16; font.weight: Font.Bold }
                    }
                    Texte {
                        secondaire: true; font.pixelSize: 12
                        text: Reglages.t("Repos : ", "Resting: ") + garmin.valOu(garmin.m.fc_repos, " bpm")
                              + " · Max : " + garmin.valOu(garmin.m.fc_max, " bpm")
                    }
                }
                Texte {
                    width: parent.width * 0.35; horizontalAlignment: Text.AlignRight; anchors.verticalCenter: parent.verticalCenter
                    text: garmin.valOu(garmin.fcCourante(), " bpm")
                    font.pixelSize: 24; font.weight: Font.Bold; color: garmin.a(garmin.fcCourante()) ? "#ff375f" : Couleurs.texteSec
                }
            }
            CourbeBento {
                visible: (garmin.m.fc_serie || []).length >= 2
                width: parent.width; points: garmin.m.fc_serie || []; teinte: "#ff375f"
            }
        }
    }

    Component {
        id: carteSommeil
        CarteBento {
            readonly property int totS: Math.max(1, (garmin.m.sommeil_profond_s || 0) + (garmin.m.sommeil_leger_s || 0) + (garmin.m.sommeil_paradoxal_s || 0) + (garmin.m.sommeil_eveil_s || 0))
            readonly property bool aPhases: (garmin.m.sommeil_profond_s || 0) + (garmin.m.sommeil_leger_s || 0) + (garmin.m.sommeil_paradoxal_s || 0) > 0
            Row {
                width: parent.width
                Column {
                    width: parent.width * 0.62; spacing: 2
                    Row {
                        spacing: 8
                        Ico { nom: "bedtime"; taille: 18; color: "#bf5af2"; anchors.verticalCenter: parent.verticalCenter }
                        Texte { text: Reglages.t("Sommeil de la dernière nuit", "Last Night's Sleep"); font.pixelSize: 16; font.weight: Font.Bold }
                    }
                    Texte {
                        secondaire: true; font.pixelSize: 12
                        text: Reglages.t("Durée : ", "Duration: ") + garmin.heures(garmin.m.sommeil_s)
                              + (garmin.a(garmin.m.spo2) ? (" · SpO2 " + garmin.m.spo2 + "%") : "")
                    }
                }
                Texte {
                    width: parent.width * 0.38; horizontalAlignment: Text.AlignRight; anchors.verticalCenter: parent.verticalCenter
                    text: garmin.a(garmin.m.sommeil_score) ? (Reglages.t("Score ", "Score ") + garmin.m.sommeil_score + "/100") : "—"
                    font.pixelSize: 21; font.weight: Font.Bold; color: garmin.a(garmin.m.sommeil_score) ? "#bf5af2" : Couleurs.texteSec
                }
            }
            Row {
                visible: aPhases
                width: parent.width; height: 14; spacing: 3
                Rectangle { width: Math.max(8, (parent.width - 9) * ((garmin.m.sommeil_profond_s || 0) / totS)); height: parent.height; radius: 6; color: "#3a5fcd" }
                Rectangle { width: Math.max(8, (parent.width - 9) * ((garmin.m.sommeil_leger_s || 0) / totS)); height: parent.height; radius: 6; color: "#5ac8fa" }
                Rectangle { width: Math.max(8, (parent.width - 9) * ((garmin.m.sommeil_paradoxal_s || 0) / totS)); height: parent.height; radius: 6; color: "#bf5af2" }
                Rectangle { width: Math.max(6, (parent.width - 9) * Math.max(0.02, (garmin.m.sommeil_eveil_s || 0) / totS)); height: parent.height; radius: 6; color: Couleurs.orange }
            }
            Flow {
                visible: aPhases
                width: parent.width; spacing: 16
                Row { spacing: 6; Rectangle { width: 10; height: 10; radius: 5; color: "#3a5fcd"; anchors.verticalCenter: parent.verticalCenter }
                      Texte { font.pixelSize: 12; text: Reglages.t("Profond : ", "Deep: ") + garmin.heures(garmin.m.sommeil_profond_s) } }
                Row { spacing: 6; Rectangle { width: 10; height: 10; radius: 5; color: "#5ac8fa"; anchors.verticalCenter: parent.verticalCenter }
                      Texte { font.pixelSize: 12; text: Reglages.t("Léger : ", "Light: ") + garmin.heures(garmin.m.sommeil_leger_s) } }
                Row { spacing: 6; Rectangle { width: 10; height: 10; radius: 5; color: "#bf5af2"; anchors.verticalCenter: parent.verticalCenter }
                      Texte { font.pixelSize: 12; text: "REM : " + garmin.heures(garmin.m.sommeil_paradoxal_s) } }
                Row { spacing: 6; Rectangle { width: 10; height: 10; radius: 5; color: Couleurs.orange; anchors.verticalCenter: parent.verticalCenter }
                      Texte { font.pixelSize: 12; text: Reglages.t("Éveil : ", "Awake: ") + Math.round((garmin.m.sommeil_eveil_s || 0) / 60) + "m" } }
            }
        }
    }

    Component {
        id: carteStress
        CarteBento {
            Row {
                width: parent.width
                Column {
                    width: parent.width * 0.65; spacing: 2
                    Row {
                        spacing: 8
                        Ico { nom: "self_improvement"; taille: 18; color: Couleurs.vert; anchors.verticalCenter: parent.verticalCenter }
                        Texte { text: Reglages.t("Stress de la journée", "Daily Stress"); font.pixelSize: 16; font.weight: Font.Bold }
                        Texte { visible: garmin.a(garmin.m.stress_moyen); anchors.verticalCenter: parent.verticalCenter; text: "· " + garmin.qualStress(garmin.m.stress_moyen); secondaire: true; font.pixelSize: 13 }
                    }
                    Texte { secondaire: true; font.pixelSize: 12; text: Reglages.t("Niveau moyen sur la journée", "Daily average level") }
                }
                Texte {
                    width: parent.width * 0.35; horizontalAlignment: Text.AlignRight; anchors.verticalCenter: parent.verticalCenter
                    text: garmin.a(garmin.m.stress_moyen) ? (garmin.m.stress_moyen + " / 100") : "—"
                    font.pixelSize: 22; font.weight: Font.Bold
                    color: !garmin.a(garmin.m.stress_moyen) ? Couleurs.texteSec : ((garmin.m.stress_moyen || 0) < 30 ? Couleurs.vert : Couleurs.orange)
                }
            }
            CourbeBento {
                visible: (garmin.m.stress_serie || []).length >= 2
                width: parent.width; height: 54; points: garmin.m.stress_serie || []
                teinte: (garmin.m.stress_moyen || 0) < 30 ? Couleurs.vert : Couleurs.orange
                minVal: 0; maxVal: 100
            }
        }
    }

    Component {
        id: cartePas
        CarteBento {
            readonly property real ratio: garmin.m.pas_objectif && garmin.a(garmin.m.pas) ? Math.min(1, garmin.m.pas / garmin.m.pas_objectif) : 0
            Row {
                width: parent.width
                Column {
                    width: parent.width * 0.62; spacing: 2
                    Row {
                        spacing: 8
                        Ico { nom: "directions_walk"; taille: 18; color: Couleurs.vert; anchors.verticalCenter: parent.verticalCenter }
                        Texte { text: Reglages.t("Pas & Distance du jour", "Daily Steps & Distance"); font.pixelSize: 16; font.weight: Font.Bold }
                    }
                    Texte {
                        secondaire: true; font.pixelSize: 12
                        text: Reglages.t("Objectif : ", "Goal: ") + garmin.nb(garmin.m.pas_objectif) + " " + Reglages.t("pas", "steps")
                              + (garmin.a(garmin.m.distance_m) ? (" · " + (garmin.m.distance_m / 1000).toFixed(2).replace(/\.00$/, "") + " km") : "")
                    }
                }
                Texte {
                    width: parent.width * 0.38; horizontalAlignment: Text.AlignRight; anchors.verticalCenter: parent.verticalCenter
                    text: garmin.valOu(garmin.m.pas, " " + Reglages.t("pas", "steps"))
                    font.pixelSize: 22; font.weight: Font.Bold; color: garmin.a(garmin.m.pas) ? Couleurs.vert : Couleurs.texteSec
                }
            }
            Rectangle {
                width: parent.width; height: 10; radius: 5; color: Couleurs.gris3
                Rectangle { width: Math.round(parent.width * ratio); height: parent.height; radius: 5; color: Couleurs.vert }
            }
        }
    }

    Component {
        id: carteVfc
        CarteBento {
            Row {
                width: parent.width
                Row { width: parent.width * 0.65; spacing: 8; Ico { nom: "monitor_heart"; taille: 18; color: Couleurs.vert; anchors.verticalCenter: parent.verticalCenter }
                      Texte { text: Reglages.t("VFC de nuit (HRV)", "Overnight HRV"); font.pixelSize: 16; font.weight: Font.Bold } }
                Texte { width: parent.width * 0.35; horizontalAlignment: Text.AlignRight; text: garmin.valOu(garmin.m.vfc_nuit, " ms"); font.pixelSize: 22; font.weight: Font.Bold; color: garmin.a(garmin.m.vfc_nuit) ? Couleurs.vert : Couleurs.texteSec }
            }
        }
    }

    Component {
        id: carteActivite
        CarteBento {
            Row {
                width: parent.width
                Column {
                    width: parent.width * 0.65; spacing: 2
                    Row { spacing: 8; Ico { nom: "directions_run"; taille: 18; color: "#00a8e8"; anchors.verticalCenter: parent.verticalCenter }
                          Texte { text: garmin.m.activite_nom || Reglages.t("Dernière activité", "Last activity"); font.pixelSize: 16; font.weight: Font.Bold } }
                    Texte { secondaire: true; font.pixelSize: 12; text: Reglages.t("Dernière séance enregistrée", "Latest recorded workout") }
                }
                Texte { width: parent.width * 0.35; horizontalAlignment: Text.AlignRight; anchors.verticalCenter: parent.verticalCenter
                        text: garmin.valOu(garmin.m.activite_minutes, " min"); font.pixelSize: 20; font.weight: Font.Bold; color: garmin.a(garmin.m.activite_minutes) ? "#00a8e8" : Couleurs.texteSec }
            }
        }
    }

    Component {
        id: carteCalories
        CarteBento {
            Row {
                width: parent.width
                Column {
                    width: parent.width * 0.65; spacing: 2
                    Row { spacing: 8; Ico { nom: "local_fire_department"; taille: 18; color: Couleurs.orange; anchors.verticalCenter: parent.verticalCenter }
                          Texte { text: Reglages.t("Calories, Étages & Minutes intenses", "Calories, Floors & Intensity Minutes"); font.pixelSize: 16; font.weight: Font.Bold } }
                    Texte { secondaire: true; font.pixelSize: 12; text: Reglages.t("Étages : ", "Floors: ") + garmin.nb(garmin.m.etages) + " · " + Reglages.t("Minutes intenses : ", "Intensity min: ") + garmin.nb(garmin.m.minutes_intenses) }
                }
                Texte { width: parent.width * 0.35; horizontalAlignment: Text.AlignRight; anchors.verticalCenter: parent.verticalCenter
                        text: garmin.valOu(garmin.m.calories_actives, " kcal"); font.pixelSize: 22; font.weight: Font.Bold; color: garmin.a(garmin.m.calories_actives) ? Couleurs.orange : Couleurs.texteSec }
            }
        }
    }

    Component {
        id: carteOxygene
        CarteBento {
            Row {
                width: parent.width
                Column {
                    width: parent.width * 0.65; spacing: 2
                    Row { spacing: 8; Ico { nom: "air"; taille: 18; color: "#5ac8fa"; anchors.verticalCenter: parent.verticalCenter }
                          Texte { text: Reglages.t("SpO2 & Respiration", "SpO2 & Respiration"); font.pixelSize: 16; font.weight: Font.Bold } }
                    Texte { secondaire: true; font.pixelSize: 12; text: Reglages.t("Respiration : ", "Respiration: ") + garmin.valOu(garmin.m.respiration, " brpm") }
                }
                Texte { width: parent.width * 0.35; horizontalAlignment: Text.AlignRight; anchors.verticalCenter: parent.verticalCenter
                        text: garmin.valOu(garmin.m.spo2, " % SpO2"); font.pixelSize: 22; font.weight: Font.Bold; color: garmin.a(garmin.m.spo2) ? "#5ac8fa" : Couleurs.texteSec }
            }
        }
    }

    Component {
        id: carteForme
        CarteBento {
            Row {
                width: parent.width
                Column {
                    width: parent.width * 0.65; spacing: 2
                    Row { spacing: 8; Ico { nom: "emoji_events"; taille: 18; color: "#bf5af2"; anchors.verticalCenter: parent.verticalCenter }
                          Texte { text: Reglages.t("VO2 Max & Disponibilité", "VO2 Max & Readiness"); font.pixelSize: 16; font.weight: Font.Bold } }
                    Texte { secondaire: true; font.pixelSize: 12; text: "VO2 Max : " + garmin.nb(garmin.m.vo2max) }
                }
                Texte { width: parent.width * 0.35; horizontalAlignment: Text.AlignRight; anchors.verticalCenter: parent.verticalCenter
                        text: garmin.a(garmin.m.readiness) ? (garmin.m.readiness + " / 100") : "—"; font.pixelSize: 22; font.weight: Font.Bold; color: garmin.a(garmin.m.readiness) ? "#bf5af2" : Couleurs.texteSec }
            }
        }
    }

    Component {
        id: carteHydratation
        CarteBento {
            Row {
                width: parent.width
                Column {
                    width: parent.width - actionsEau.width - 12; spacing: 2
                    Row { spacing: 8; Ico { nom: "water_drop"; taille: 18; color: "#00a8e8"; anchors.verticalCenter: parent.verticalCenter }
                          Texte { text: Reglages.t("Hydratation", "Hydration"); font.pixelSize: 16; font.weight: Font.Bold } }
                    Texte { secondaire: true; font.pixelSize: 12; text: garmin.nb(garmin.m.hydratation_ml) + " ml" }
                }
                Row {
                    id: actionsEau
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6
                    BoutonPilule { texte: "+250 ml"; icone: "add"; teinte: "#00a8e8"; onClic: GarminEtat.hydrater("250") }
                    BoutonPilule { texte: "+500 ml"; icone: "water_full"; teinte: "#00a8e8"; onClic: GarminEtat.hydrater("500") }
                }
            }
        }
    }
}
