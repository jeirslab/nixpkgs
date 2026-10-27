# jeirslab/nixpkgs

jeirslab's own Nix package set, as a flake. It holds packages that must be newer than (or differ from) what nixpkgs ships, and is imported into select repositories as an override or an addition. More packages will be added here the same way.

## Packages

| Package | What | Kept current |
|---|---|---|
| `tailscale` | nixpkgs' `tailscale` derivation moved to the latest upstream release. Same outputs (`out`, `derper`), same binaries, so it is a drop-in for `services.tailscale.package`. | daily (`scripts/update`) |

Systems: `x86_64-linux`, `aarch64-linux`. The nixpkgs input is `nixos-unstable`, pinned in `flake.lock`.

## Use

As a package:

```nix
{
  inputs.jeirslab-nixpkgs.url = "github:jeirslab/nixpkgs";
  # in a NixOS module:
  services.tailscale.package = inputs.jeirslab-nixpkgs.packages.${pkgs.system}.tailscale;
}
```

As an overlay (adds or overrides `tailscale` in `pkgs`):

```nix
nixpkgs.overlays = [ inputs.jeirslab-nixpkgs.overlays.default ];
```

Do not make this flake's `nixpkgs` follow yours unless your nixpkgs is recent enough to hold the Go toolchain the new release needs.

## How the update works

Every self-updating package follows one model (below) and is kept current by one script, `scripts/update`, run daily by `.github/workflows/update.yml` (and by hand: `gh workflow run update`).

Per package, in `pkgs/<name>/`:

- `version.json`: the logged state. `{ "version": "1.104.2", "hashes": { "src": "sha256-...", "vendor": "sha256-..." }, "updated": "2026-10-27" }`. One schema for all packages; only the keys under `hashes` differ. `default.nix` reads its version and hashes from it.
- `get-version`: the package's version getter. Executable, any language, no arguments, exit 0 and exactly one JSON object on stdout, nothing else: `{ "name": "tailscale", "version": "1.106.0", "url": "https://..." }` (`url` is the source archive the `src` hash is prefetched from). Non-zero exit on failure, diagnostics on stderr.
- `passthru.selfUpdate = { getVersion = ./get-version; versionFile = ./version.json; hashes = [ "src" "vendor" ]; };` in `default.nix`. This is how the updater finds the package (flake output `selfUpdate.<system>`), not the file names.

`scripts/update [--package NAME]... [--dry-run] [--commit]` walks every package that declares `selfUpdate` and, for each: runs `get-version`, validates its output (`scripts/validate getter`), compares with `version.json`, and for a different version writes it, recomputes every listed hash (`src` by prefetch from `url`; any other hash from the fake-hash build's `got:` line, so `vendorHash`, `npmDepsHash` and `cargoHash` all work), builds the package and `checks.<system>.<name>` if it exists, and keeps the change only if that passed. `--commit` makes one commit per updated package, `<name>: <old> -> <new>`. It prints one line per package, `[update] <name> up-to-date|available|updated|FAILED ...`, and exits 0 if nothing failed, 1 if a package failed, 2 on bad arguments.

`nix flake check` runs `checks.<system>.self-update-model`: every self-updating package has a valid `version.json` and an executable `get-version`, the hash keys match `selfUpdate.hashes`, the built package's version equals `version.json`, files of the model are not present without the declaration, and the validators pass their fixtures (`tests/fixtures/`).

The workflow job `check` runs `nix flake check` on pushes, pull requests and before every update; job `update` runs `scripts/update --commit` and pushes the per-package commits to `main` (`contents: write` only).

Run-time self-download (as in the Claude Code self-update flake) is deliberately not used: a system daemon should be built, hashed and cached, not fetched at start.

If upstream needs a newer Go than the pinned nixpkgs provides, the build fails, that package is reported `FAILED`, nothing is committed for it; run `nix flake update` to move nixpkgs.

## Adding a self-updating package

1. Copy `pkgs/_template/` to `pkgs/<name>/` (README there explains the files); write `default.nix` (callPackage style; take the nixpkgs package of the same name as an argument if it overrides one), reading version and hashes from `version.json`, and declare `passthru.selfUpdate` as above.
2. Write `get-version`: your upstream query, printing the one JSON object. Check it: `scripts/validate getter <name> < <(pkgs/<name>/get-version)`.
3. Fill `version.json` (any valid placeholder hashes; then `scripts/update --package <name>` after setting an older `version`, or just put the real ones).
4. Add `<name>` to `names` in `flake.nix`; optionally add `checks.<system>.<name>` (a smoke test the updater also runs).
5. `git add` the new files, `nix flake check`, `scripts/update --package <name> --dry-run`.

A package that does not self-update is just `pkgs/<name>/default.nix` plus the `names` entry; it must not have `get-version` or `version.json` (the check fails otherwise).
