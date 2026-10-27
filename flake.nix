{
  description = "jeirslab's own Nix packages: newer than nixpkgs where it matters";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      lib = nixpkgs.lib;
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = f: lib.genAttrs systems (system: f system);

      # One list: every package here is pkgs/<name>/default.nix (callPackage-style,
      # taking the nixpkgs package of the same name when it overrides one).
      # A package that declares passthru.selfUpdate (see README.md) is kept current
      # by scripts/update, which finds it through the selfUpdate output below.
      names = [ "tailscale" ];

      overlay = final: prev:
        lib.genAttrs names (name:
          final.callPackage ./pkgs/${name} (
            lib.optionalAttrs (prev ? ${name}) { ${name} = prev.${name}; }
          ));

      # Repo-relative path of a path value (what scripts/update runs and rewrites).
      rel = p: lib.removePrefix "${self}/" (toString p);

      pkgsFor = system: import nixpkgs { inherit system; overlays = [ overlay ]; };
    in
    {
      overlays.default = overlay;

      packages = forAllSystems (system:
        let pkgs = pkgsFor system; in
        lib.genAttrs names (name: pkgs.${name}) // { default = pkgs.tailscale; });

      # Every package that declares passthru.selfUpdate, per system, as plain data
      # for scripts/update: { <name> = { version, hashes, getVersion, versionFile }; }
      selfUpdate = forAllSystems (system:
        let pkgs = pkgsFor system; in
        lib.mapAttrs
          (name: pkg: {
            inherit (pkg) version;
            inherit (pkg.selfUpdate) hashes;
            getVersion = rel pkg.selfUpdate.getVersion;
            versionFile = rel pkg.selfUpdate.versionFile;
          })
          (lib.filterAttrs (_: pkg: pkg ? selfUpdate)
            (lib.genAttrs names (name: pkgs.${name}))));

      checks = forAllSystems (system:
        let
          pkgs = pkgsFor system;
          selfUpdating = lib.filterAttrs (_: pkg: pkg ? selfUpdate)
            (lib.genAttrs names (name: pkgs.${name}));
          # Files that belong to the model but sit in a package that does not declare it.
          undeclared = lib.filter
            (name: !(selfUpdating ? ${name})
              && (builtins.pathExists ./pkgs/${name}/get-version
                  || builtins.pathExists ./pkgs/${name}/version.json))
            names;
          model = pkgs.writeText "self-update-model.json" (builtins.toJSON {
            packages = lib.mapAttrs
              (_: pkg: {
                inherit (pkg) version;
                inherit (pkg.selfUpdate) hashes;
                getVersion = "${pkg.selfUpdate.getVersion}";
                versionFile = "${pkg.selfUpdate.versionFile}";
              })
              selfUpdating;
            inherit undeclared;
          });
        in
        {
          tailscale = pkgs.runCommand "check-tailscale" { } ''
            v=$(${pkgs.tailscale}/bin/tailscale version | head -n1)
            echo "$v"
            test "$v" = "${pkgs.tailscale.version}"
            test -x ${pkgs.tailscale}/bin/tailscaled
            touch $out
          '';

          # The self-update model: schema and consistency, no network.
          self-update-model = pkgs.runCommand "check-self-update-model"
            { nativeBuildInputs = [ pkgs.jq pkgs.bash ]; } ''
            validate() { bash ${./scripts/validate} "$@"; }
            fail=0

            # 1. every package that declares selfUpdate
            for name in $(jq -r '.packages | keys[]' ${model}); do
              p() { jq -r --arg n "$name" ".packages[\$n]$1" ${model}; }
              echo "checking $name"
              validate version "$name" < "$(p .versionFile)" || fail=1
              test -x "$(p .getVersion)" || { echo "$name: get-version is not executable" >&2; fail=1; }
              [ "$(jq -r .version "$(p .versionFile)")" = "$(p .version)" ] \
                || { echo "$name: package version $(p .version) differs from version.json" >&2; fail=1; }
              [ "$(jq -c '.hashes | keys' "$(p .versionFile)")" = "$(p '.hashes | sort | tojson')" ] \
                || { echo "$name: version.json hashes differ from selfUpdate.hashes" >&2; fail=1; }
            done

            # 2. model files in a package that does not declare selfUpdate
            for name in $(jq -r '.undeclared[]' ${model}); do
              echo "$name: has get-version or version.json but no passthru.selfUpdate" >&2; fail=1
            done

            # 3. the validators themselves, on fixtures; the template files must be valid
            for f in ${./tests/fixtures}/getter-good-*.json; do validate getter example < "$f" || fail=1; done
            for f in ${./tests/fixtures}/getter-bad-*.json; do
              if validate getter example < "$f" 2>/dev/null; then echo "$f: accepted, should fail" >&2; fail=1; fi
            done
            for f in ${./tests/fixtures}/version-good-*.json; do validate version example < "$f" || fail=1; done
            for f in ${./tests/fixtures}/version-bad-*.json; do
              if validate version example < "$f" 2>/dev/null; then echo "$f: accepted, should fail" >&2; fail=1; fi
            done
            validate version example < ${./pkgs/_template/version.json} || fail=1
            test -x ${./pkgs/_template/get-version} || { echo "_template/get-version is not executable" >&2; fail=1; }
            validate getter example < <(${./pkgs/_template/get-version}) || fail=1

            test "$fail" = 0
            touch $out
          '';
        });
    };
}
