{
  description = "noctalia-config : bureau Hyprland et Noctalia v5 pour NixOS";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs, ... }: {
    nixosModules.default = import ./nix/nixos.nix;

    # Évaluation d'une machine minimale ; pas besoin de matériel ou de session Wayland.
    checks = nixpkgs.lib.genAttrs [ "x86_64-linux" "aarch64-linux" ] (system:
      let
        machine = nixpkgs.lib.nixosSystem {
          inherit system;
          modules = [
            ./nix/nixos.nix
            ({ pkgs, ... }: {
              programs.noctalia-config.enable = true;
              boot.loader.grub.enable = false;
              fileSystems."/" = { device = "/dev/vda"; fsType = "ext4"; };
              system.stateVersion = "26.05";
            })
          ];
        };
        pkgs = nixpkgs.legacyPackages.${system};
        failures = builtins.filter (a: !a.assertion) machine.config.assertions;
      in {
        module = assert failures == []; pkgs.runCommand "noctalia-config-module" {
          # Force aussi l'évaluation de tous les paquets déclarés.
          packageNames = builtins.map (p: p.name) machine.config.environment.systemPackages;
        } "touch $out";
      });

    packages.x86_64-linux.vm-test = nixpkgs.legacyPackages.x86_64-linux.testers.runNixOSTest
      (import ./nix/vm-test.nix {
        noctaliaConfigModule = self.nixosModules.default;
        source = self;
      });
  };
}
