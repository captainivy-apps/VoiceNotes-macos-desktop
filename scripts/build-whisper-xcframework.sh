#!/usr/bin/env bash
#
# Build a universal (arm64 + x86_64) macOS whisper.xcframework from the
# vendored whisper.cpp sources. CoreML + Metal + BLAS are enabled. CoreML is
# used automatically on Apple Silicon when a ggml-<model>-encoder.mlmodelc
# sits next to the ggml model; otherwise it falls back to Metal/CPU
# (WHISPER_COREML_ALLOW_FALLBACK).
#
# Usage:
#   scripts/build-whisper-xcframework.sh
#
# Requires: Xcode (with accepted license), cmake >= 3.28, libtool, dsymutil.
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WHISPER_DIR="${WHISPER_DIR:-$REPO_ROOT/Vendor/whisper.cpp}"
BUILD_DIR="build-macos"
FRAMEWORK_NAME="whisper"
OUT_DIR="$REPO_ROOT/Frameworks"
XCFRAMEWORK="$OUT_DIR/${FRAMEWORK_NAME}.xcframework"

MACOS_MIN_OS_VERSION="${MACOS_MIN_OS_VERSION:-13.0}"

export PATH="/usr/local/bin:$PATH"

check_tool() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "Error: '$1' not found. $2" >&2
        exit 1
    fi
}

echo "==> Checking required tools"
check_tool cmake "Install with: brew install cmake"
check_tool xcodebuild "Install Xcode and run: sudo xcodebuild -license accept"
check_tool libtool "Included with Xcode Command Line Tools"
check_tool dsymutil "Included with Xcode Command Line Tools"

if [[ ! -f "$WHISPER_DIR/CMakeLists.txt" ]]; then
    echo "Error: whisper.cpp sources not found at $WHISPER_DIR" >&2
    echo "Run: git submodule update --init --recursive" >&2
    exit 1
fi

echo "==> Configuring whisper.cpp ($BUILD_DIR)"
cd "$WHISPER_DIR"
rm -rf "$BUILD_DIR"

cmake -B "$BUILD_DIR" -G "Unix Makefiles" \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=OFF \
    -DWHISPER_BUILD_EXAMPLES=OFF \
    -DWHISPER_BUILD_TESTS=OFF \
    -DWHISPER_BUILD_SERVER=OFF \
    -DWHISPER_COREML=ON \
    -DWHISPER_COREML_ALLOW_FALLBACK=ON \
    -DGGML_METAL=ON \
    -DGGML_METAL_EMBED_LIBRARY=ON \
    -DGGML_METAL_USE_BF16=ON \
    -DGGML_BLAS=ON \
    -DGGML_BLAS_VENDOR=Apple \
    -DGGML_OPENMP=OFF \
    -DGGML_NATIVE=OFF \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="$MACOS_MIN_OS_VERSION" \
    -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" \
    -DCMAKE_C_FLAGS="-Wno-macro-redefined -Wno-shorten-64-to-32" \
    -DCMAKE_CXX_FLAGS="-Wno-macro-redefined -Wno-shorten-64-to-32" \
    -S .

echo "==> Building (Release)"
cmake --build "$BUILD_DIR" -j "$(sysctl -n hw.ncpu)"

echo "==> Locating static libraries"
find_lib() {
    local name="$1"
    local found
    found="$(find "$BUILD_DIR" -type f -name "$name" -not -path "*/CMakeFiles/*" | head -n 1)"
    if [[ -z "$found" ]]; then
        echo "Error: could not find $name under $BUILD_DIR" >&2
        exit 1
    fi
    echo "$found"
}

LIBS=(
    "$(find_lib libwhisper.a)"
    "$(find_lib libwhisper.coreml.a)"
    "$(find_lib libggml.a)"
    "$(find_lib libggml-base.a)"
    "$(find_lib libggml-cpu.a)"
    "$(find_lib libggml-metal.a)"
    "$(find_lib libggml-blas.a)"
)

for lib in "${LIBS[@]}"; do
    echo "    $lib"
done

echo "==> Assembling ${FRAMEWORK_NAME}.framework"
FW_DIR="$WHISPER_DIR/$BUILD_DIR/framework/${FRAMEWORK_NAME}.framework"
rm -rf "$WHISPER_DIR/$BUILD_DIR/framework"
mkdir -p "$FW_DIR/Versions/A/Headers" \
         "$FW_DIR/Versions/A/Modules" \
         "$FW_DIR/Versions/A/Resources"
ln -sf A "$FW_DIR/Versions/Current"
ln -sf Versions/Current/Headers "$FW_DIR/Headers"
ln -sf Versions/Current/Modules "$FW_DIR/Modules"
ln -sf Versions/Current/Resources "$FW_DIR/Resources"
ln -sf "Versions/Current/${FRAMEWORK_NAME}" "$FW_DIR/${FRAMEWORK_NAME}"

HEADERS_DIR="$FW_DIR/Versions/A/Headers"
cp "$WHISPER_DIR/include/whisper.h" "$HEADERS_DIR/"
for header in ggml.h ggml-alloc.h ggml-backend.h ggml-metal.h ggml-cpu.h ggml-blas.h gguf.h; do
    cp "$WHISPER_DIR/ggml/include/$header" "$HEADERS_DIR/"
done

cat > "$FW_DIR/Versions/A/Modules/module.modulemap" <<'EOF'
framework module whisper {
    header "whisper.h"
    header "ggml.h"
    header "ggml-alloc.h"
    header "ggml-backend.h"
    header "ggml-metal.h"
    header "ggml-cpu.h"
    header "ggml-blas.h"
    header "gguf.h"

    link "c++"
    link framework "Accelerate"
    link framework "Metal"
    link framework "CoreML"
    link framework "Foundation"

    export *
}
EOF

cat > "$FW_DIR/Versions/A/Resources/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>${FRAMEWORK_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>org.ggml.whisper</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${FRAMEWORK_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>FMWK</string>
    <key>CFBundleShortVersionString</key>
    <string>1.8.5</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>MinimumOSVersion</key>
    <string>${MACOS_MIN_OS_VERSION}</string>
    <key>CFBundleSupportedPlatforms</key>
    <array>
        <string>MacOSX</string>
    </array>
    <key>DTPlatformName</key>
    <string>macosx</string>
    <key>DTSDKName</key>
    <string>macosx</string>
</dict>
</plist>
EOF

echo "==> Combining static libraries"
TEMP_DIR="$WHISPER_DIR/$BUILD_DIR/temp"
rm -rf "$TEMP_DIR"
mkdir -p "$TEMP_DIR"
libtool -static -o "$TEMP_DIR/combined.a" "${LIBS[@]}" 2>/dev/null

OUTPUT_LIB="$FW_DIR/Versions/A/${FRAMEWORK_NAME}"
echo "==> Creating universal dynamic library"
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
xcrun -sdk macosx clang++ -dynamiclib \
    -isysroot "$SDK_PATH" \
    -arch arm64 -arch x86_64 \
    -mmacosx-version-min="$MACOS_MIN_OS_VERSION" \
    -Wl,-force_load,"$TEMP_DIR/combined.a" \
    -framework Foundation -framework Metal -framework Accelerate -framework CoreML \
    -install_name "@rpath/${FRAMEWORK_NAME}.framework/Versions/Current/${FRAMEWORK_NAME}" \
    -o "$OUTPUT_LIB"

echo "==> Stripping debug info"
xcrun strip -S "$OUTPUT_LIB" -o "$TEMP_DIR/stripped_lib"
mv "$TEMP_DIR/stripped_lib" "$OUTPUT_LIB"
rm -rf "$TEMP_DIR" "$OUTPUT_LIB.dSYM"
if [[ -d "$FW_DIR/Versions/A/Resources" ]]; then :; fi

echo "==> Creating xcframework"
mkdir -p "$OUT_DIR"
rm -rf "$XCFRAMEWORK"
xcodebuild -create-xcframework \
    -framework "$FW_DIR" \
    -output "$XCFRAMEWORK" >/dev/null

echo "==> Verifying architectures"
lipo -info "$XCFRAMEWORK/macos-arm64_x86_64/${FRAMEWORK_NAME}.framework/Versions/A/${FRAMEWORK_NAME}"

echo ""
echo "Done: $XCFRAMEWORK"
