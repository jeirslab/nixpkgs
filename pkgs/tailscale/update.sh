#!/usr/bin/env bash
# Move source.json to the latest tailscale/tailscale release.
# Needs: nix, jq, curl. Optional GITHUB_TOKEN. Run from anywhere.
set -euo pipefail
dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
root=$(cd "$dir/../.." && pwd)
src=$dir/source.json

auth=()
[ -n "${GITHUB_TOKEN:-}" ] && auth=(-H "Authorization: Bearer $GITHUB_TOKEN")
tag=$(curl -fsSL "${auth[@]}" https://api.github.com/repos/tailscale/tailscale/releases/latest | jq -r .tag_name)
version=${tag#v}
[[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "unexpected tag: $tag" >&2; exit 1; }

if [ "$version" = "$(jq -r .version "$src")" ]; then
  echo "tailscale already at $version"
  exit 0
fi

hash=$(nix flake prefetch --json "github:tailscale/tailscale/$tag" | jq -r .hash)
fake=sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=
jq --arg v "$version" --arg h "$hash" --arg f "$fake" \
  '.version=$v | .hash=$h | .vendorHash=$f' "$src" > "$src.new" && mv "$src.new" "$src"

# The vendor hash is only known from the failed build's "got:" line.
log=$(mktemp)
if nix build "$root#tailscale" --no-link 2> "$log"; then
  echo "build succeeded with a fake vendorHash; refusing" >&2; exit 1
fi
vendor=$(sed -n 's/^ *got: *\(sha256-[A-Za-z0-9+\/=]*\).*/\1/p' "$log" | tail -n1)
[ -n "$vendor" ] || { cat "$log" >&2; echo "no vendorHash in build output" >&2; exit 1; }
jq --arg h "$vendor" '.vendorHash=$h' "$src" > "$src.new" && mv "$src.new" "$src"
echo "tailscale -> $version"
