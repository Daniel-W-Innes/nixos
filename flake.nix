{
  description = "Starting flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

    lanzaboote = {
      url = "github:nix-community/lanzaboote/v0.4.3";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-index-database = {
      url = "github:nix-community/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-facter-modules = {
      url = "github:numtide/nixos-facter-modules";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    pre-commit-hooks = {
      url = "github:cachix/pre-commit-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      agenix,
      lanzaboote,
      home-manager,
      nix-index-database,
      nixos-facter-modules,
      pre-commit-hooks,
      ...
    }:
    {
      formatter.x86_64-linux = nixpkgs.legacyPackages.x86_64-linux.nixfmt-tree;
      checks.x86_64-linux.pre-commit-check = pre-commit-hooks.lib.x86_64-linux.run {
        src = self;
        hooks = {
          deadnix.enable = true;
          nil.enable = true;
          statix = {
            enable = true;
            settings.ignore = [
              "**/hardware-configuration.nix"
              "virt/gen"
            ];
          };

          ripsecrets.enable = true;
          trufflehog.enable = true;
        };
        package = nixpkgs.legacyPackages.x86_64-linux.prek;
      };
      devShells = {
        x86_64-linux = {
          default = nixpkgs.legacyPackages.x86_64-linux.mkShell {
            inherit (self.checks.x86_64-linux.pre-commit-check) shellHook;
            buildInputs = self.checks.x86_64-linux.pre-commit-check.enabledPackages;
          };
        };
      };
      nixosConfigurations = {
        onion = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            #sops-nix.nixosModules.sops
            agenix.nixosModules.default
            nixos-facter-modules.nixosModules.facter
            { config.facter.reportPath = ./onion/facter.json; }
            ./onion/configuration.nix
            ./secrets/age.nix
            ./generic/all.nix
            ./virt/podman.nix
            home-manager.nixosModules.home-manager
            {
              home-manager = {
                useGlobalPkgs = true;
                useUserPackages = true;
                users.daniel = import ./home/desktop.nix;
              };
            }
            nix-index-database.nixosModules.nix-index
            { programs.nix-index-database.comma.enable = true; }
          ];
        };
        cucamelon = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            lanzaboote.nixosModules.lanzaboote
            agenix.nixosModules.default
            nixos-facter-modules.nixosModules.facter
            { config.facter.reportPath = ./cucamelon/facter.json; }
            ./cucamelon/configuration.nix
            ./secrets/age.nix
            ./generic/all.nix
            ./virt/podman.nix
            home-manager.nixosModules.home-manager
            {
              home-manager = {
                useGlobalPkgs = true;
                useUserPackages = true;
                users.daniel = import ./home/laptop.nix;
              };
            }
            (
              { pkgs, lib, ... }:
              {

                environment.systemPackages = [ pkgs.sbctl ];
                # Lanzaboote currently replaces the systemd-boot module.
                # This setting is usually set to true in configuration.nix
                # generated at installation time. So we force it to false
                # for now.
                boot.loader.systemd-boot.enable = lib.mkForce false;

                boot.lanzaboote = {
                  enable = true;
                  pkiBundle = "/var/lib/sbctl";
                };
              }
            )
            nix-index-database.nixosModules.nix-index
            { programs.nix-index-database.comma.enable = true; }
          ];
        };
      };
    };
}
