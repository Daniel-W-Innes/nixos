{
  description = "Starting flake";

  inputs = {
    # NixOS official package source, using the nixos-25.05 branch here
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    
    lanzaboote = {
      url = "github:nix-community/lanzaboote/v0.4.2";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    
    home-manager = {
      url = "github:nix-community/home-manager/release-25.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, ... }@inputs: {
    nixosConfigurations = {
      cucamelon = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          inputs.lanzaboote.nixosModules.lanzaboote
          ./cucamelon/configuration.nix
          ./generic/configuration.nix
          inputs.home-manager.nixosModules.home-manager
          {
            inputs.home-manager.useGlobalPkgs = true;
            inputs.home-manager.useUserPackages = true;
            inputs.home-manager.users.daniel = import ./home.nix;
          }
          ({ pkgs, lib, ... }: {

            environment.systemPackages = [
              pkgs.sbctl
            ];
            # Lanzaboote currently replaces the systemd-boot module.
            # This setting is usually set to true in configuration.nix
            # generated at installation time. So we force it to false
            # for now.
            boot.loader.systemd-boot.enable = lib.mkForce false;

            boot.lanzaboote = {
              enable = true;
              pkiBundle = "/var/lib/sbctl";
            };
          })
        ];
      };
    };
  };
}
