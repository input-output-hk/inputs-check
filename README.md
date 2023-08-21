# Inputs-check

A [flake parts](https://flake.parts/) module to check input closure sizes recursively.

## Getting Started

### Installing

* Add to your flake inputs:
  ```
  inputs-check.url = "github:input-output-hk/inputs-check";
  ```

* Inside the mkFlake add:
  ```
  imports = [
    inputs.inputs-check.flakeModule
  ];
  ```

* Run nix flake lock and you're set.

### Usage

* From CLI:
  ```
  nix run .#inputs-check
  ```

* Default parameters may be modified by passing a single quoted attribute set as an arg:
  ```
  nix run .#inputs-check -- '{maxRecurseDepth = 1;}'
  ```
