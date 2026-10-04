# 语音记事 · macOS 桌面版

原生 macOS 桌面应用（Swift + SwiftUI），功能与 Android 版「语音记事」保持一致：

**录音 → 本地 whisper.cpp 语音识别（识别稿）→ 可选 OpenAI 兼容 LLM 润色（润色稿）→ 本地保存与管理。**

- 本地优先：录音、识别稿、润色稿均保存在本机
- 离线 ASR：whisper.cpp 模型按需下载到本地
- 支持 Apple Silicon 与 Intel Mac（Universal Binary：arm64 + x86_64）

## 功能一览

- **录制页**：大按钮录音、录音时长、实时波形；支持导入 WAV/MP3/M4A 等音频文件
- **识别稿**：录音保存后询问是否立即识别；识别完成可编辑
- **润色稿**：可用 LLM 加工识别稿，或直接另存为润色稿
- **记事列表**：按时间倒序，支持多选删除
- **记事详情**：录音试听（波形 + 播放进度）、识别稿/润色稿标签页编辑、分别删除录音/识别稿/润色稿、删除整篇、复制、导出、上一篇/下一篇
- **设置**：ASR 模型下载/镜像下载/删除/切换（镜像地址可自定义）；多组 LLM 配置（OpenAI / Ollama / DeepSeek 等）增删改、设为默认、测试连接；帮助
- 处理过程展示进度与耗时；错误提示清晰

## 技术栈

| 模块 | 实现 |
|------|------|
| UI | SwiftUI（`NavigationSplitView`） |
| 本地 ASR | whisper.cpp 1.8.5（Metal + BLAS + Accelerate + Core ML），`whisper.xcframework` |
| 本地存储 | SQLite（系统 `libsqlite3`） |
| 音频 | AVFoundation（`AVCaptureSession` 采集 / `AVAudioConverter` / `AVAudioPlayer`） |
| LLM | OpenAI 兼容 `/v1/chat/completions`，SSE 流式 |
| 最低系统 | macOS 13.0（Ventura） |
| Bundle ID | `com.dafei.voicenotes` |

## 环境要求

- macOS 13+
- Xcode（首次需同意许可）：`sudo xcodebuild -license accept`
- CMake（仅构建 whisper.xcframework 时需要）：`brew install cmake`
- 若 Xcode 提示插件缺失：`xcodebuild -runFirstLaunch`

## 首次构建

```bash
# 1. 克隆（含 whisper.cpp 子模块）
git clone --recursive https://github.com/captainivy-apps/VoiceNotes-macos-desktop.git
cd VoiceNotes-macos-desktop
# 若已克隆但未拉子模块：
git submodule update --init --recursive

# 2. 构建 Universal 的 whisper.xcframework（已随仓库提交，可跳过；重新生成时执行）
./scripts/build-whisper-xcframework.sh

# 3. 构建 Universal .app（输出到 dist/VoiceNotes.app）
./scripts/build-universal.sh
```

开发时也可直接打开 `VoiceNotes.xcodeproj`，选择 `VoiceNotes` scheme 运行。

### 构建产物架构

`scripts/build-universal.sh` 与 xcframework 均为 `x86_64 arm64` 双架构。校验：

```bash
lipo -info dist/VoiceNotes.app/Contents/MacOS/VoiceNotes
lipo -info dist/VoiceNotes.app/Contents/Frameworks/whisper.framework/Versions/A/whisper
```

## 首次使用

1. 打开 **设置 → 录制**，下载至少一个 ASR 模型（建议先下载 **Base**，约 142 MB），并设为当前模型。
2. 如需 LLM 润色，在 **设置 → LLM 配置** 添加一组或多组配置并设为默认；也可在录制页/详情页临时切换。
3. 回到 **录制** 页开始录音或导入音频。

### LLM 配置示例

- **云端 OpenAI**：Base URL `https://api.openai.com`，填写 API Key，Model `gpt-4o-mini`
- **本地 / 局域网 LLM**（Ollama、LM Studio 等）：Base URL 填局域网地址，API Key 可留空
  - 例如 Ollama：`http://127.0.0.1:11434`，Model 如 `qwen2.5:7b`

## 内置 ASR 模型

| 模型 ID | 大小 | 说明 |
|---------|------|------|
| tiny | 75 MB | 最快，精度较低 |
| tiny-q5_1 | 30.7 MB | 量化 tiny，Intel CPU 推荐 |
| base | 142 MB | 推荐默认 |
| base-q5_1 | 56.9 MB | 量化 base，Intel CPU 推荐 |
| small | 466 MB | 更高精度 |
| small-q5_1 | 181.3 MB | 量化 small，Intel CPU 推荐 |
| medium | 1.5 GB | 高精度，推理较慢 |
| large-v3-turbo-q5_0 | 547 MB | 量化大模型 |

模型从 HuggingFace `ggerganov/whisper.cpp` 按需下载；`base`、`base-q5_1`、`small-q5_1`、`tiny-q5_1`、
`large-v3-turbo-q5_0` 支持镜像加速，并在下载后校验 SHA-256。量化（Q5）模型在 Intel 上利用
AVX2 整型内核，速度明显快于 f16 模型；在 Apple Silicon 上会复用同名非量化模型的 Core ML
编码器（若已安装），否则回退到 Metal。

## Core ML 加速（Apple Silicon）

whisper.xcframework 已编译进 Core ML 支持（`WHISPER_COREML=ON`，并开启
`WHISPER_COREML_ALLOW_FALLBACK`）。**在 Apple Silicon 上**，若模型同目录存在
对应的 Core ML 编码器 `ggml-<模型>-encoder.mlmodelc`，whisper.cpp 会自动用它
把编码器跑在 Neural Engine 上（约 2–3× 提速）；否则自动回退到 Metal/CPU。
Intel Mac 无 ANE，会回退到（已启用 AVX2 的）CPU。

应用内下载：在 **设置 → 录制 → 已下载的模型 → Core ML 编码器**，可分别从
**原版（Hugging Face）** 与 **镜像** 下载 `ggml-<模型>-encoder.mlmodelc.zip`，
解压到 `models/` 目录；也可 **导入 .mlpackage** 用本机 `coremlc` 现场编译。
镜像地址需在 **设置 → 录制 → 模型下载镜像** 中自行填写（初始为空，未填写时不显示镜像
下载选项），模型与编码器下载共用该地址。
镜像下载会校验 SHA-256；原版编码器 zip 与镜像构建产物字节不同，故原版不做校验。
Base / Small / Medium / Large v3 Turbo / Tiny 均提供编码器。量化（Q5）模型不单独提供
编码器，但在 Apple Silicon 上会**自动复用同名非量化模型**的编码器
（whisper.cpp 查找时会去掉 `-qX_X` 后缀）。

### 开发者：生成并发布 Core ML 编码器

1. 准备 Python 环境（3.9–3.12）并安装依赖：

   ```bash
   pip install 'coremltools==8.3.0' 'torch==2.2.2' 'numpy<2' openai-whisper ane_transformers tiktoken numba
   ```

2. 生成并编译编码器（默认 `base small medium large-v3-turbo`，可指定模型）：

   ```bash
   ./scripts/build-coreml-encoders.sh            # 默认四个
   ./scripts/build-coreml-encoders.sh base tiny  # 指定模型
   ```

   脚本调用 `Vendor/whisper.cpp/models/convert-whisper-to-coreml.py`
   （`--encoder-only True --optimize-ane True`），用 `xcrun coremlc` 编译，打包为
   `dist-coreml-mirror/ggml-<模型>-encoder.mlmodelc.zip`，最后打印 SHA-256。

3. 上传镜像并校验：

   ```bash
   rsync -avP dist-coreml-mirror/ggml-<模型>-encoder.mlmodelc.zip \
     target-mirror-server:/path
   ssh target-mirror-server \
     'sha256sum /path/ggml-<模型>-encoder.mlmodelc.zip'
   ```

4. 将校验值写入 `VoiceNotes/Models/AsrModelInfo.swift` 的 `coremlMirrorSHA256`，
   并确认 `coremlDownloadURL`（原版，HuggingFace `ggerganov/whisper.cpp`）与
   `coremlMirrorPath`（镜像相对路径，如 `ggml-base-encoder.mlmodelc.zip`）均已填写。
   镜像地址不在代码中写死：应用以 `AppSettings.mirrorBaseURL`（设置页填写，初始为空）
   拼接 `coremlMirrorPath`。

## Intel CPU 优化（量化模型）

量化（Q5）模型在 Intel 上走 AVX2 整型点积内核，明显快于 f16；应用已内置
`tiny-q5_1`、`base-q5_1`、`small-q5_1` 三个选项，下载后校验 SHA-256。

### 开发者：新增 / 更新量化模型

1. 从 HuggingFace `ggerganov/whisper.cpp` 下载目标 `ggml-<模型>-qX_X.bin`。
2. 上传镜像并记录校验值：
   ```bash
   rsync -avP ggml-<模型>-qX_X.bin \
     target-mirror-server:/path
   shasum -a 256 ggml-<模型>-qX_X.bin
   ```
3. 在 `VoiceNotes/Models/AsrModelInfo.swift` 的 `AsrModels.all` 增加条目：`fileName`、
   `downloadURL`（HF）、`mirrorPath`（镜像相对路径）、`sha256`、`quantized: true`。

### 开发者：重新构建 AVX2 / NEON 版 xcframework

务必使用 `scripts/build-whisper-xcframework.sh`（按架构分别编译）。自行 CMake 时
**不要**设置通用的 `CMAKE_OSX_ARCHITECTURES="arm64;x86_64"`，否则 ggml 会退化为 generic
内核（极慢）。构建后可用反汇编确认 x86_64 slice 已启用 AVX2：

```bash
FW=Frameworks/whisper.xcframework/macos-arm64_x86_64/whisper.framework/Versions/A/whisper
lipo -thin x86_64 "$FW" -output /tmp/whisper_x86
otool -tv /tmp/whisper_x86 | grep -c '%ymm'   # 应远大于 0
```

## 数据存储

应用数据保存在 `~/Library/Application Support/com.dafei.voicenotes/`：

- 录音：`recordings/rec_*.wav`（16 kHz 单声道 PCM）
- 数据库与文本：`voice_notes.db`（SQLite）
- ASR 模型：`models/ggml-*.bin`

导出的录音/识别稿/润色稿通过系统保存面板写入，默认目录为「下载」。

## 架构说明

- 通用二进制：`arm64` 使用 Metal + flash attention 加速，若安装了 Core ML 编码器则进一步在 Neural Engine 上运行编码器；`x86_64`（Intel）自动回退到 CPU（Accelerate/BLAS）。
- **按架构分别编译**：`scripts/build-whisper-xcframework.sh` 对 `arm64` 与 `x86_64` 各配置一次 CMake，再 `lipo` 成通用库。这很关键——若直接以 `arm64;x86_64` 通用配置构建，ggml 的架构探测会返回 `UNKNOWN`，从而静默禁用 x86 的 AVX2/FMA 与 ARM 的 NEON 优化内核，退化为极慢的 generic 实现。`x86_64` 显式启用 SSE4.2/AVX/AVX2/FMA/F16C/BMI2（`AVX512` 关闭以保证兼容）。macOS 13 支持的所有 Intel Mac 均支持 AVX2。
- 内置 Silero VAD（`VoiceNotes/Resources/ggml-silero-v5.1.2.bin`）：识别前跳过静音段，对停顿较多的口述提速并减少幻觉；未内置时也可将同名模型放入 `models/` 目录。
- 长音频按约 5 分钟分窗、1 秒重叠分段识别，避免一次性占用过多内存。
- 识别语言默认「自动检测」（whisper 按音频判断），可在设置中固定为中文/English 等。解码保留熵检查触发的温度回退（`temperature_inc = 0.2`，仅在低熵/重复段重解码，用于打断重复循环）、抑制非语音 token（`suppress_nst`），并保持各段独立（`no_context = true`，避免一段的幻觉污染后续段）；`greedy.best_of = 5` 仅在回退时扩充候选，温度 0 的常规解码仍只用 1 个 decoder，故不影响常规速度。主要提速来自 VAD 跳过静音、按物理核数设置线程、Metal / Core ML 与自动语言检测。此外对输出做重复片段折叠作为兜底。

## 工程结构

```
VoiceNotes.xcodeproj         # Xcode 工程（使用文件系统同步目录）
VoiceNotes/
  Models/                    # DiaryEntry / AsrModelInfo / LlmProfile / AppSettings
  Data/                      # Paths / SQLiteDatabase / DiaryStore
  Audio/                     # AudioRecorder / WavFile / AudioImporter / AudioPlayer
  ASR/                       # WhisperEngine / ModelDownloader / AsrProgress / RepetitionFilter
  LLM/                       # OpenAiCompatibleClient / LlmProgress
  Export/                    # Exporter / ExportFileNames
  ViewModels/                # Record / DiaryList / DiaryDetail / Settings
  Views/                     # Root / Record / Notes / DiaryDetail / Settings / Help + Components
  Resources/                 # 内置 Silero VAD 模型（ggml-silero-v5.1.2.bin）
Frameworks/whisper.xcframework
Vendor/whisper.cpp           # git submodule（v1.8.5）
Support/                     # Info.plist / entitlements
scripts/                     # build-whisper-xcframework / build-universal / build-coreml-encoders
VoiceNotesTests/             # XCTest
```

## 测试

```bash
xcodebuild -project VoiceNotes.xcodeproj -scheme VoiceNotes -destination 'platform=macOS' test
```

## 说明

本项目参考同仓库的 Android 版「语音记事」实现，功能对齐。whisper.cpp 遵循其 MIT 许可，详见 `LICENSE`。
