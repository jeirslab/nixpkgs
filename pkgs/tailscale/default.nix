# nixpkgs' tailscale, moved to the release pinned in source.json.
# source.json is rewritten by ./update.sh (daily, by .github/workflows/update.yml).
{ lib, fetchFromGitHub, tailscale }:
let
  source = lib.importJSON ./source.json;
in
tailscale.overrideAttrs (old: {
  inherit (source) version vendorHash;
  src = fetchFromGitHub {
    owner = "tailscale";
    repo = "tailscale";
    tag = "v${source.version}";
    inherit (source) hash;
  };
})
