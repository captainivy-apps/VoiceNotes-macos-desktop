import SwiftUI

private enum SettingsTab: String, CaseIterable, Identifiable {
    case rec = "录制"
    case device = "录音设备"
    case llm = "LLM 配置"
    case help = "帮助"
    var id: String { rawValue }
}

struct SettingsScreen: View {
    let services: AppServices
    @StateObject private var vm: SettingsViewModel
    @State private var tab: SettingsTab = .rec
    @State private var coremlImportModelId: String?

    init(services: AppServices) {
        self.services = services
        _vm = StateObject(wrappedValue: SettingsViewModel(services: services))
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("设置").font(.largeTitle.bold()).frame(maxWidth: .infinity, alignment: .leading).padding(16)
            Picker("", selection: $tab) {
                ForEach(SettingsTab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 16)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch tab {
                    case .rec: recTab
                    case .device: deviceTab
                    case .llm: llmTab
                    case .help: HelpView()
                    }
                }
                .frame(maxWidth: 720, alignment: .leading)
                .padding(16)
            }
        }
        .sheet(isPresented: $vm.editorOpen) {
            LlmEditorSheet(vm: vm)
        }
        .fileImporter(
            isPresented: Binding(
                get: { coremlImportModelId != nil },
                set: { if !$0 { coremlImportModelId = nil } }
            ),
            allowedContentTypes: [.data],
            allowsMultipleSelection: false
        ) { result in
            guard let modelId = coremlImportModelId else { return }
            coremlImportModelId = nil
            if case .success(let urls) = result, let url = urls.first {
                vm.installCoreMLEncoder(modelId, from: url)
            }
        }
        .toast($vm.toast)
    }

    // MARK: - Rec tab

    private var recTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("模型下载镜像").font(.title3.bold())
            Text("用于 ASR 模型与 Core ML 编码器的「镜像下载」地址。留空则不显示镜像下载选项。")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                TextField("https://…/mirrors", text: $vm.mirrorBaseURL)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { vm.saveMirrorBaseURL() }
                Button("保存") { vm.saveMirrorBaseURL() }
                Button("清空") { vm.clearMirrorBaseURL() }
            }
            .frame(maxWidth: 560, alignment: .leading)

            Divider()

            Text("识别语言").font(.title3.bold())
            Text("默认「自动检测」会为每次识别判断语言，适合中英混说。若音频为单一语言（如纯英文），可固定对应语言以提升准确率。")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("识别语言", selection: Binding(
                get: { vm.asrLanguage },
                set: { vm.selectAsrLanguage($0) }
            )) {
                ForEach(vm.asrLanguages) { language in
                    Text(language.displayName).tag(language.id)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(maxWidth: 240, alignment: .leading)

            Divider()

            Text("ASR 模型").font(.title3.bold())
            Text("在已下载的模型中点击切换当前使用的模型。中文识别稿的标点与模型大小相关，建议使用 Small 及以上；完整排版可依赖 LLM 润色得到润色稿。")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(vm.models) { model in
                modelCard(model)
            }

            if let message = vm.message { Text(message).foregroundStyle(Color.accentColor) }
            if let error = vm.error { Text(error).foregroundStyle(.red) }
        }
    }

    private func modelCard(_ model: AsrModelInfo) -> some View {
        let downloaded = vm.downloadedIds.contains(model.id)
        let selected = vm.selectedModelId == model.id
        let isDownloading = vm.downloadingIds.contains(model.id)
        let progress = vm.downloadProgress[model.id]
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(model.displayName).font(.headline)
                        if model.id == AppSettings.defaultAsrModel {
                            Text("推荐").font(.caption2)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.2))
                                .clipShape(Capsule())
                        }
                    }
                    Text("\(model.sizeLabel) · \(downloaded ? "已下载" : "未下载")")
                        .font(.caption).foregroundStyle(.secondary)
                    if let time = vm.modelDownloadTimes[model.id] {
                        Text("下载于 \(formatDateTime(Int64(time.timeIntervalSince1970 * 1000)))")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button {
                    vm.selectModel(model.id)
                } label: {
                    Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                        .font(.system(size: 18))
                }
                .buttonStyle(.plain)
                .disabled(!downloaded)
            }

            if isDownloading {
                if let progress {
                    ProgressView(value: progress)
                } else {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("正在下载…").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            HStack(spacing: 8) {
                if downloaded {
                    Button("删除") { vm.deleteModel(model.id) }
                } else if !isDownloading {
                    Button("下载") { vm.downloadModel(model.id, useMirror: false) }
                        .buttonStyle(.borderedProminent)
                        .disabled(vm.isDownloadingAny)
                    if model.hasMirror {
                        Button("镜像下载") { vm.downloadModel(model.id, useMirror: true) }
                            .disabled(vm.isDownloadingAny)
                    }
                }
            }

            if downloaded {
                if model.quantized {
                    Text("量化模型使用 AVX2 整型内核，面向 Intel CPU 优化；Apple Silicon 上会复用同名非量化模型的 Core ML 编码器（若已安装）。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                } else {
                    coremlRow(model)
                }
            }
        }
        .padding(12)
        .background(selected ? Color.accentColor.opacity(0.12) : Color.gray.opacity(0.06))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(selected ? Color.accentColor : Color.clear, lineWidth: 2))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func coremlRow(_ model: AsrModelInfo) -> some View {
        let installed = vm.coremlInstalledIds.contains(model.id)
        let installing = vm.coremlInstallingIds.contains(model.id)
        let progress = vm.coremlDownloadProgress[model.id]
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: installed ? "checkmark.seal.fill" : "sparkles")
                    .foregroundStyle(installed ? Color.green : Color.secondary)
                Text(installed ? "Core ML 编码器已安装" : "Core ML 编码器（Apple Silicon 加速）")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if installing {
                    ProgressView().controlSize(.small)
                } else if installed {
                    Button("移除") { vm.removeCoreMLEncoder(model.id) }
                        .buttonStyle(.borderless)
                } else if model.hasCoreML {
                    Button("原版下载") { vm.downloadCoreMLEncoder(model.id, useMirror: false) }
                        .buttonStyle(.borderless)
                    if model.hasCoreMLMirror {
                        Button("镜像下载") { vm.downloadCoreMLEncoder(model.id, useMirror: true) }
                            .buttonStyle(.borderless)
                    }
                    Button("导入 .mlpackage") { coremlImportModelId = model.id }
                        .buttonStyle(.borderless)
                } else {
                    Button("导入 .mlpackage") { coremlImportModelId = model.id }
                        .buttonStyle(.borderless)
                }
            }
            if installing, let progress {
                ProgressView(value: progress)
            }
            if !installed, !installing {
                if let size = model.coremlSizeLabel {
                    Text("在 Apple Silicon 上可下载编码器（约 \(size)，支持原版 / 镜像）以启用 Neural Engine 加速；Intel Mac 会自动回退。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text("需自行生成 ggml-\(model.coremlName)-encoder.mlpackage（见 README「Core ML 加速」）后导入本机编译。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.top, 2)
    }

    // MARK: - Device tab

    private var deviceTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("录音设备").font(.title3.bold())
            Text("选择录音时使用的麦克风。「系统默认」会跟随 macOS 的“声音 → 输入”设置。")
                .font(.caption)
                .foregroundStyle(.secondary)

            deviceRow(id: "", name: "系统默认")
            ForEach(vm.inputDevices) { device in
                deviceRow(id: device.id, name: device.name)
            }

            if vm.inputDevices.isEmpty {
                Text("未检测到可用的录音设备")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if !vm.selectedInputDeviceUID.isEmpty,
                      !vm.inputDevices.contains(where: { $0.id == vm.selectedInputDeviceUID }) {
                Text("已保存的录音设备当前不可用，录音时将回退到系统默认。")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Button("刷新设备列表") { vm.refreshInputDevices() }

            if let message = vm.message { Text(message).foregroundStyle(Color.accentColor) }
            if let error = vm.error { Text(error).foregroundStyle(.red) }
        }
    }

    private func deviceRow(id: String, name: String) -> some View {
        let selected = vm.selectedInputDeviceUID == id
        return HStack(spacing: 10) {
            Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                .font(.system(size: 18))
                .foregroundStyle(selected ? Color.accentColor : Color.secondary)
            Text(name).font(.headline)
            Spacer()
        }
        .padding(12)
        .background(selected ? Color.accentColor.opacity(0.12) : Color.gray.opacity(0.06))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(selected ? Color.accentColor : Color.clear, lineWidth: 2))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
        .onTapGesture { vm.selectInputDevice(id) }
    }

    // MARK: - LLM tab

    private var llmTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("LLM 配置").font(.title3.bold())
            Text("可保存多组配置（如 OpenAI、Ollama、DeepSeek）。单选设为默认；通过弹窗添加或编辑。")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("添加配置") { vm.openAddLlmProfile() }
                .buttonStyle(.borderedProminent)

            ForEach(vm.llmProfiles) { profile in
                llmCard(profile)
            }
            if let message = vm.message { Text(message).foregroundStyle(Color.accentColor) }
            if let error = vm.error { Text(error).foregroundStyle(.red) }
        }
    }

    private func llmCard(_ profile: LlmProfile) -> some View {
        let active = vm.activeLlmProfileId == profile.id
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(profile.name).font(.headline)
                    Text(profile.model).font(.caption).foregroundStyle(.secondary)
                    Text(profile.baseURL).font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    vm.setActiveLlmProfile(profile.id)
                } label: {
                    Image(systemName: active ? "largecircle.fill.circle" : "circle")
                        .font(.system(size: 18))
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: 8) {
                Button("编辑") { vm.openEditLlmProfile(profile.id) }
                if vm.llmProfiles.count > 1 {
                    Button("删除") { vm.deleteLlmProfile(profile.id) }
                }
            }
        }
        .padding(12)
        .background(active ? Color.accentColor.opacity(0.12) : Color.gray.opacity(0.06))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(active ? Color.accentColor : Color.clear, lineWidth: 2))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct LlmEditorSheet: View {
    @ObservedObject var vm: SettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(vm.editorIsNew ? "添加配置" : "编辑配置").font(.title2.bold())
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    labeledField("配置名称", text: $vm.formName, prompt: "例如：OpenAI、本地 Ollama")
                    labeledField("Base URL", text: $vm.formBaseURL, prompt: "https://api.openai.com 或 http://192.168.1.100:11434")
                    VStack(alignment: .leading, spacing: 4) {
                        Text("API Key（本地 LLM 可留空）").font(.caption).foregroundStyle(.secondary)
                        SecureField("", text: $vm.formApiKey)
                            .textFieldStyle(.roundedBorder)
                    }
                    labeledField("Model Name", text: $vm.formModel, prompt: "gpt-4o-mini")
                    VStack(alignment: .leading, spacing: 4) {
                        Text("System Prompt").font(.caption).foregroundStyle(.secondary)
                        TextEditor(text: $vm.formSystemPrompt)
                            .frame(minHeight: 100)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.3)))
                    }
                }
            }
            HStack {
                Spacer()
                Button("取消") { vm.closeEditor() }
                Button("测试连接") { vm.testLlm() }
                Button("保存") { vm.saveLlmSettings() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 520, height: 520)
    }

    private func labeledField(_ label: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            TextField(prompt, text: text)
                .textFieldStyle(.roundedBorder)
        }
    }
}
