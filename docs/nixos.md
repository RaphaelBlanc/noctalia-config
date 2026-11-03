# NixOS (prototype communautaire)

Ce portage est publié sur la branche [`feat/nixos-support` du fork RaphaelBlanc/noctalia-config](https://github.com/RaphaelBlanc/noctalia-config/tree/feat/nixos-support),
pour permettre sa relecture et son adaptation. Le dépôt amont ne propose pas
encore de support officiel de NixOS ; les limites sont détaillées plus bas.

Le portage fournit un module NixOS pour les paquets, Hyprland avec UWSM, PAM
(verrouillage), les polices, le terminal et les services système du bureau.
`install.sh` conserve la détection du matériel, les sauvegardes et les fichiers
utilisateur modifiables : les réglages de l'île continuent à fonctionner.
Home Manager n'est pas nécessaire. Ne lui fais pas gérer en parallèle les fichiers
de ce dépôt (`~/.config/hypr`, `~/.config/noctalia`, `~/.zshrc`, etc.).

## Préparer le système

Il faut une installation NixOS existante, un compte utilisateur et les droits
d'administration pour reconstruire le système. Sur un poste administré par
l'école, le module doit être ajouté par l'administrateur. Rien dans ce dépôt ne
réinstalle NixOS ni ne définit les disques, le réseau de l'école ou les pilotes GPU.

Utilise **nixos-unstable** : Hyprland doit être en version **0.55 ou plus** pour
charger les fichiers Lua. Le module refuse une version plus ancienne. Noctalia
doit être en v5 (le projet `noctalia`, pas `noctalia-shell` v4).

Sur le PC NixOS, récupère la branche du fork :

```bash
nix-shell -p git
git clone -b feat/nixos-support https://github.com/RaphaelBlanc/noctalia-config.git ~/noctalia-config
```

Utilise ce clone et `./install.sh` pour le prototype. La commande d'installation
rapide du README vise le dépôt amont, qui ne contient pas encore ce portage.

Dans la flake **du système**, ajoute l'entrée locale (adapte le nom d'utilisateur) :

```nix
inputs = {
  nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  noctalia-config.url = "path:/home/TON_UTILISATEUR/noctalia-config";
  noctalia-config.inputs.nixpkgs.follows = "nixpkgs";
};
```

Puis ajoute le module dans les `modules` de ton `nixosConfigurations.<machine>` :

```nix
modules = [
  ./configuration.nix
  inputs.noctalia-config.nixosModules.default
  ({ pkgs, ... }: {
    programs.noctalia-config.enable = true;
    users.users.TON_UTILISATEUR.extraGroups = [ "networkmanager" ];
    # Facultatif : faire de zsh le shell de ce compte.
    users.users.TON_UTILISATEUR.shell = pkgs.zsh;
  })
];
```

Ces extraits supposent que la fonction `outputs` de ta flake reçoit `inputs`
(`outputs = inputs@{ self, nixpkgs, ... }: ...`). Conserve ta configuration matérielle,
ton `system.stateVersion` et ton écran de connexion existants.
Si tu n'en as pas encore, SDDM peut être activé dans `configuration.nix` :

```nix
services.displayManager.sddm.enable = true;
services.displayManager.sddm.wayland.enable = true;
```

Sans flake, `imports = [ /chemin/noctalia-config/nix/nixos.nix ];` et
`programs.noctalia-config.enable = true;` fonctionnent avec un nixpkgs récent
contenant `pkgs.noctalia` v5. La flake utilise également ce paquet précompilé,
avec la version fixée par son `flake.lock`.

Reconstruis depuis le dossier de ta configuration NixOS :

```bash
sudo nixos-rebuild switch --flake .#NOM_MACHINE
```

Le premier appel génère les entrées du `flake.lock` du système : conserve ce
fichier dans ton dépôt NixOS. Ce dépôt fournit aussi son `flake.lock`, qui fixe
les versions utilisées pour les tests. Pour vérifier le portage indépendamment,
exécute `nix flake check --all-systems` depuis `~/noctalia-config`.

## Installer les fichiers du bureau

Depuis un terminal utilisateur sur NixOS, **sans sudo** :

```bash
cd ~/noctalia-config
./install.sh
```

L'installateur détecte NixOS et utilise les paquets déclarés dans Nix. Il copie
les configs (y compris zsh et LazyVim), adapte les écrans et le clavier, sauvegarde
les fichiers remplacés et active les services utilisateur. Les unités emploient
`/run/current-system/sw/bin` au lieu de `/usr/bin`. La police de l'île vient de
Nix ; oh-my-zsh, powerlevel10k et ses plugins aussi. Les plugins LazyVim seront
téléchargés par LazyVim à la première ouverture de Neovim.
Les applications Qt utilisent le style Fusion intégré, avec la palette du bureau ;
l'OCR fournit les modèles français et anglais.

Ferme puis rouvre la session en choisissant **Hyprland (uwsm-managed)**.
UWSM transmet le PATH de la session aux services ; pas de lancement supplémentaire
de Noctalia ou de Quickshell dans un `exec-once` ou un module Home Manager.

`--files-only` reste une simple copie sans activation des services, zsh ou Neovim.
`--restore` restaure les fichiers sauvegardés ; pour retirer les paquets et services
système, désactive aussi le module et reconstruis NixOS.

## Services et mises à jour

Le module propose NetworkManager (avec OpenVPN), Bluetooth, UPower, PipeWire et
power-profiles-daemon. Si tu utilises déjà TLP, tuned ou une configuration audio
différente, désactive ces choix groupés et configure les services toi-même :

```nix
programs.noctalia-config.recommendedServices = false;
```

Les pilotes NVIDIA, le thème GRUB/Plymouth/SDDM et les assistants root
`nc-energie-root`, `nc-limite-charge`, `nc-vpn-root` ne sont pas installés par ce
portage. Leurs étapes impératives sont sautées, même avec `--oui` ;
`--seulement energie` et `--seulement killswitch` renvoient vers ce guide.
Les profils standard passent par power-profiles-daemon ; le kill switch qui
dépend de l'assistant root n'est pas disponible.

Les mises à jour du système se font avec ta configuration NixOS et
`nixos-rebuild` ; le compteur de paquets de l'île ne compte pas les générations
NixOS. Il ne sélectionne pas dnf/apt/pacman même si tu les as dans ton PATH.
Avec le clone du fork ci-dessus, `nc-maj` suit la branche distante
`origin/feat/nixos-support`. Les nouveautés du dépôt amont doivent d'abord être
intégrées à cette branche du fork, puis testées avec le portage.

Pour mettre à jour les dépendances, actualise le lock de ta flake système puis
reconstruis. Avec une entrée `path:`, actualise aussi cette entrée après chaque
changement du module local (`nix flake update noctalia-config`).

## Vérifications

```bash
nc-diag
systemctl --user status noctalia.service nc-ile.service hypridle.service
journalctl --user -b -u noctalia.service -u nc-ile.service
```

Depuis Fedora, les tests `python3 -m unittest tests.test_nixos` contrôlent les
gardes NixOS et le rendu des fichiers sans modifier la session réelle.
`nix flake check` évalue le module et les noms de paquets pour x86_64 et aarch64
(avec `--all-systems`). Cela ne remplace pas un démarrage graphique sur NixOS.
Le diagnostic historique peut encore signaler certains chemins `/usr/share`
absents sous NixOS ; les journaux des services donnent leur état réel.

### Test complet dans une VM

Sur un hôte Linux x86_64 avec Nix et `/dev/kvm` accessible :

```bash
nix build .#vm-test -L --cores 4 --max-jobs 2 --out-link result-vm-test
```

Le test construit une VM jetable (4 Go de RAM, 4 processeurs virtuels, disque de
8 Go), lance réellement `install.sh` avec un compte ordinaire, démarre Hyprland
avec UWSM et vérifie Noctalia, l'île Quickshell, hypridle et l'ouverture d'un
terminal kitty/zsh. Les journaux et captures d'écran sont conservés dans
`result-vm-test/`. Aucun fichier de la session hôte n'est installé ou remplacé.
Le premier lancement télécharge plusieurs Go de dépendances ; les suivants
réutilisent le cache Nix. Le rendu graphique de la VM utilise le processeur : ce
test ne mesure pas les performances ni les pilotes GPU d'une machine physique.

### Validation du 3 novembre 2026

Le test QEMU/KVM passe sous NixOS 26.11, avec Hyprland 0.57.0, Noctalia 5.4.1
et Quickshell 0.3.2. Il vérifie l'installation sans root, le chargement de la
configuration Lua sans erreur, les services et leurs interfaces IPC, puis les
plugins Zsh (coloration, suggestions, powerlevel10k) et une commande réellement
tapée dans le terminal Kitty. Les captures du bureau et du terminal ont aussi
été inspectées. Le scénario dure environ une minute une fois le cache rempli.

La VM désactive son serveur de synthèse vocale système pour éviter de télécharger
toutes les voix MBROLA ; le module installé sur une vraie machine conserve le
choix de NixOS. Les services externes ne sont pas accessibles depuis le réseau
isolé du test. Les journaux peuvent donc signaler les API hors ligne et l'absence
de périphériques Bluetooth ou audio. Les fonctions qui dépendent du matériel
(veille réelle, Wi-Fi, Bluetooth, NVIDIA et batterie) restent à vérifier sur le PC.

Hyprland 0.57 affiche encore l'avertissement non bloquant `on_created_empty`
pour le terminal déroulant de la configuration d'origine ; il est également
présent avec cette configuration sous Fedora. Noctalia peut aussi notifier la
migration du rôle de palette `outline` vers `outline_variant` au premier démarrage.

Références : [Noctalia v5 sous NixOS](https://docs.noctalia.dev/noctalia/getting-started/nixos/)
et [Hyprland avec UWSM](https://wiki.hypr.land/useful-utilities/uwsm/).
