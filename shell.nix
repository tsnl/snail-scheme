{ pkgs ? import <nixpkgs> {} }:

pkgs.mkShell {
  packages = with pkgs; [
    chibi
    direnv
    gnumake
  ];
}
