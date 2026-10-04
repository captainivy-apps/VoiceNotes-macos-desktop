#!/usr/bin/env bash
#
# Build a universal (arm64 + x86_64) macOS whisper.xcframework from the
# vendored whisper.cpp sources. CoreML + Metal + BLAS are enabled. CoreML is
# used automatically on Apple Silicon when a ggml-<model>-encoder.mlmodelc
# sits next to the ggml model; otherwise it falls back to Metal/CPU
# (WHISPER_COREML_ALLOW_FALLBACK).
#
# Each architecture is configured and compiled in its own CMake build tree.
# This is REQUIRED for correct CPU SIMD: passing a universal
# CMAKE_OSX_ARCHITECTURES ("arm64;x86_64") makes ggml's architecture detection
# report "UNKNOWN", which silently disables the SSE/AVX2 (x86) and NEON (ARM)
# optimized kernels and falls back to the slow generic implementations.
#
# Usage:
#   scripts/build-whisper-xcframework.sh
#
# Requires: Xcode (with accepted license), cmake >= 3.28, libtool, dsymutil.
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WHISPER_DIR="${WHISPER_DIR:-$REPO_ROOT/Vendor/whisper.cpp}"
FRAMEWORK_NAME="whisper"
OUT_DIR="$REPO_ROOT/Frameworks"
XCFRAMEWORK="$OUT_DIR/${FRAMEWORK_NAME}.xcframework"
FW_BUILD_DIR="$REPO_ROOT/build-framework"

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

cd "$WHISPER_DIR"

find_lib() {
    local build_dir="$1"
    local name="$2"
    local found
    found="$(find "$build_dir" -type f -name "$name" -not -path "*/CMakeFiles/*" | head -n 1)"
    if [[ -z "$found" ]]; then
        echo "Error: could not find $name under $build_dir" >&2
        exit 1
    fi
    echo "$found"
}

# Global set by build_arch to the produced single-arch dynamic library path.
ARCH_LIB=""

build_arch() {
    local arch="$1"
    local build_dir="build-macos-$arch"
    local arch_flags=()

    if [[ "$arch" == "x86_64" ]]; then
        # macOS 13 (Ventura) requires 2017+ Intel Macs, all of which support
        # AVX2/FMA/F16C/BMI2. Enable them explicitly. GGML_NATIVE=OFF keeps
        # AVX512 off so the binary still runs on every supported CPU.
        arch_flags+=(
            -DGGML_SSE42=ON -DGGML_AVX=ON -DGGML_AVX2=ON
            -DGGML_FMA=ON -DGGML_F16C=ON -DGGML_BMI2=ON
            -DGGML_AVX512=OFF
        )
    elif [[ "$arch" == "arm64" ]]; then
        # All Apple Silicon (M1+) supports dot-product and FP16 arithmetic.
        arch_flags+=(-DGGML_CPU_ARM_ARCH=armv8.2-a+dotprod+fp16)
    fi

    echo "==> Configuring whisper.cpp for $arch ($build_dir)"
    rm -rf "$build_dir"
    cmake -B "$build_dir" -G "Unix Makefiles" \
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
        -DCMAKE_OSX_ARCHITECTURES="$arch" \
        -DCMAKE_C_FLAGS="-Wno-macro-redefined -Wno-shorten-64-to-32" \
        -DCMAKE_CXX_FLAGS="-Wno-macro-redefined -Wno-shorten-64-to-32" \
        "${arch_flags[@]}" \
        -S .

    echo "==> Building $arch (Release)"
    cmake --build "$build_dir" -j "$(sysctl -n hw.ncpu)"

    local libs=(
        "$(find_lib "$build_dir" libwhisper.a)"
        "$(find_lib "$build_dir" libwhisper.coreml.a)"
        "$(find_lib "$build_dir" libggml.a)"
        "$(find_lib "$build_dir" libggml-base.a)"
        "$(find_lib "$build_dir" libggml-cpu.a)"
        "$(find_lib "$build_dir" libggml-metal.a)"
        "$(find_lib "$build_dir" libggml-blas.a)"
    )

    echo "==> Combining static libraries for $arch"
    local temp_dir="$build_dir/temp"
    rm -rf "$temp_dir"
    mkdir -p "$temp_dir"
    libtool -static -o "$temp_dir/combined-$arch.a" "${libs[@]}" 2>/dev/null

    local sdk_path
    sdk_path="$(xcrun --sdk macosx --show-sdk-path)"
    local out="$temp_dir/${FRAMEWORK_NAME}-$arch"
    echo "==> Creating $arch dynamic library"
    xcrun -sdk macosx clang++ -dynamiclib \
        -isysroot "$sdk_path" \
        -arch "$arch" \
        -mmacosx-version-min="$MACOS_MIN_OS_VERSION" \
        -Wl,-force_load,"$temp_dir/combined-$arch.a" \
        -framework Foundation -framework Metal -framework Accelerate -framework CoreML \
        -install_name "@rpath/${FRAMEWORK_NAME}.framework/Versions/Current/${FRAMEWORK_NAME}" \
        -o "$out"

    echo "==> Stripping debug info for $arch"
    xcrun strip -S "$out" -o "$out.stripped"
    mv "$out.stripped" "$out"
    rm -rf "$out.dSYM"

    ARCH_LIB="$out"
}

build_arch arm64
LIB_ARM64="$ARCH_LIB"
build_arch x86_64
LIB_X86_64="$ARCH_LIB"

echo "==> Assembling ${FRAMEWORK_NAME}.framework"
FW_DIR="$FW_BUILD_DIR/${FRAMEWORK_NAME}.framework"
rm -rf "$FW_BUILD_DIR"
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

echo "==> Creating universal dynamic library"
OUTPUT_LIB="$FW_DIR/Versions/A/${FRAMEWORK_NAME}"
lipo -create "$LIB_ARM64" "$LIB_X86_64" -output "$OUTPUT_LIB"
lipo -info "$OUTPUT_LIB"

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
