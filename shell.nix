# The tools for building and testing, from the nixpkgs revision pinned in
# npins/sources.json (`npins update nixpkgs` moves it). CI and the
# devcontainer use this same file.
{
  sources ? import ./npins,
  pkgs ? import sources.nixpkgs { },
}:

let
  # Chez through 10.4.1 crashes ("nonrecoverable invalid memory reference")
  # when it collects its oldest generation in place and meets a
  # continuation with an empty stack: it marks the byte before the stack.
  # The test runner and the bootstrap reach that, now and then (#800). The
  # fix is upstream for 10.5.0; this goes once the pinned nixpkgs has it.
  chez = pkgs.chez.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [
      (pkgs.fetchpatch {
        name = "repair-in-place-marking-of-an-empty-continuation-stack.patch";
        url = "https://github.com/cisco/ChezScheme/commit/ed9bbe777715a8df75cdb84ca2088cdd2a16aa1e.patch";
        includes = [ "c/gc.c" ];
        hash = "sha256-fzCet8QTWk4Bh0gGbseY/pdzlRlIkVhy4QK4LikAP6o=";
      })
    ];
  });
in
pkgs.mkShell {
  packages = with pkgs; [
    git
    git-filter-repo
    chez
    gnumake
    nixfmt
    npins
    rustup
    nodejs_26
    mdbook
    tree-sitter
    binaryen
  ];
}
