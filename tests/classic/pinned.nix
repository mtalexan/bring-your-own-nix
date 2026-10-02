# Fetches nixpkgs into the private store. Do not use <nixpkgs> here: a system
# store path is not visible under --store local?root=...
{ pkgs ? import (builtins.fetchTarball {
    url = "https://github.com/NixOS/nixpkgs/archive/b4fd65b198c599cbe814fcb9f42d25d021595ec9.tar.gz";
    sha256 = "sha256-ilerN1WLSvF+HMjziC/Wv99J5y02maDH+6hZPwsORKg=";
  }) { }
}:
pkgs.mkShell {
  packages = [ pkgs.hello ];
}
