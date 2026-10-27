# Template for a self-updating package

Copy this folder to `pkgs/<name>/` and add `<name>` to `names` in `flake.nix`. Not a package itself (it is not in `names`), but `nix flake check` validates its files.

- `version.json`: the logged state. Schema: `{ "version", "hashes": { "<key>": "sha256-..." }, "updated": "YYYY-MM-DD" }`. The keys under `hashes` are yours (`src`, `vendor`, `npmDeps`, ...); the shape is fixed. `default.nix` reads version and hashes from it.
- `get-version`: executable, any language, no arguments. Prints exactly one JSON object `{ "name": "<name>", "version": "<latest>", "url": "<https source url>" }` on stdout, nothing else; exit 0, non-zero on failure. `url` is what the `src` hash is prefetched from, if there is a `src` hash.
- `default.nix` declares it:

```nix
passthru.selfUpdate = {
  getVersion = ./get-version;
  versionFile = ./version.json;
  hashes = [ "src" "vendor" ];   # exactly the keys of version.json "hashes"
};
```

Hash keys other than `src` are taken from the failed build's `got:` line, so any fixed-output hash (`vendorHash`, `npmDepsHash`, `cargoHash`) works. If `src` is not prefetchable from `url`, it is resolved the same way.

Check it: `scripts/validate getter <name> < <(pkgs/<name>/get-version)`, `scripts/update --package <name> --dry-run`, `nix flake check`.
