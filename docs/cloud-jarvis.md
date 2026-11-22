# Cloud JARVIS distant

Le cloud est une option du serveur distant JARVIS BIS. Il reste désactivé lorsque JARVIS tourne en mode local sur ce PC. Le serveur doit fournir le contrat cloud v1 ; un ancien serveur reste utilisable pour le chat.

## Envoyer directement à un autre appareil

Ouvre le Cloud sur les deux PC. Clique sur **Partage de proximité** pour agrandir la fenêtre sous la barre. Le Cloud apparaît à gauche et **Partage entre appareils** à droite. Un second clic sur **Partage de proximité** rétablit le format initial. Sur un écran étroit, le partage occupe la largeur disponible sous le même en-tête. Garde la fenêtre ouverte pendant le transfert. Un second clic sur le nuage de l’île referme le panneau. Dans l’île, **Wi-Fi → Appairer un appareil** ouvre le partage réseau et **Bluetooth → Appairer un appareil** ouvre le partage radio.

| Situation | Connexion à choisir |
| --- | --- |
| Deux PC proches, chacun sur son Wi-Fi | **Bluetooth direct**. Active le Bluetooth classique sur les deux machines. Saisis l’adresse Bluetooth affichée par l’autre PC ou recherche un appareil rendu visible dans les réglages Bluetooth. Accepte la demande d’association du système si elle apparaît. |
| Deux PC proches, sans réseau commun, pour un gros fichier | **Wi-Fi Direct → Rechercher à proximité** sur les deux PC. Clique sur **Relier** en face de l’autre PC sur chaque écran. Après établissement du lien, choisis son adresse détectée ou recopie son IPv4 en 169.254.x.x. Les deux cartes et leurs pilotes doivent prendre en charge le mode P2P. |
| Deux PC déjà sur le même réseau | **Réseau IP**. Choisis l’appareil détecté ou saisis son adresse IP. |
| Deux PC éloignés | **Réseau IP**. Saisis une IPv4 ou une IPv6 joignable du destinataire. Un VPN entre pairs convient aussi. Une connexion entrante TCP sur le port 43827 doit pouvoir atteindre le destinataire. Derrière deux NAT sans route entrante, il faut d’abord établir cette route. |

Clique sur **Appairer un appareil**, compare le code et confirme sur les deux écrans. L’association est liée à l’identité de la machine. Lors d’un changement de transport, tu peux directement sélectionner ou saisir sa nouvelle adresse et choisir **Choisir les fichiers…**, puis **Envoyer**. Chaque fichier est soumis à l’accord du destinataire et arrive dans le dossier **Noctalia** de ses téléchargements. Dans Nautilus, **Scripts → Envoyer à un appareil** transmet la sélection à la fenêtre.

Le protocole Noctalia utilise TLS 1.3 sur une liaison TCP ou Bluetooth classique RFCOMM (canal 22). La découverte IP utilise des annonces UDP locales sur le port 43827. Wi-Fi Direct utilise un groupe P2P NetworkManager, des adresses locales au lien et un profil volatile lié à la durée de vie du panneau. Selon le matériel, le maintien du Wi-Fi habituel pendant la liaison peut varier.

## Activer le cloud distant

Dans les réglages « Agents IA (coucou) », ouvrir « Cloud JARVIS distant », associer le PC puis activer « Cloud JARVIS dans la barre ». Le jeton de cet appareil est enregistré dans le trousseau de session, séparément de la clé générale JARVIS.

Commandes :

```bash
nc-cloud associer
nc-reglages set CLOUD_JARVIS oui
nc-cloud fenetre
nc-cloud ouvrir
```

Le client Python de transferts utilise la bibliothèque standard. L’association nécessite `secret-tool` et un trousseau Secret Service déverrouillé. L’accès dans Fichiers nécessite Gio Python et le backend WebDAV de GVfs. Aucun moteur de conteneurs n’est nécessaire sur le poste client.

## Utiliser

Déposer jusqu’à 8 fichiers locaux sur l’île ou dans la fenêtre, ou cliquer « Importer des fichiers… » pour ouvrir le sélecteur du système (sélection multiple). Dans la fenêtre, parcourir les dossiers, éventuellement créer un dossier, puis cliquer « Envoyer ici ». Annuler le sélecteur conserve la sélection précédente. Les sources sont copiées et restent sur le PC. La progression et le résultat sont affichés par fichier ; fermer la fenêtre ne stoppe pas le processus d’envoi. La liste et le quota sont actualisés automatiquement lorsqu’un transfert est enregistré sur le serveur, même si l’envoi s’est terminé avant sa première lecture dans la fenêtre.

Un clic sélectionne un élément et affiche les actions ; un double-clic ouvre un dossier ou télécharge une copie privée vérifiée du fichier avant de lancer son application. Les modifications de cette copie doivent être envoyées à nouveau pour être publiées. La fenêtre permet de créer, renommer, déplacer et supprimer des fichiers ou dossiers, avec aperçu et confirmation avant suppression. Pour déplacer un élément directement dans la liste, le glisser sur un dossier ; le déposer sur la flèche ↑ le déplace au niveau supérieur sans quitter le dossier courant. Un dossier peut être déplacé avec son contenu. Les noms occupés et les cycles sont refusés par le serveur ; les déplacements transmettent les révisions affichées et ne sont pas mis en attente hors ligne.

Le bouton « Ouvrir dans Fichiers » monte le drive à la demande et ajoute le favori « Cloud JARVIS » au gestionnaire GTK. `Super + E` continue d’ouvrir le gestionnaire choisi. L’accès natif permet l’écriture lorsque le serveur annonce `webdav=read_write` (option serveur explicite `CLOUD_DAV_WRITE=1`), sinon il reste en lecture seule. Remonter le drive après un changement de ce mode. Les applications compatibles peuvent enregistrer directement via DAV ; leur prise en charge des révisions dépend de l’application. Nautilus dispose aussi de « Scripts → Envoyer vers Cloud JARVIS ». Pour un autre gestionnaire, `nc-cloud deposer FICHIER…` ouvre le même choix de destination.

L’indicateur est intégré à la pilule de l’île, uniquement si le cloud est activé et configuré. La fenêtre conserve l’écran sur lequel elle a été ouverte lorsque le pointeur passe sur un autre moniteur.

## Hors ligne et conflits

Hors ligne, le dépôt est refusé avec un message. Aucun fichier n’est mis dans une file d’envoi différé. Un transfert commencé puis interrompu reste dans l’historique privé ; « Reprendre / vérifier » consulte son état sur le serveur avant de renvoyer quoi que ce soit.

Si la source a changé, déposer de nouveau le fichier. Si la destination existe ou si un autre PC l’a modifiée, choisir « Conserver les deux », « Remplacer » ou « Annuler ». Le remplacement vérifie la révision distante ; une seconde modification peut donc provoquer un nouveau conflit. La résolution renvoie actuellement les morceaux depuis la source locale.

Un changement de serveur ou d’appareil interdit la réutilisation d’un ancien transfert. Le favori et le montage de l’ancienne connexion sont retirés lors de la prochaine vérification cloud. Aucune suppression ou modification de fichiers du serveur n’est déclenchée par une désactivation de l’icône.

Les manifestes sont privés, sous `$XDG_STATE_HOME/nc-cloud/` (ou `~/.local/state/nc-cloud/`), séparés par adresse de serveur. Ils contiennent les chemins des sources nécessaires à une reprise, sans leur contenu ni leurs jetons. Les 100 transferts les plus récents sont affichés. Le bouton « Effacer les terminés » retire immédiatement les entrées enregistrées, annulées ou expirées ; elles sont aussi nettoyées automatiquement après 24 heures lors de la lecture des transferts. Les envois en cours, interrompus ou en conflit sont conservés. Ce nettoyage local fonctionne hors ligne et ne supprime aucun fichier source ni aucun fichier du cloud. Une entrée encore verrouillée par un worker est conservée jusqu’à la fin de celui-ci.

## Vérifier

```bash
python3 -B -m unittest tests.test_cloud -v
NC_CLOUD_QML=1 python3 -B -m unittest tests.test_cloud_qml -v
```

Les tests client utilisent un serveur HTTP simulé et un faux trousseau. Les tests QML, facultatifs en session Wayland avec Quickshell, ouvrent une fenêtre isolée : rendu, file de requêtes, rafraîchissement après transfert, déplacements par gestes QtTest vers un dossier puis vers le parent, et sélection/annulation d’un import. Ils n’accèdent pas au cloud personnel. Le montage GVfs nécessite une validation séparée. Le serveur et ses instructions d’installation sont livrés dans le dépôt JARVIS BIS, avec le SHA exact indiqué dans la fiche d’intégration.
