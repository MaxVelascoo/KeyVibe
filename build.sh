#!/bin/sh
set -eu
cd "$(dirname "$0")"
mkdir -p build/KeyVibe.app/Contents/MacOS
clang -Wall -Wextra -Wno-unused-parameter -fobjc-arc -O2 -mmacosx-version-min=13.0 src/main.m -framework Cocoa -framework AVFoundation -framework IOKit -framework ApplicationServices -framework UniformTypeIdentifiers -o build/KeyVibe.app/Contents/MacOS/KeyVibe
clang -Wall -Wextra -Wno-unused-parameter -fobjc-arc -O2 src/probe.m -framework Foundation -framework IOKit -o build/sensor-probe
cp Info.plist build/KeyVibe.app/Contents/Info.plist
# A fixed designated requirement prevents macOS from tying Input Monitoring
# to the binary hash, which changes on every local build.
codesign --force --sign - --requirements '=designated => identifier "local.maxvelasco.keyvibe"' build/KeyVibe.app
./build/KeyVibe.app/Contents/MacOS/KeyVibe --self-test
