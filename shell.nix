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
pkgs.mkShellNoCC {
  PERFETTO_UI = perfettoUi;
  SNAIL_NATIVE_LIBC = "${pkgs.glibc}/lib";
  SNAIL_NATIVE_GCC = "${pkgs.stdenv.cc.cc.lib}/lib";
  shellHook = ''
    if [ -z "''${RUSTC_WRAPPER:-}" ]; then
      export RUSTC_WRAPPER="${toString ./scripts/rustc-native}"
    fi
  '';
  packages = with pkgs; [
    git
    chibi
    chez
    direnv
    gnumake
    nixfmt
    emacs-nox
    ripgrep
    rustup
    binaryen
    llvmPackages.llvm
    nodejs
    mdbook
  ];
}
