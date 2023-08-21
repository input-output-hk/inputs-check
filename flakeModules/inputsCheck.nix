# flakeModule: inputs.inputs-check.flakeModule
flake @ {lib, ...}: let
  inherit (lib) filter filterAttrs flatten foldl' mapAttrsToList optionals recursiveUpdate traceSeq;

  p = v: traceSeq v v;

  # Attrset defaults don't work from impure cli passing to functions
  parseArgs = args:
    p (foldl' recursiveUpdate {} [
      # Search defns
      (parseArg args "startPathStr" "inputs")
      (parseArg args "recursePathStr" "inputs")

      # To scan though all discovered inputs and search for closureSize
      (parseArg args "dumpAllPaths" true)

      # Blank if dumpAllPaths, otherwise, a regex match string
      (parseArg args "matchExtRegex" "")

      # Depth limiter
      (parseArg args "maxRecurseDepth" 6)

      # Redundant or infinite recursion exclusions here
      (parseArg args "denyList" ["self"])

      # Optionally show all fullPaths as they are recursed
      (parseArg args "pathTrace" false)
    ]);

  parseArg = args: name: default: {
    ${name} =
      if builtins.hasAttr name args
      then args.${name}
      else default;
  };

  optionalTrace = args: attrPath: eval:
    if args.pathTrace
    then builtins.trace attrPath eval
    else eval;

  fAttrs = args: filterAttrs (n: _: !(builtins.elem n args.denyList));
  fList = args: builtins.filter (n: !(builtins.elem n args.denyList));

  found = pathAttr: [{FOUND = {inherit (pathAttr) attrPath out depth;};}];
  attrCheck = pathAttr: args: builtins.hasAttr args.recursePathStr pathAttr.attr && pathAttr.depth < args.maxRecurseDepth;

  genPathAttr = args:
    mapAttrsToList (name: _: {
      inherit name;
      out = builtins.unsafeDiscardStringContext flake.${args.startPathStr}.${name}.outPath;
      attr = flake.${args.startPathStr}.${name};
      attrPath = "${args.startPathStr}.${name}";
      depth = 1;
    })
    (fAttrs args flake.${args.startPathStr});

  recursePathSearch = pathAttr: args: let
    recurseInto = pathAttr:
      map (name:
        recursePathSearch {
          inherit name;
          out = builtins.unsafeDiscardStringContext pathAttr.attr.${args.recursePathStr}.${name}.outPath;
          attr = pathAttr.attr.${args.recursePathStr}.${name};
          attrPath = "${pathAttr.attrPath}.${args.recursePathStr}.${name}";
          depth = pathAttr.depth + 1;
        }
        args)
      (fList args (builtins.attrNames pathAttr.attr.${args.recursePathStr}));
  in
    optionalTrace args pathAttr.attrPath (
      if args.dumpAllPaths
      then found pathAttr ++ optionals (attrCheck pathAttr args) (recurseInto pathAttr)
      else if builtins.match args.matchExtRegex pathAttr.name != null
      then found pathAttr
      else if attrCheck pathAttr args
      then recurseInto pathAttr
      else "recurseEndpointReached"
    );

  searchAttrPath = args:
    builtins.concatLists (
      map builtins.attrValues (
        filter (e: builtins.typeOf e == "set" && e ? FOUND) (
          flatten (
            map (
              pathAttr:
                if args.dumpAllPaths
                then found pathAttr ++ optionals (attrCheck pathAttr args) (recursePathSearch pathAttr args)
                else if builtins.match args.matchExtRegex pathAttr.name != null
                then found pathAttr
                else if attrCheck pathAttr args
                then recursePathSearch pathAttr args
                else null
            )
            (genPathAttr args)
          )
        )
      )
    );
in {
  flake.inputsCheck = args: builtins.toJSON (searchAttrPath (parseArgs args));

  perSystem = {pkgs, ...}: {
    packages.inputs-check =
      (pkgs.writeShellApplication {
        name = "inputs-check";
        runtimeInputs = with pkgs; [findutils jq nix];
        text = ''
          [ -n "''${1:-}" ] && ARGS="$1" || ARGS="{}"
          # shellcheck disable=SC2016
          nix eval \
            --raw \
            --impure \
            --expr "let f = builtins.getFlake (toString ./.); in f.inputsCheck $ARGS" \
            | jq -r '.[] | (.attrPath) + " " + (.depth | tostring) + " " + (.out)' \
            | xargs -I{} bash -c 'echo "{} $(nix path-info -S $(echo {} | awk "{print \$3}") | awk "{print \$2}")"' \
            | jq -R '[splits(" +")] | {attrPath: .[0], depth: (.[1] | tonumber), out: .[2], closureSize: (.[3] | tonumber)}' \
            | jq -s 'sort_by(.closureSize)'
        '';
      })
      .overrideAttrs (_: {meta.description = "Show sorted flake input closure sizes";});
  };
}
