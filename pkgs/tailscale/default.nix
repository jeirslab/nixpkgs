# nixpkgs' tailscale, moved to the release logged in version.json.
# version.json is rewritten by scripts/update (daily, by .github/workflows/update.yml);
# get-version finds the latest release. The model: README.md, "Adding a self-updating package".
{ lib, fetchFromGitHub, tailscale }:
let
  logged = lib.importJSON ./version.json;
in
tailscale.overrideAttrs (old: {
  inherit (logged) version;
  vendorHash = logged.hashes.vendor;
  src = fetchFromGitHub {
    owner = "tailscale";
    repo = "tailscale";
    tag = "v${logged.version}";
    hash = logged.hashes.src;
  };
  passthru = (old.passthru or { }) // {
    selfUpdate = {
      getVersion = ./get-version;
      versionFile = ./version.json;
      hashes = [ "src" "vendor" ];
    };
  };
})
