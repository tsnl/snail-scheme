# The environment the reference trainers run in. gsplat and the INRIA
# code are PyTorch programs that compile CUDA kernels as they install.
# CUDA, the host compiler that CUDA release supports, and Python come from
# the nixpkgs revision npins pins for the repository. The trainers' Python
# packages come from pip, as their own instructions install them, into
# the virtual environment `setup` makes: gsplat's example trainer reads a
# dozen packages nixpkgs does not carry. pip's wheels expect a
# conventional Linux, so this is an FHS environment, and its one command,
# `splat-bench`, runs bash in it.
{
  sources ? import ../../npins,
  pkgs ? import sources.nixpkgs { config.allowUnfree = true; },
}:

let
  # CUDA 12.8 is the first release for the RTX 5090 (sm_120), and the
  # trainers' PyTorch is built with it; 12.9 is the newest 12.x in nixpkgs.
  # An extension must be compiled by the CUDA major version PyTorch was.
  cuda = pkgs.cudaPackages_12_9;
in
pkgs.buildFHSEnv {
  name = "splat-bench";
  targetPkgs = p: [
    cuda.cudatoolkit
    cuda.backendStdenv.cc
    p.python312
    p.git
    p.ninja
    p.which
    # What the wheels of PyTorch, OpenCV and their neighbours link to.
    p.stdenv.cc.cc.lib
    p.zlib
    p.libGL
    p.glib
    p.libx11
    p.libxcb
    p.libxext
    p.libsm
    p.libice
  ];
  profile = ''
    # Entered from a nix-shell, as the repository's, the environment would
    # keep its build variables, which point compilers and Python at that
    # shell's packages: the kernels would build against its Python.
    for name in $(env | sed -n 's/^\([A-Za-z_][A-Za-z0-9_]*\)=.*/\1/p'); do
      case $name in
        NIX_PATH | NIX_REMOTE | NIX_SSL_CERT_FILE) ;;
        NIX_* | _PYTHON_* | PYTHONPATH | PYTHONHOME | CC | CXX | CPATH | LIBRARY_PATH | PKG_CONFIG_PATH)
          unset "$name"
          ;;
      esac
    done
    # The bench's scripts enter the environment unless this is set.
    export SPLAT_BENCH=1
    export CUDA_HOME=${cuda.cudatoolkit}
    export TORCH_CUDA_ARCH_LIST=12.0
    # NixOS keeps the driver's libcuda here, outside the environment.
    export LD_LIBRARY_PATH=/run/opengl-driver/lib''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
  '';
  runScript = "bash";
}
