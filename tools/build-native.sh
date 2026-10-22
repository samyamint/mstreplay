#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
output=${1:-"$root/bin/Release/streplay-encoder"}
stage="$root/obj/native"
mkdir -p "$stage" "$(dirname "$output")"
for arch in arm64 x86_64; do
    xcrun swiftc -swift-version 5 -O -target "$arch-apple-macosx12.0" \
        "$root/native/Encoder.swift" -o "$stage/streplay-encoder-$arch"
done
xcrun lipo -create "$stage/streplay-encoder-arm64" "$stage/streplay-encoder-x86_64" -output "$output"
codesign --force --sign - "$output"
chmod +x "$output"
