#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
sdk="${1:-iphoneos}"
case "$sdk" in
  iphoneos) rust_target=aarch64-apple-ios ;;
  iphonesimulator) rust_target=aarch64-apple-ios-sim ;;
  *) echo 'Unsupported SDK'; exit 1 ;;
esac
mkdir -p Native/deps
fetch() {
  local url="$1" revision="$2" folder="$3"
  if [ ! -d "$folder/.git" ]; then git init -q "$folder"; git -C "$folder" remote add origin "$url"; fi
  git -C "$folder" fetch --depth 1 origin "$revision"
  git -C "$folder" checkout --detach FETCH_HEAD
}
fetch https://github.com/0xShug0/audio.cpp.git 6b0260ec8002e69a20c4ab2949fc312113c95bdf Native/deps/audio
fetch https://github.com/pnnbao97/sea-g2p.git e825173f235d08ea19315b2b279fb11153b44cea Native/deps/sea
python3 - <<'PY'
from pathlib import Path
p=Path('Native/deps/sea/Cargo.toml')
p.write_text(p.read_text().replace('crate-type = ["cdylib", "rlib"]','crate-type = ["staticlib"]'))
PY
rustup target add "$rust_target"
cargo build --manifest-path Native/deps/sea/Cargo.toml --release --locked --no-default-features --features capi --target "$rust_target"
repo="$PWD"
cmake -S Native -B "Native/build/$sdk" -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_SYSROOT="$sdk" -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=17.0 -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY \
  -DAUDIO_SOURCE="$repo/Native/deps/audio" -DSEA_SOURCE="$repo/Native/deps/sea" \
  -DSEA_LIBRARY="$repo/Native/deps/sea/target/$rust_target/release/libsea_g2p_rs.a"
cmake --build "Native/build/$sdk" --target studio_voice --parallel 3
test -s "Native/build/$sdk/libStudioVoice.a"
mkdir -p ThreadsStudio/Library/voice/licenses
cp Native/deps/audio/LICENSE ThreadsStudio/Library/voice/licenses/audio-cpp.txt
cp Native/deps/sea/LICENSE ThreadsStudio/Library/voice/licenses/sea-g2p.txt
cp Native/deps/audio/external/ggml/LICENSE ThreadsStudio/Library/voice/licenses/ggml.txt
echo "Native VieNeu ready: $sdk"
