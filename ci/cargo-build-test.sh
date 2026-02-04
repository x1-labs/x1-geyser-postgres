#!/usr/bin/env bash

set -e
cd "$(dirname "$0")/.."

source ./ci/rust-version.sh stable

export RUSTFLAGS="-D warnings"
export RUSTBACKTRACE=1

# Try to increase file descriptor limit for Solana tests
ulimit -n 1000000 2>/dev/null || ulimit -n 65536 2>/dev/null || true

set -x

# Build/test all host crates
cargo +"$rust_stable" build
cargo +"$rust_stable" test -- --nocapture

exit 0
