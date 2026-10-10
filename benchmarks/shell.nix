{
  pkgs ? import <nixpkgs> { },
}:

pkgs.mkShell {
  packages = with pkgs; [
    git
    (python3.withPackages (python: [ python.matplotlib ]))
    chibi
    chez
    guile
    binaryen
    nodejs
    clang
    llvm
    boehmgc
  ];
  BDWGC_INCLUDE = "${pkgs.boehmgc.dev}/include";
  BDWGC_LIB = "${pkgs.boehmgc}/lib";
}
