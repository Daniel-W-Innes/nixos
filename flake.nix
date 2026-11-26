{
  description = "Main flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    # Rolling nixpkgs for fast-moving services (immich) that stable lags on
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

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
    lanzaboote = {
      url = "github:nix-community/lanzaboote/v1.0.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # MCP server for the Lidarr API (https://github.com/abl030/lidarr-mcp)
    lidarr-mcp = {
      url = "github:abl030/lidarr-mcp";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      nixpkgs-unstable,
      agenix,
      home-manager,
      nix-index-database,
      nixos-facter-modules,
      pre-commit-hooks,
      lanzaboote,
      lidarr-mcp,
      ...
    }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      inherit (nixpkgs) lib;

      preCommitCheck = pre-commit-hooks.lib.${system}.run {
        src = self;
        hooks = {
          deadnix = {
            enable = true;
            settings.exclude = [
              # Vendored unmerged nixpkgs PR #552103 module
              # (see modules/stalwart/VENDORED.md).
              "modules/stalwart/**"
            ];
          };
          nil.enable = true;
          statix = {
            enable = true;
            settings.ignore = [
              "**/hardware-configuration.nix"
              "modules/stalwart/**"
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
        ./modules/konnected-exporter.nix
        ./modules/bookorbit.nix
        ./modules/openvpn-exporter.nix
        home-manager.nixosModules.home-manager
        nix-index-database.nixosModules.nix-index
        lanzaboote.nixosModules.lanzaboote
        {
          _module.args.secretsDir = ./secrets;
          _module.args.lidarrMCP = lidarr-mcp;
          _module.args.immichPkgs = nixpkgs-unstable.legacyPackages.${system};
          programs.nix-index-database.comma.enable = true;
          environment.systemPackages = preCommitCheck.enabledPackages ++ [
            pkgs.prek
          ];
        }
      ];

      mkHomeManagerModule = homeFile: {
        home-manager = {
          useGlobalPkgs = true;
          useUserPackages = true;
          users.daniel = import homeFile;
        };
      };

      # The module list of a host, factored out so the VM tests in
      # tests/vm-test.nix can evaluate exactly the same configuration.
      mkHostModules =
        name:
        {
          type,
          stateVersion,
          secureBoot ? false,
          extraModules ? [ ],
        }:
        sharedModules
        ++ [
          { config.facter.reportPath = ./. + "/hosts/${name}/facter.json"; }
          (./. + "/hosts/${name}/configuration.nix")
          (./. + "/generic/${type}.nix")
          (mkHomeManagerModule (./. + "/home/${type}.nix"))
          { _module.args.secureBoot = secureBoot; }
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

      mkHost =
        name: hostAttrs:
        nixpkgs.lib.nixosSystem {
          inherit system;
          modules = mkHostModules name hostAttrs;
        };

      hosts = {
        melon = {
          type = "server";
          stateVersion = "25.11";
          extraModules = [
            # Vendored from github:nix-forge/vpn-confinement with an OpenVPN
            # transport added (see modules/vpn-confinement/VENDORED.md).
            ./modules/vpn-confinement
            {
              # Stalwart 1.x package backports for the vendored post-26.11
              # module (see modules/stalwart/VENDORED.md).
              nixpkgs.overlays = [
                (import ./overlays/stalwart.nix nixpkgs-unstable.legacyPackages.${system})
              ];
            }
          ];
        };
        onion = {
          type = "desktop";
          stateVersion = "25.05";
          extraModules = [
            ./generic/zsa.nix
            ./generic/ckb.nix
          ];
        };
        cucamelon = {
          secureBoot = true;
          type = "laptop";
          stateVersion = "26.05";
        };
      };

      vmTests = import ./tests/vm-test.nix {
        inherit
          pkgs
          lib
          system
          hosts
          mkHostModules
          ;
      };
    in
    {
      formatter.${system} = pkgs.nixfmt-tree;
      checks.${system} = {
        pre-commit-check = preCommitCheck;
      }
      // vmTests.checks;
      packages.${system} = vmTests.packages;
      # Base-flake-path -> transition test functions (see tests/vm-test.nix).
      # Only called from impure evaluations (the CI --expr step and the
      # transition wrappers); pure evals never force them, so the
      # builtins.getFlake inside is fine.
      lib.vmTransitionTests = vmTests.vmTransitionTests;
      lib.vmTransitionStateTests = vmTests.vmTransitionStateTests;
      nixosConfigurations = nixpkgs.lib.mapAttrs mkHost hosts;
    };
}
