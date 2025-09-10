{ ... }:

{
  nix.buildMachines = [{
    hostName = "onion";
    system = "x86_64-linux";
    protocol = "ssh-ng";
    maxJobs = 4;
    speedFactor = 4;
    supportedFeatures = [ "nixos-test" "benchmark" "big-parallel" "kvm" ];
  }];
  nix.distributedBuilds = true;
  nix.settings = {
    builders-use-substitutes = true;
  };
}
