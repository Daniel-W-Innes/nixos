{
  description = "Main flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

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

    vpn-confinement = {
      url = "github:Maroka-chan/VPN-Confinement";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    whisper-dictation = {
      url = "github:jacopone/whisper-dictation";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      agenix,
      home-manager,
      nix-index-database,
      nixos-facter-modules,
      pre-commit-hooks,
      vpn-confinement,
      whisper-dictation,
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
            ];
          };

          ripsecrets.enable = true;
          trufflehog.enable = true;
        };
        package = nixpkgs.legacyPackages.x86_64-linux.prek;
      };
      nixosConfigurations = {
        melon = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            agenix.nixosModules.default
            nixos-facter-modules.nixosModules.facter
            { config.facter.reportPath = ./melon/facter.json; }
            { _module.args.secretsDir = ./secrets; }
            vpn-confinement.nixosModules.default
            ./melon/configuration.nix
            ./generic/avahi.nix
            ./generic/min.nix
            ./generic/ssh.nix
            ./generic/prometheus.nix
            ./generic/server/all.nix
            {
              environment.systemPackages = self.checks.x86_64-linux.pre-commit-check.enabledPackages ++ [
                nixpkgs.legacyPackages.x86_64-linux.prek
              ];
            }
            home-manager.nixosModules.home-manager
            {
              home-manager = {
                useGlobalPkgs = true;
                useUserPackages = true;
                users.daniel = import ./home/server.nix;
              };
            }
            nix-index-database.nixosModules.nix-index
            { programs.nix-index-database.comma.enable = true; }
          ];
        };
        onion = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            agenix.nixosModules.default
            nixos-facter-modules.nixosModules.facter
            { config.facter.reportPath = ./onion/facter.json; }
            { _module.args.secretsDir = ./secrets; }
            ./onion/configuration.nix
            ./generic/all.nix
            ./generic/borgmatic.nix
            ./generic/zsa.nix
            {
              environment.systemPackages = [whisper-dictation.packages.x86_64-linux.default];
               systemd.user.services.whisper-dictation = {
                enable = true;
                wantedBy = [ "graphical-session.target" ];
              };
            }
            {
              environment.systemPackages = self.checks.x86_64-linux.pre-commit-check.enabledPackages ++ [
                nixpkgs.legacyPackages.x86_64-linux.prek
              ];
            }
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
      };
    };
}
