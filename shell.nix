{
  pkgs ? import <nixpkgs> { },
}:

pkgs.mkShell {
  packages = with pkgs; [
    git
    chibi
    chez
    direnv
    gnumake
    nixfmt
    emacs-nox
    ripgrep
    python3
    rustup
    binaryen
    nodejs
  ];
}
