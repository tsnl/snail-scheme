{
  pkgs ? import <nixpkgs> { },
}:

pkgs.mkShell {
  packages = with pkgs; [
    git
    chibi
    gnumake
    nixfmt
    emacs-nox
    rustup
    binaryen
    nodejs
    mdbook
  ];
}
