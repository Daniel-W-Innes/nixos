{ ... }:

{
  nix = {
    buildMachines = [
      {
        hostName = "onion";
        system = "x86_64-linux";
        protocol = "ssh-ng";
        maxJobs = 4;
        speedFactor = 4;
        supportedFeatures = [
          "nixos-test"
          "benchmark"
          "big-parallel"
          "kvm"
        ];
      }
    ];
    distributedBuilds = true;
    settings = {
      builders-use-substitutes = true;
      trusted-users = [ "builder" ];
    };
  };
}
