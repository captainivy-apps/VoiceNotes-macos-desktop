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
- **设置**：ASR 模型下载/镜像下载/删除/切换；多组 LLM 配置（OpenAI / Ollama / DeepSeek 等）增删改、设为默认、测试连接；帮助
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
| base | 142 MB | 推荐默认 |
| small | 466 MB | 更高精度 |
| medium | 1.5 GB | 高精度，推理较慢 |
| large-v3-turbo-q5_0 | 547 MB | 量化大模型 |

模型从 HuggingFace `ggerganov/whisper.cpp` 按需下载；`base` 与 `large-v3-turbo-q5_0` 支持镜像加速。

## Core ML 加速（Apple Silicon）

whisper.xcframework 已编译进 Core ML 支持（`WHISPER_COREML=ON`，并开启
`WHISPER_COREML_ALLOW_FALLBACK`）。**在 Apple Silicon 上**，若模型同目录存在
对应的 Core ML 编码器 `ggml-<模型>-encoder.mlmodelc`，whisper.cpp 会自动用它
把编码器跑在 Neural Engine 上（约 2–3× 提速）；否则自动回退到 Metal/CPU，
Intel Mac 亦不受影响（无 ANE，始终回退）。

编码器由应用内置下载：在 **设置 → 录制 → 已下载的模型 → 下载编码器**，
应用从镜像下载 `ggml-<模型>-encoder.mlmodelc.zip`、校验 SHA-256 后解压到
`models/` 目录。也支持 **导入 .mlpackage** 用本机 `coremlc` 现场编译。

Base / Small / Medium / Large v3 Turbo 均提供编码器；编码器打包与校验值由
`scripts/build-coreml-encoders.sh` 生成（需 `coremltools==8.3.0`、
`torch==2.2.2`、`openai-whisper`、`ane_transformers` 等）。产物位于
`dist-coreml-mirror/`，需上传到镜像站点 `https://www.galaxyrover.com/mirrors/`
的对应路径。当前校验值记录在 `VoiceNotes/Models/AsrModelInfo.swift`。

## 数据存储

应用数据保存在 `~/Library/Application Support/com.dafei.voicenotes/`：

- 录音：`recordings/rec_*.wav`（16 kHz 单声道 PCM）
- 数据库与文本：`voice_notes.db`（SQLite）
- ASR 模型：`models/ggml-*.bin`

导出的录音/识别稿/润色稿通过系统保存面板写入，默认目录为「下载」。

## 架构说明

- 通用二进制：`arm64` 使用 Metal + flash attention 加速，若安装了 Core ML 编码器则进一步在 Neural Engine 上运行编码器；`x86_64`（Intel）自动回退到 CPU（Accelerate/BLAS）。这是因为部分 Intel Mac 上 Metal 后端可能产生错误结果。
- 长音频按约 5 分钟分窗、1 秒重叠分段识别，避免一次性占用过多内存。
- 识别语言默认「自动检测」（whisper 按音频判断），可在设置中固定为中文/English 等；解码使用 `greedy.best_of = 1` 以加快速度。

## 工程结构

```
VoiceNotes.xcodeproj         # Xcode 工程（使用文件系统同步目录）
VoiceNotes/
  Models/                    # DiaryEntry / AsrModelInfo / LlmProfile / AppSettings
  Data/                      # Paths / SQLiteDatabase / DiaryStore
  Audio/                     # AudioRecorder / WavFile / AudioImporter / AudioPlayer
  ASR/                       # WhisperEngine / ModelDownloader / AsrProgress
  LLM/                       # OpenAiCompatibleClient / LlmProgress
  Export/                    # Exporter / ExportFileNames
  ViewModels/                # Record / DiaryList / DiaryDetail / Settings
  Views/                     # Root / Record / Notes / DiaryDetail / Settings / Help + Components
Frameworks/whisper.xcframework
Vendor/whisper.cpp           # git submodule（v1.8.5）
Support/                     # Info.plist / entitlements
scripts/                     # 构建脚本
VoiceNotesTests/             # XCTest
```

## 测试

```bash
xcodebuild -project VoiceNotes.xcodeproj -scheme VoiceNotes -destination 'platform=macOS' test
```

## 说明

本项目参考同仓库的 Android 版「语音记事」实现，功能对齐。whisper.cpp 遵循其 MIT 许可，详见 `LICENSE`。
