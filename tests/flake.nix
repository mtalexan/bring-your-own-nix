{
  description = "Exercises bring-your-own-nix with tools that are not on the host";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f (import nixpkgs { inherit system; }));
    in
    {
      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = [ pkgs.hello pkgs.nim ];
        };
        cowsay = pkgs.mkShell {
          packages = [ pkgs.cowsay ];
        };
      });
    };
}
