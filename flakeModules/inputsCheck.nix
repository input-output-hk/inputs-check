# flakeModule: inputs.inputs-check.flakeModule
{lib, ...}: let
  inherit (builtins) attrNames attrValues concatLists elem hasAttr match toJSON trace typeOf unsafeDiscardStringContext;
  inherit (lib) filter filterAttrs flatten foldl' listToAttrs mapAttrsToList nameValuePair optionals recursiveUpdate traceSeq;

  p = v: traceSeq v v;

  # Attrset defaults don't work from impure cli passing to functions, so
  # assemble an attrset of usable args with this function.
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
      if hasAttr name args
      then args.${name}
      else default;
  };

  optionalTrace = args: attrPath: eval:
    if args.pathTrace
    then trace attrPath eval
    else eval;

  # Remove any `denyList` attrs from the supplied attrset, which is by default
  # self.inputs.
  fAttrs = args: filterAttrs (n: _: !(elem n args.denyList));

  # Remove any `denyList` elements from the supplied list, which is typically a
  # list of attrNames found from a provided recursion path point.
  fList = args: filter (n: !(elem n args.denyList));

  # Mark a pathAttr as recognized for inclusion in results.
  found = pathAttr: [{FOUND = {inherit (pathAttr) attrPath out depth;};}];

  # Check if the input path has the `recursePathStr` attr and is within the
  # depth maximum.
  attrCheck = pathAttr: args: hasAttr args.recursePathStr pathAttr.attr && pathAttr.depth < args.maxRecurseDepth;

  # Filter any non-unique pathAttr elements from a list by criteria of
  # attrPath, keeping only the last element if duplicates are present.
  uniqueAttrPaths = l: attrValues (listToAttrs (map (e: nameValuePair e.attrPath e) l));

  # Generates an initial list of inputs to begin processing marking them as
  # depth of 1.  The list is filtered for any `denyList` and starts processing
  # from the flakes self.`startPathStr` attr path location.
  genPathAttr = self: args:
    mapAttrsToList (name: _: {
      inherit name;
      out = unsafeDiscardStringContext self.${args.startPathStr}.${name}.outPath;
      attr = self.${args.startPathStr}.${name};
      attrPath = "${args.startPathStr}.${name}";
      depth = 1;
    })
  (fAttrs args self.${args.startPathStr});

  recursePathSearch = pathAttr: args: let
    recurseInto = pathAttr:
      map (name:
        recursePathSearch {
          inherit name;
          out = unsafeDiscardStringContext pathAttr.attr.${args.recursePathStr}.${name}.outPath;
          attr = pathAttr.attr.${args.recursePathStr}.${name};
          attrPath = "${pathAttr.attrPath}.${args.recursePathStr}.${name}";
          depth = pathAttr.depth + 1;
        }
        args)
      (fList args (attrNames pathAttr.attr.${args.recursePathStr}));
  in
    optionalTrace args pathAttr.attrPath (
      if args.dumpAllPaths
      then found pathAttr ++ optionals (attrCheck pathAttr args) (recurseInto pathAttr)
      else if match args.matchExtRegex pathAttr.name != null
      then found pathAttr
      else if attrCheck pathAttr args
      then recurseInto pathAttr
      else "recurseEndpointReached"
    );

  searchAttrPath = self: args:
    uniqueAttrPaths (concatLists (
      map attrValues (
        filter (e: typeOf e == "set" && e ? FOUND) (
          flatten (
            map (
              pathAttr:
                if args.dumpAllPaths
                then found pathAttr ++ optionals (attrCheck pathAttr args) (recursePathSearch pathAttr args)
                else if match args.matchExtRegex pathAttr.name != null
                then found pathAttr
                else if attrCheck pathAttr args
                then recursePathSearch pathAttr args
                else null
            )
            # A starting list of inputs to process -- see comment above
            (genPathAttr self args)
          )
        )
      )
    ));
in {
  flake.inputsCheck = self: args: toJSON (searchAttrPath self (parseArgs args));

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
            --expr "let f = builtins.getFlake (toString ./.); in f.inputsCheck f $ARGS" \
            | jq -r '.[] | (.attrPath) + " " + (.depth | tostring) + " " + (.out)' \
            | xargs -I{} bash -c 'echo "{} $(nix path-info -S $(echo {} | awk "{print \$3}") | awk "{print \$2}")"' \
            | jq -R '[splits(" +")] | {attrPath: .[0], depth: (.[1] | tonumber), out: .[2], closureSize: (.[3] | tonumber)}' \
            | jq -s 'sort_by(.closureSize)'
        '';
      })
      .overrideAttrs (_: {meta.description = "Show sorted flake input closure sizes";});
  };
}
