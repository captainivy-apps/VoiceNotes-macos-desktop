#!/usr/bin/env bash
#
# Generate + compile Core ML encoders for the ASR models shipped by the app,
# package them as `ggml-<name>-encoder.mlmodelc.zip` for the mirror, and print
# their SHA-256 checksums (used in VoiceNotes/Models/AsrModelInfo.swift and for
# in-app download verification).
#
# Usage:
#   scripts/build-coreml-encoders.sh                 # default: base small medium large-v3-turbo
#   scripts/build-coreml-encoders.sh base small
#
# Requirements:
#   - Xcode command line tools (for `xcrun coremlc`)
#   - Python 3.9–3.12 with coremltools==8.3.0, torch==2.2.2, openai-whisper,
#     ane_transformers, numpy<2, tiktoken, numba. The whisper.cpp conversion
#     script lives at Vendor/whisper.cpp/models/convert-whisper-to-coreml.py.
#
# Output: dist-coreml-mirror/*.zip
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WHISPER_DIR="$REPO_ROOT/Vendor/whisper.cpp"
OUT_DIR="$REPO_ROOT/dist-coreml-mirror"
PYTHON="${PYTHON:-python3}"

MODELS=("$@")
if [[ ${#MODELS[@]} -eq 0 ]]; then
    MODELS=(base small medium large-v3-turbo)
fi

export PATH="/usr/local/bin:$PATH"
export HF_HUB_DISABLE_XET=1

check_tool() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "Error: '$1' not found. $2" >&2
        exit 1
    fi
}

check_tool xcrun "Install Xcode / command line tools"
check_tool ditto "Included with macOS"

if [[ ! -f "$WHISPER_DIR/models/convert-whisper-to-coreml.py" ]]; then
    echo "Error: whisper.cpp sources not found at $WHISPER_DIR" >&2
    exit 1
fi

"$PYTHON" -c "import coremltools, torch, whisper, ane_transformers" 2>/dev/null || {
    echo "Error: Python deps missing. Install: pip install 'coremltools==8.3.0' 'torch==2.2.2' 'numpy<2' openai-whisper ane_transformers tiktoken numba" >&2
    exit 1
}

mkdir -p "$OUT_DIR"
cd "$WHISPER_DIR"

for m in "${MODELS[@]}"; do
    echo "==> Converting $m"
    "$PYTHON" models/convert-whisper-to-coreml.py --model "$m" --encoder-only True --optimize-ane True
    pkg="models/coreml-encoder-${m}.mlpackage"
    [[ -d "$pkg" ]] || { echo "Error: $pkg not produced" >&2; exit 1; }
    echo "==> Compiling $m"
    xcrun coremlc compile "$pkg" "$OUT_DIR" >/dev/null
    src="$OUT_DIR/coreml-encoder-${m}.mlmodelc"
    [[ -d "$src" ]] || { echo "Error: $src not produced" >&2; exit 1; }
    rm -rf "$OUT_DIR/ggml-${m}-encoder.mlmodelc"
    mv "$src" "$OUT_DIR/ggml-${m}-encoder.mlmodelc"
    rm -f "$OUT_DIR/ggml-${m}-encoder.mlmodelc.zip"
    (cd "$OUT_DIR" && ditto -c -k "ggml-${m}-encoder.mlmodelc" "ggml-${m}-encoder.mlmodelc.zip")
done

echo ""
echo "==> Artifacts in $OUT_DIR"
shasum -a 256 "$OUT_DIR"/ggml-*-encoder.mlmodelc.zip
