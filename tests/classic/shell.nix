# A function so the enter path has to auto-call it. nix eval --file does not.
{ pkgs ? import <nixpkgs> { } }:
pkgs.mkShell {
  packages = [ pkgs.hello ];
}
