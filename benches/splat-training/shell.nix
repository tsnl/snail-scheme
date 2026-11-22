# `nix-shell benches/splat-training` enters the environment `default.nix`
# describes. Scripts run their commands in it through its `splat-bench`
# command instead, since an FHS environment's shell takes no `--run`.
{ ... }@args: (import ./default.nix args).env
