{
  description = "Main flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-index-database = {
      url = "github:nix-community/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-facter-modules.url = "github:numtide/nixos-facter-modules";

    pre-commit-hooks = {
      url = "github:cachix/pre-commit-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    agenix = {
      url = "github:ryantm/agenix";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        home-manager.follows = "home-manager";
      };
    };

    vpn-confinement.url = "github:Maroka-chan/VPN-Confinement";
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
      ...
    }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};

      preCommitCheck = pre-commit-hooks.lib.${system}.run {
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
        package = pkgs.prek;
      };

      sharedModules = [
        agenix.nixosModules.default
        nixos-facter-modules.nixosModules.facter
        ./modules/airzone-exporter.nix
        ./modules/openweathermap-exporter.nix
        { _module.args.secretsDir = ./secrets; }
        {
          environment.systemPackages = preCommitCheck.enabledPackages ++ [
            pkgs.prek
          ];
        }
        home-manager.nixosModules.home-manager
        nix-index-database.nixosModules.nix-index
        { programs.nix-index-database.comma.enable = true; }
      ];

      mkHomeManagerModule = homeFile: {
        home-manager = {
          useGlobalPkgs = true;
          useUserPackages = true;
          users.daniel = import homeFile;
        };
      };

      mkHost =
        name:
        {
          type,
          stateVersion,
          extraModules ? [ ],
        }:
        nixpkgs.lib.nixosSystem {
          inherit system;
          modules =
            sharedModules
            ++ [
              { config.facter.reportPath = ./. + "/${name}/facter.json"; }
              (./. + "/${name}/configuration.nix")
              (./. + "/generic/${type}.nix")
              (mkHomeManagerModule (./. + "/home/${type}.nix"))
              {
                # This value determines the NixOS release from which the default
                # settings for stateful data, like file locations and database versions
                # on your system were taken. It‘s perfectly fine and recommended to leave
                # this value at the release version of the first install of this system.
                # Before changing this value read the documentation for this option
                # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
                home-manager.users.daniel.home.stateVersion = stateVersion;
                system.stateVersion = stateVersion;
              }
            ]
            ++ extraModules;
        };

      hosts = {
        melon = {
          type = "server";
          stateVersion = "25.11";
          extraModules = [
            vpn-confinement.nixosModules.default # TODO: This should be in the server module not here.
          ];
        };

        onion = {
          type = "desktop";
          stateVersion = "25.05";
          extraModules = [
            ./generic/zsa.nix
          ];
        };
      };
    in
    {
      formatter.${system} = pkgs.nixfmt-tree;
      checks.${system}.pre-commit-check = preCommitCheck;
      nixosConfigurations = nixpkgs.lib.mapAttrs mkHost hosts;
    };
}
