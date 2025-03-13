# Inputs-check

A [flake parts](https://flake.parts/) module to check input closure sizes recursively.

## Getting Started

### Installing for a flake-parts nix flake repo

Add to your flake inputs, optionally following a nixpkgs input already in use:

    inputs-check = {
      url = "github:input-output-hk/inputs-check";

      # Optional to reduce input closure size
      inputs.nixpkgs.follows = "nixpkgs";
    };


Inside the mkFlake add:

    imports = [
      inputs.inputs-check.flakeModule
    ];


Assuming all other nix flake inputs are already locked, then just run:

    nix flake update inputs-check


### Installing for a non-flake-parts nix flake repo

Add input-check to your flake inputs, the same as for a flake-parts nix flake repo shown above

Inside the set which creates top level flake outputs, add an inputsCheck attribute:

    inherit (input-check) inputsCheck;


Add a flake package output for the desired arch:

    packages.x86_64-linux.input-checks = input-check.packages.x86_64-linux.input-checks;


Assuming all other nix flake inputs are already locked, then just run:

    nix flake update inputs-check


### Usage

From CLI:

    nix run .#inputs-check


The above command will use default parameters, which will be printed and appear at the top of the output:

    trace: { denyList = [ "self" ]; dumpAllPaths = true; matchExtRegex = ""; maxRecurseDepth = 6; pathTrace = false; recursePathStr = "inputs"; startPathStr = "inputs"; }


Default parameters may be modified by passing a single quoted attribute set as an arg:

    nix run .#inputs-check -- '{maxRecurseDepth = 1;}'


Use jq to analyze different things about the flake inputs:

* Find the number of top level inputs

      nix run .#inputs-check -- '{maxRecurseDepth = 1;}' | jq length
      15


* Find the number of nested inputs 10 levels deep

      nix run .#inputs-check -- '{maxRecurseDepth = 10;}' | jq length
      169


* Find the number of unique closures 10 levels deep

      nix run .#inputs-check -- '{maxRecurseDepth = 10;}' \
        | jq 'group_by(.out) | length'
      81


* Find the total closure size 10 levels deep in human readable format

      nix run .#inputs-check -- '{maxRecurseDepth = 10;}' \
        | jq 'group_by(.out) | map(first) | map (.closureSize) | add' \
        | numfmt --to=si --suffix=B
      4.8GB


### Troubleshooting

Depending on the nix version and repo inputs, infinite recursions can be
encountered as `maxRecurseDepth` increases.  If `maxRecurseDepth` can be
increased and the jq length of the result remains stable, then all nested flake
inputs are successfully being traversed.  The default depth of `6` was selected
as sufficient to often find all nested inputs, but still remain just below the
threshold of what was found to trigger infinite recursions in a few specific
repos.

A denyList of `["self"]` is set as default to avoid duplicate top level inputs
as well as eliminating an infinite recursion in one repo.

To examine total closure size using the jq example command above and not
include the inputs-check input itself if that is considered only a transient
input, set `denyList = ["inputs-check" "self"]` in the args.
