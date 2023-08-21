{
  description = "A flake parts module to check input closure sizes recursively";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-23.05";
    flake-parts.url = "github:hercules-ci/flake-parts";
  };

  outputs = inputs:
    inputs.flake-parts.lib.mkFlake {inherit inputs;} {
      imports = [./flakeModules/inputsCheck.nix];
      systems = ["x86_64-linux"];
      flake.flakeModule = ./flakeModules/inputsCheck.nix;
    };
}
