#!/usr/bin/env bash
# A quick check that the devcontainer works, run inside it from the root of
# the checkout. It runs what the devcontainer runs when it is created, then
# uses each kind of tool once: the Rust crates offline, a program through
# Chibi, Binaryen and Node, and Chromium. CI runs it in the image podman
# builds (.github/workflows/devcontainer.yml).
set -euo pipefail

# What the devcontainer runs once it is created, if anything.
bash -c "$(node -p "require('./.devcontainer/devcontainer.json').postCreateCommand ?? 'true'")"
cargo test --offline --manifest-path crates/snail-core-support/Cargo.toml
output=$(./scripts/snail-tool run examples/fibonacci.sld)
[ "$output" = "$(cat examples/fibonacci.out)" ] || { echo "fibonacci printed: $output" >&2; exit 1; }
timeout 120 node tests/browser/page.mjs about:blank "$(mktemp -d)/page.png" 1
