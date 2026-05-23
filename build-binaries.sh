#!/bin/bash

# Compiles static binaries for all supported architectures.
# Run this before build-plasmoid.sh when the C source changes

SRC="contents/src/read_hid_sc2.c"
OUT="contents/bin"

compile() {
    local arch=$1
    local cc=$2
    echo "Compiling for $arch..."
    $cc -O2 -static -o "$OUT/read_hid_sc2.$arch" "$SRC" || {
        echo "Error: failed to compile for $arch"
        exit 1
    }
    echo "  -> $OUT/read_hid_sc2.$arch ($(du -h "$OUT/read_hid_sc2.$arch" | cut -f1))"
}

compile x86_64  gcc
compile aarch64 aarch64-linux-gnu-gcc

echo "Done!"
