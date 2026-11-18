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

  # WebGPU for Node: Dawn's own binding, dawn.node, as the webgpu package
  # publishes it prebuilt, with its binaries for this machine only.
  # host/native/gpu.mjs loads it from SNAIL_WEBGPU. On Linux, Dawn opens
  # the Vulkan loader, found through the binding's runpath, which finds
  # the GPU's driver where the system keeps it.
  linux = pkgs.stdenv.hostPlatform.isLinux;
  webgpu = pkgs.stdenv.mkDerivation rec {
    pname = "webgpu";
    version = "0.6.2";
    src = pkgs.fetchurl {
      url = "https://registry.npmjs.org/webgpu/-/webgpu-${version}.tgz";
      hash = "sha512-3L4GfmqJLvYUIEWJngEQY+2HQiUlAFkg8+P8NDDj3Xx5hHHIFO/r8JW+ynfqBj7kHN4mbnwO74uB+lrRtLhp4Q==";
    };
    platform =
      {
        x86_64-linux = "linux-x64";
        aarch64-linux = "linux-arm64";
        x86_64-darwin = "darwin-universal";
        aarch64-darwin = "darwin-universal";
      }
      .${pkgs.stdenv.hostPlatform.system};
    nativeBuildInputs = pkgs.lib.optionals linux [ pkgs.autoPatchelfHook ];
    buildInputs = pkgs.lib.optionals linux [ pkgs.stdenv.cc.cc.lib ];
    appendRunpaths = pkgs.lib.optionals linux [ "${pkgs.vulkan-loader}/lib" ];
    dontBuild = true;
    installPhase = ''
      mkdir -p $out/dist
      cp index.js package.json LICENSE.md $out/
      cp -r dist/$platform $out/dist/
    '';
  };
in
pkgs.mkShell {
  SNAIL_WEBGPU = webgpu;
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
