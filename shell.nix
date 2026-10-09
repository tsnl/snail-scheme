{
  pkgs ? import <nixpkgs> { },
}:

pkgs.mkShell {
  packages = with pkgs; [
    git
    chibi
    direnv
    gnumake
    nixfmt
    emacs-nox
    ripgrep
  ];
}
