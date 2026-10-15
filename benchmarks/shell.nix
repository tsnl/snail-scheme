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
    llvmPackages.clang
    llvmPackages.lld
    llvm
  ];
}
