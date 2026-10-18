let
  pkgs = import (builtins.fetchTarball {
    url = "https://github.com/NixOS/nixpkgs/archive/dc5d91f840324650bac8c379428c7037a416959a.tar.gz";
    sha256 = "1v403gscmmsaq6v3rrbwin62bvjps737klmpg9v868cwmwkqd9am";
  }) { };
in
pkgs.mkShellNoCC {
  OTT_COQ_LIB = "${pkgs.ott.src}/coq";
  packages = [
    pkgs.ott
    pkgs.coq
    pkgs.rocqPackages.stdlib
    (pkgs.texliveSmall.withPackages (tex: [ tex.supertabular ]))
  ];
}
