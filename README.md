# Inputs-check

A [flake parts](https://flake.parts/) module to check input closure sizes recursively.

## Getting Started

### Installing for a flake-parts nix flake repo

* Add to your flake inputs, optionally following a nixpkgs input already in use:
  ```
  inputs-check = {
    url = "github:input-output-hk/inputs-check";

    # Optional to reduce input closure size
    inputs.nixpkgs.follows = "nixpkgs";
  };
  ```

* Inside the mkFlake add:
  ```
  imports = [
    inputs.inputs-check.flakeModule
  ];
  ```

* Assuming all other nix flake inputs are already locked, the just run:
  ```
  nix flake update inputs-check
  ```

### Installing for a non-flake-parts nix flake repo

* Add input-check to your flake inputs, the same as for a flake-parts nix flake repo shown above

* Inside the set which creates top level flake outputs, add an inputsCheck attribute:
  ```
  inherit (input-check) inputsCheck;
  ```

* Add a flake package output for the desired arch:
  ```
  packages.x86_64-linux.input-checks = input-check.packages.x86_64-linux.input-checks;
  ```

* Assuming all other nix flake inputs are already locked, the just run:
  ```
  nix flake update inputs-check
  ```

### Usage

* From CLI:
  ```
  nix run .#inputs-check
  ```

* Default parameters may be modified by passing a single quoted attribute set as an arg:
  ```
  nix run .#inputs-check -- '{maxRecurseDepth = 1;}'
  ```

* Use jq to analyze different things about the flake inputs:
  ```
  # Find the number of top level inputs, excluding inputs-check itself
  nix run .#inputs-check -- '{maxRecurseDepth = 1; denyList = ["inputs-check" "self"];}' | jq length
  15

  # Find the number of top nested inputs 6 levels deep, excluding inputs-check itself
  nix run .#inputs-check -- '{maxRecurseDepth = 6; denyList = ["inputs-check" "self"];}' | jq length
  175

  # Find the number of unique closures 6 levels deep, excluding inputs-check itself
  nix run .#inputs-check -- '{maxRecurseDepth = 6; denyList = ["inputs-check" "self"];}' \
    | jq 'group_by(.out) | length'
  81

  # Find the total closure size 6 levels deep, excluding inputs-check itself, in human readable format
  nix run .#inputs-check -- '{maxRecurseDepth = 6; denyList = ["inputs-check" "self"];}' \
    | jq 'group_by(.out) | map(first) | map (.closureSize) | add' \
    | numfmt --to=si --suffix=B
  4.8GB
  ```
