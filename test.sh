#!/bin/sh
set -eu
cd "$(dirname "$0")"
mkdir -p build
clang -Wall -Wextra -Wno-unused-function -fobjc-arc -O2 tests/imported-sound.m -framework Foundation -framework AVFoundation -o build/test-imports
./build/test-imports
clang -Wall -Wextra -Wno-unused-function -fobjc-arc -O2 tests/sound-pack.m -framework Foundation -framework AVFoundation -o build/test-packs
./build/test-packs
