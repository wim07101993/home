{
  description = "Machine layer for the Hetzner hosts. Containers are OpenTofu's -- see ../tofu.";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, nixpkgs-unstable, disko, ... }:
    let
      host = name: nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { inherit nixpkgs-unstable; };
        modules = [
          disko.nixosModules.disko
          ./hosts/${name}

          { system.configurationRevision = self.rev or self.dirtyRev or null; }
        ];
      };
    in
    {
      nixosConfigurations = {
        # Hetzner Cloud.
        bumba = host "bumba";
        mindy = host "mindy";

        # At home.
        samson = host "samson";
        plop = host "plop";

        laptop = host "laptop";
      };
    };
}
