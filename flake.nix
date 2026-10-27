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
      # A package with pkgs/<name>/update.sh is kept current by the update workflow.
      names = [ "tailscale" ];

      overlay = final: prev:
        lib.genAttrs names (name:
          final.callPackage ./pkgs/${name} (
            lib.optionalAttrs (prev ? ${name}) { ${name} = prev.${name}; }
          ));

      pkgsFor = system: import nixpkgs { inherit system; overlays = [ overlay ]; };
    in
    {
      overlays.default = overlay;

      packages = forAllSystems (system:
        let pkgs = pkgsFor system; in
        lib.genAttrs names (name: pkgs.${name}) // { default = pkgs.tailscale; });

      checks = forAllSystems (system:
        let pkgs = pkgsFor system; in {
          tailscale = pkgs.runCommand "check-tailscale" { } ''
            v=$(${pkgs.tailscale}/bin/tailscale version | head -n1)
            echo "$v"
            test "$v" = "${pkgs.tailscale.version}"
            test -x ${pkgs.tailscale}/bin/tailscaled
            touch $out
          '';
        });
    };
}
