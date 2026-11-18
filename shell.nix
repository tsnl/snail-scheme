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

  # WebGPU for Node is Dawn's own binding, dawn.node, from npm's webgpu
  # package, which package.json pins and `make fetch` installs. On Linux,
  # Dawn opens the Vulkan loader by name, which finds the GPU's driver
  # where the system keeps it; NixOS keeps no loader where the dynamic
  # linker looks, so the shell names nixpkgs'.
  linux = pkgs.stdenv.hostPlatform.isLinux;
in
pkgs.mkShell {
  LD_LIBRARY_PATH = pkgs.lib.optionalString linux (pkgs.lib.makeLibraryPath [ pkgs.vulkan-loader ]);
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
