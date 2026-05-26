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

    airzone-explorer = {
      url = "github:Daniel-W-Innes/airzone-explorer";
      inputs = {
        nixpkgs.follows = "nixpkgs";
      };
    };

    librewxr = {
      url = "github:JoshuaKimsey/LibreWXR/6013d3a05f2ac984f3f1712d43593923dc618db1";
      flake = false;
    };

    vpn-confinement.url = "github:Maroka-chan/VPN-Confinement";
  };

  outputs =
    {
      self,
      airzone-explorer,
      librewxr,
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
        {
          _module.args = {
            inherit librewxr;
            secretsDir = ./secrets;
          };
        }
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
            ]
            ++ extraModules;
        };

      hosts = {
        melon = {
          type = "server";
          extraModules = [
            # TODO: This should be in the server module not here.
            airzone-explorer.nixosModules.default
            vpn-confinement.nixosModules.default 
            ./modules/librewxr.nix
          ];
        };

        onion = {
          type = "desktop";
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
