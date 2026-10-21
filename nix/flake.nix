{
  description = "Machine layer for the Hetzner hosts. Containers are OpenTofu's -- see ../tofu.";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, disko, ... }:
    let
      host = name: nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          disko.nixosModules.disko
          ./hosts/${name}
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
      };
    };
}
