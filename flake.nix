{
  description = "Juno — Autonomous AI sidekick NixOS module";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }: {
    nixosModules.juno = import ./nixos;
    nixosModules.default = self.nixosModules.juno;
  };
}
