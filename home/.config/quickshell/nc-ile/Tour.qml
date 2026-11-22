// Fenêtre Tour « Tour Exemple » (Super + Alt + T, clic sur l'indicateur Tour de la pilule ou appui long / clic droit sur la tuile Tour du Centre).
// Même architecture que Vpn.qml : FloatingWindow, titre stable « Tour » (reconnu par regles.lua et automatismes.lua), verre flouté.
import QtQuick
import Quickshell

FloatingWindow {
    id: win
    signal fermer()
    title: "Tour"
    color: "transparent"
    implicitWidth: win.largeurCarte
    implicitHeight: Math.min(Math.round(win.hauteurEcran * 0.9), contenu.implicitHeight + 48)
    minimumSize: Qt.size(460, 320)
    onClosed: win.fermer()
    onVisibleChanged: if (!visible) win.fermer()

    readonly property real largeurEcran: win.screen ? win.screen.width : 1600
    readonly property real hauteurEcran: win.screen ? win.screen.height : 1000
    readonly property bool verre: Reglages.val("FENETRES_FLOU", "oui") !== "non" && !Reglages.sobre
    readonly property int largeurCarte: Math.min(880, Math.round(largeurEcran * 0.92))
    property string confirmationPower: "" // "", "veille", "redemarrer", "eteindre"

    function quitter() { win.fermer() }
    Component.onCompleted: TourEtat.panneauOuvert = true
    Component.onDestruction: TourEtat.panneauOuvert = false

    component CarteSection: Rectangle {
        default property alias enfants: colCarte.data
        width: parent.width
        height: colCarte.implicitHeight + 36
        radius: 22
        color: Qt.alpha(Qt.tint(Couleurs.fond, Qt.alpha(Couleurs.texte, 0.08)), 0.85)
        border.width: 1
        border.color: Qt.alpha(Couleurs.texte, 0.09)
        Column {
            id: colCarte
            x: 20; y: 18
            width: parent.width - 40
            spacing: 12
        }
    }

    component BoutonAction: Rectangle {
        id: btn
        property string texte: ""
        property string sousTexte: ""
        property string icone: ""
        property color teinte: Couleurs.accent
        property bool accentPlein: false
        property bool actif: true
        signal clic()

        height: sousTexte !== "" ? 56 : 40
        radius: sousTexte !== "" ? 16 : 20
        opacity: actif && !TourEtat.occupe ? 1 : 0.45
        color: accentPlein
               ? (zoneBtn.containsMouse ? Qt.lighter(teinte, 1.1) : teinte)
               : (zoneBtn.containsMouse ? Qt.alpha(teinte, 0.26) : Qt.alpha(Couleurs.carte, 0.65))
        border.width: 1
        border.color: accentPlein ? "transparent" : Qt.alpha(teinte, zoneBtn.containsMouse ? 0.55 : 0.22)
        Behavior on color { enabled: !Reglages.sobre; ColorAnimation { duration: 120 } }

        Row {
            anchors.centerIn: btn.sousTexte === "" ? parent : undefined
            anchors.left: btn.sousTexte !== "" ? parent.left : undefined
            anchors.leftMargin: btn.sousTexte !== "" ? 14 : 0
            anchors.verticalCenter: parent.verticalCenter
            spacing: 10
            Ico {
                visible: btn.icone !== ""
                anchors.verticalCenter: parent.verticalCenter
                nom: btn.icone
                taille: btn.sousTexte !== "" ? 22 : 17
                color: btn.accentPlein ? Couleurs.surAccent : btn.teinte
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1
                Texte {
                    text: btn.texte
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    color: btn.accentPlein ? Couleurs.surAccent : Couleurs.texte
                }
                Texte {
                    visible: btn.sousTexte !== ""
                    text: btn.sousTexte
                    font.pixelSize: 11
                    secondaire: !btn.accentPlein
                    color: btn.accentPlein ? Qt.alpha(Couleurs.surAccent, 0.85) : Couleurs.texteSec
                }
            }
        }
        MouseArea {
            id: zoneBtn
            anchors.fill: parent
            hoverEnabled: true
            enabled: btn.actif && !TourEtat.occupe
            onClicked: btn.clic()
        }
        Accessible.role: Accessible.Button
        Accessible.name: btn.texte
    }

    Item {
        id: racineCarte
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: win.quitter()

        Rectangle {
            anchors.fill: parent
            color: Qt.alpha(Couleurs.fond, win.verre ? 0.62 : 0.92)
        }

        Flickable {
            id: defile
            anchors.fill: parent
            anchors.margins: 1
            contentWidth: width
            contentHeight: contenu.implicitHeight + 48
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            flickableDirection: Flickable.VerticalFlick

            Column {
                id: contenu
                x: 26; y: 24
                width: defile.width - 52
                spacing: 14

                // ── 1. En-tête ──
                Item {
                    width: parent.width; height: 52
                    Column {
                        anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                        spacing: 2
                        Texte {
                            text: Reglages.t("Tour Exemple", "Example Tower")
                            font.pixelSize: 24; font.weight: Font.Bold
                        }
                        Texte {
                            text: Reglages.t("i5-14600KF · Radeon RX 7800 XT (16 Go) · Sunshine & Ollama",
                                             "i5-14600KF · Radeon RX 7800 XT (16 GB) · Sunshine & Ollama")
                            secondaire: true; font.pixelSize: 13
                        }
                    }
                    Row {
                        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                        spacing: 8
                        BoutonAction {
                            width: 110; height: 32; radius: 16
                            texte: Reglages.t("Actualiser", "Refresh")
                            icone: "refresh"
                            onClic: TourEtat.rafraichir()
                        }
                        BoutonAction {
                            width: 96; height: 32; radius: 16
                            texte: Reglages.t("Fermer", "Close")
                            onClic: win.quitter()
                        }
                    }
                }

                // ── 2. Carte principale : État, Réseau & Alimentation (Wake-on-LAN / Veille / Arrêt) ──
                CarteSection {
                    Item {
                        width: parent.width; height: 38
                        Row {
                            anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                            spacing: 10
                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 12; height: 12; radius: 6
                                color: TourEtat.enStream ? Couleurs.accent : (TourEtat.enLigne ? Couleurs.vert : Couleurs.gris4)
                            }
                            Texte {
                                anchors.verticalCenter: parent.verticalCenter
                                font.pixelSize: 18; font.weight: Font.Bold
                                text: TourEtat.enStream
                                      ? Reglages.t("En stream sur ce portable", "Streaming on this laptop")
                                      : (TourEtat.enLigne
                                         ? Reglages.t("Allumée · Prête", "Online · Ready") + (TourEtat.pingMs > 0 ? " · " + TourEtat.pingMs + " ms" : "")
                                         : Reglages.t("Hors ligne / Éteinte", "Offline / Powered off"))
                            }
                        }
                        Row {
                            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                            spacing: 8
                            BoutonAction {
                                visible: !TourEtat.enLigne
                                width: 185; height: 36; radius: 18
                                icone: "power_settings_new"
                                texte: Reglages.t("Réveiller (WoL)", "Wake up (WoL)")
                                teinte: Couleurs.vert
                                accentPlein: true
                                onClic: TourEtat.reveiller()
                            }
                            BoutonAction {
                                visible: TourEtat.enLigne
                                width: 110; height: 34; radius: 17
                                icone: "bedtime"
                                texte: Reglages.t("Veille", "Sleep")
                                teinte: Couleurs.orange
                                onClic: win.confirmationPower = (win.confirmationPower === "veille" ? "" : "veille")
                            }
                            BoutonAction {
                                visible: TourEtat.enLigne
                                width: 130; height: 34; radius: 17
                                icone: "restart_alt"
                                texte: Reglages.t("Redémarrer", "Reboot")
                                teinte: Couleurs.orange
                                onClic: win.confirmationPower = (win.confirmationPower === "redemarrer" ? "" : "redemarrer")
                            }
                            BoutonAction {
                                visible: TourEtat.enLigne
                                width: 115; height: 34; radius: 17
                                icone: "power_settings_new"
                                texte: Reglages.t("Éteindre", "Shut down")
                                teinte: Couleurs.rouge
                                onClic: win.confirmationPower = (win.confirmationPower === "eteindre" ? "" : "eteindre")
                            }
                        }
                    }

                    // Bandeau de confirmation avant veille/redémarrage/arrêt
                    Rectangle {
                        visible: win.confirmationPower !== ""
                        width: parent.width; height: 48; radius: 14
                        color: Qt.alpha(Couleurs.rouge, 0.14)
                        border.width: 1; border.color: Qt.alpha(Couleurs.rouge, 0.4)
                        Row {
                            anchors.left: parent.left; anchors.leftMargin: 14; anchors.verticalCenter: parent.verticalCenter
                            spacing: 8
                            Ico { nom: "warning"; taille: 18; color: Couleurs.orange; anchors.verticalCenter: parent.verticalCenter }
                            Texte {
                                anchors.verticalCenter: parent.verticalCenter
                                font.pixelSize: 13; font.weight: Font.DemiBold
                                text: win.confirmationPower === "veille"
                                      ? Reglages.t("Mettre la tour en veille ?", "Put the tower to sleep?")
                                      : (win.confirmationPower === "redemarrer"
                                         ? Reglages.t("Redémarrer la tour maintenant ?", "Reboot the tower now?")
                                         : Reglages.t("Éteindre complètement la tour ?", "Shut down the tower completely?"))
                            }
                        }
                        Row {
                            anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter
                            spacing: 8
                            BoutonAction {
                                width: 110; height: 32; radius: 16
                                texte: Reglages.t("Confirmer", "Confirm")
                                teinte: Couleurs.rouge; accentPlein: true
                                onClic: {
                                    var act = win.confirmationPower
                                    win.confirmationPower = ""
                                    if (act === "veille") TourEtat.mettreEnVeille()
                                    else if (act === "redemarrer") TourEtat.redemarrer()
                                    else if (act === "eteindre") TourEtat.eteindre()
                                }
                            }
                            BoutonAction {
                                width: 96; height: 32; radius: 16
                                texte: Reglages.t("Annuler", "Cancel")
                                onClic: win.confirmationPower = ""
                            }
                        }
                    }

                    // Statistiques rapides & Télémétrie (CPU / GPU / VRAM / Réseau)
                    Flow {
                        width: parent.width; spacing: 26
                        VpnStat {
                            titre: Reglages.t("Réseau Tailscale", "Tailscale network")
                            valeur: !TourEtat.enLigne
                                    ? Reglages.t("Hors ligne", "Offline")
                                    : (TourEtat.modeReseau === "direct" ? "Direct (" + TourEtat.ip + ")"
                                       : (TourEtat.modeReseau === "relais" ? "Relais DERP (" + TourEtat.relais + ")" : TourEtat.ip))
                        }
                        VpnStat {
                            visible: TourEtat.enLigne
                            titre: "CPU (i5-14600KF)"
                            valeur: (TourEtat.cpuPct >= 0 ? TourEtat.cpuPct + " %" : "…")
                                    + (TourEtat.cpuTemp > 0 ? " · " + TourEtat.cpuTemp + " °C" : "")
                        }
                        VpnStat {
                            visible: TourEtat.enLigne
                            titre: "GPU (RX 7800 XT)"
                            valeur: (TourEtat.gpuPct >= 0 ? TourEtat.gpuPct + " %" : "…")
                                    + (TourEtat.gpuTemp > 0 ? " · " + TourEtat.gpuTemp + " °C" : "")
                        }
                        VpnStat {
                            visible: TourEtat.enLigne
                            titre: "VRAM (16 Go)"
                            valeur: TourEtat.vramUtiliseeGo >= 0 ? TourEtat.vramUtiliseeGo + " / " + TourEtat.vramTotaleGo + " Go" : "…"
                        }
                        VpnStat {
                            visible: TourEtat.enLigne
                            titre: "RAM (32 Go)"
                            valeur: TourEtat.ramUtiliseeGo >= 0 ? TourEtat.ramUtiliseeGo + " / " + TourEtat.ramTotaleGo + " Go" : "…"
                        }
                    }
                }

                // ── 3. Streaming Moonlight + Mode d'écran (Principal vs 2e écran virtuel) ──
                CarteSection {
                    Item {
                        width: parent.width; height: 28
                        Texte {
                            anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                            text: Reglages.t("Streaming Bureau & Jeux (Sunshine / Moonlight)", "Desktop & Game Streaming (Sunshine / Moonlight)")
                            font.pixelSize: 16; font.weight: Font.Bold
                        }
                        BoutonAction {
                            visible: TourEtat.enStream || TourEtat.ecranVirtuel
                            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                            width: 190; height: 32; radius: 16
                            icone: "stop_circle"
                            texte: Reglages.t("Couper le stream", "Stop stream")
                            teinte: Couleurs.rouge
                            onClic: TourEtat.couperStream()
                        }
                    }

                    Row {
                        width: parent.width; spacing: 10
                        BoutonAction {
                            width: (parent.width - 20) / 3
                            icone: "desktop_windows"
                            texte: Reglages.t("Bureau Principal", "Main Desktop")
                            sousTexte: Reglages.t("Écran normal de la tour", "Tower main display")
                            teinte: Couleurs.accent
                            accentPlein: true
                            actif: TourEtat.enLigne
                            onClic: { TourEtat.lancerStream("Desktop", "principal"); win.quitter() }
                        }
                        BoutonAction {
                            width: (parent.width - 20) / 3
                            icone: "Multiple_stop"
                            texte: Reglages.t("Écran Virtuel (Turquie)", "Virtual Display (Turkey)")
                            sousTexte: Reglages.t("Écran headless + coupe écran tour", "Headless display + tower screen off")
                            teinte: Couleurs.violet
                            actif: TourEtat.enLigne
                            onClic: { TourEtat.lancerStream("Desktop", "virtuel"); win.quitter() }
                        }
                        BoutonAction {
                            width: (parent.width - 20) / 3
                            icone: "sports_esports"
                            texte: "Steam Big Picture"
                            sousTexte: Reglages.t("Interface manette / Jeux", "Gamepad UI / Games")
                            teinte: Couleurs.orange
                            actif: TourEtat.enLigne
                            onClic: { TourEtat.lancerStream("Steam Big Picture", "principal"); win.quitter() }
                        }
                    }

                    // Choix du profil de latence / bande passante
                    Texte {
                        text: Reglages.t("Profil d'encodage AV1 & Latence :", "AV1 Encoding & Latency Profile:")
                        secondaire: true; font.pixelSize: 12
                    }
                    Row {
                        width: parent.width; spacing: 10
                        Repeater {
                            model: TourEtat.profils
                            BoutonAction {
                                required property var modelData
                                width: (parent.width - 20) / 3
                                icone: modelData.id === TourEtat.profil ? "check_circle" : "tune"
                                texte: modelData.nom
                                sousTexte: modelData.detail
                                teinte: modelData.id === TourEtat.profil ? Couleurs.vert : Couleurs.texteSec
                                onClic: TourEtat.choisirProfil(modelData.id)
                            }
                        }
                    }
                }

                // ── 4. IA Locale (Ollama RX 7800 XT) & Développement distant (SSH / Code) ──
                CarteSection {
                    Texte {
                        text: Reglages.t("IA Locale (Ollama RX 7800 XT) & Développement", "Local AI (Ollama RX 7800 XT) & Development")
                        font.pixelSize: 16; font.weight: Font.Bold
                    }
                    Texte {
                        width: parent.width; wrapMode: Text.Wrap; secondaire: true; font.pixelSize: 12
                        text: TourEtat.ollamaModeles.length > 0
                              ? Reglages.t("Modèles sur la tour : ", "Models on tower: ") + TourEtat.ollamaModeles.join(" · ")
                              : Reglages.t("Bascule nc-ia sur l'Ollama de ta tour (16 Go VRAM) ou ouvre un accès direct en SSH.",
                                           "Switch nc-ia to your tower's Ollama (16 GB VRAM) or open direct SSH access.")
                    }
                    Row {
                        width: parent.width; spacing: 10
                        BoutonAction {
                            width: (parent.width - 20) / 3
                            icone: "auto_awesome"
                            texte: TourEtat.iaTour
                                   ? Reglages.t("IA : Sur la Tour (Actif)", "AI: On Tower (Active)")
                                   : Reglages.t("IA : Sur ce Portable", "AI: On this Laptop")
                            sousTexte: TourEtat.iaTour
                                       ? "http://198.51.100.10:11434"
                                       : Reglages.t("Cliquer pour utiliser la RX 7800 XT", "Click to use RX 7800 XT")
                            teinte: TourEtat.iaTour ? Couleurs.vert : Couleurs.violet
                            onClic: TourEtat.basculerIA()
                        }
                        BoutonAction {
                            width: (parent.width - 20) / 3
                            icone: "terminal"
                            texte: Reglages.t("Terminal SSH Tour", "Tower SSH Terminal")
                            sousTexte: "kitty ssh tour"
                            teinte: Couleurs.accent
                            onClic: { TourEtat.ouvrirSsh(); win.quitter() }
                        }
                        BoutonAction {
                            width: (parent.width - 20) / 3
                            icone: "code"
                            texte: Reglages.t("Ouvrir dans Code / AGY", "Open in Code / AGY")
                            sousTexte: "Remote-SSH (tour-exemple)"
                            teinte: Couleurs.accent
                            onClic: { TourEtat.ouvrirCode(); win.quitter() }
                        }
                    }
                }

                // ── Message de retour d'action ──
                Texte {
                    visible: TourEtat.message !== ""
                    width: parent.width; wrapMode: Text.Wrap
                    color: TourEtat.erreur ? Couleurs.orange : Couleurs.vert
                    font.pixelSize: 12; font.weight: Font.DemiBold
                    text: TourEtat.message
                }

                // ── Pied de page : Rappel raccourcis ──
                Texte {
                    width: parent.width; wrapMode: Text.Wrap; secondaire: true; font.pixelSize: 11
                    text: Reglages.t("Raccourcis en stream : tous tes Super+… et le pavé tactile vont à la tour · Super+Ctrl+Alt+M bascule vers le portable · Ctrl+Alt+Maj+Q quitte Moonlight.",
                                     "Stream shortcuts: all Super+… keys go to the tower · Super+Ctrl+Alt+M switches back to laptop · Ctrl+Alt+Shift+Q quits Moonlight.")
                }
            }
        }
    }
}
