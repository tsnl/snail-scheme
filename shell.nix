{
  pkgs ? import <nixpkgs> { },
}:

let
  perfettoUi = pkgs.fetchzip {
    name = "perfetto-ui-58.2";
    url = "https://github.com/google/perfetto/releases/download/v58.2/perfetto-ui.zip";
    hash = "sha256-DZTOCTHQ+4mi6oefwv1SY/fJ3WfM3Q3BnOhs/Xy+W6s=";
    stripRoot = false;
  };
in
pkgs.mkShell {
  PERFETTO_UI = perfettoUi;
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
    mdbook
    graphviz
  ];
}
