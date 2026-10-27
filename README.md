# jeirslab/nixpkgs

jeirslab's own Nix package set, as a flake. It holds packages that must be newer than (or differ from) what nixpkgs ships, and is imported into select repositories as an override or an addition. More packages will be added here the same way.

## Packages

| Package | What | Kept current |
|---|---|---|
| `tailscale` | nixpkgs' `tailscale` derivation moved to the latest upstream release. Same outputs (`out`, `derper`), same binaries, so it is a drop-in for `services.tailscale.package`. | daily |

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

`.github/workflows/update.yml` runs daily (and by hand: `gh workflow run update`). For every `pkgs/<name>/update.sh` it:

1. reads the latest `tailscale/tailscale` release and rewrites `pkgs/tailscale/source.json` (version, source hash, vendor hash; the vendor hash is read from the failed build's `got:` line);
2. runs `nix flake check` (builds the package, runs `tailscale version`);
3. commits to `main` only if the build passed. It uses `GITHUB_TOKEN` with `contents: write` only.

Run-time self-download (as in the Claude Code self-update flake) is deliberately not used: a system daemon should be built, hashed and cached, not fetched at start.

If upstream needs a newer Go than the pinned nixpkgs provides, the build fails and nothing is committed; run `nix flake update` to move nixpkgs.

## Adding a package

1. Add `pkgs/<name>/default.nix` (callPackage style; take the nixpkgs package of the same name as an argument if it overrides one).
2. Add `<name>` to `names` in `flake.nix`.
3. Optional: add an executable `pkgs/<name>/update.sh`; the workflow runs it.
