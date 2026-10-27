# The tools for building and testing, from the nixpkgs revision pinned in
# npins/sources.json (`npins update nixpkgs` moves it). CI and the
# devcontainer use this same file.
{
  sources ? import ./npins,
  pkgs ? import sources.nixpkgs { },
}:

pkgs.mkShell {
  packages = with pkgs; [
    git
    git-filter-repo
    chibi
    gnumake
    nixfmt
    npins
    emacs-nox
    rustup
    binaryen
    nodejs_26
    mdbook
  ];
}
