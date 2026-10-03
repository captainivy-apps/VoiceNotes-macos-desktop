import SwiftUI
import UniformTypeIdentifiers

struct RecordScreen: View {
    let services: AppServices
    var onSaved: (Int64) -> Void

    @StateObject private var vm: RecordViewModel
    @State private var showingImporter = false
    @State private var showAsrPrompt = false

    init(services: AppServices, onSaved: @escaping (Int64) -> Void) {
        self.services = services
        self.onSaved = onSaved
        _vm = StateObject(wrappedValue: RecordViewModel(services: services))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text("语音记事")
                    .font(.largeTitle.bold())
                Text(formatDuration(vm.isRecording ? vm.elapsedMs : vm.durationMs))
                    .font(.title2.monospacedDigit())

                Text("录音设备：\(vm.inputDeviceName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                WaveformView(samples: vm.waveform)
                    .frame(height: 120)
                    .frame(maxWidth: 640)
                    .padding(.horizontal)

                content
                    .frame(maxWidth: 640)

                if let error = vm.error {
                    Text(error)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 640)
                }
                Spacer(minLength: 8)
            }
            .frame(maxWidth: .infinity)
            .padding(20)
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.audio, .mp3, .wav, .mpeg4Audio],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first { vm.importAudio(from: url) }
            case .failure(let error):
                vm.error = error.localizedDescription
            }
        }
        .alert("开始语音识别？", isPresented: $showAsrPrompt) {
            Button("立即识别") { vm.startTranscription() }
            Button("稍后", role: .cancel) { vm.dismissAsrPrompt() }
        } message: {
            Text("音频已保存。是否立即使用 ASR 模型将语音转为文字？")
        }
        .onChange(of: vm.awaitingAsrPrompt) { awaiting in
            showAsrPrompt = awaiting
        }
        .onChange(of: showAsrPrompt) { presented in
            if !presented { vm.dismissAsrPrompt() }
        }
        .toast($vm.toast)
        .onAppear { vm.refreshInputDeviceName() }
        .navigationTitle("录制")
    }

    @ViewBuilder
    private var content: some View {
        if vm.isProcessing {
            if let progress = vm.asrProgress {
                ProcessingOverlay(progress: progress, message: vm.statusMessage, elapsedMs: vm.asrElapsedMs)
            } else if let progress = vm.llmProgress {
                ProcessingOverlay(progress: progress, message: vm.statusMessage, elapsedMs: vm.llmElapsedMs)
            } else {
                IndeterminateProcessing(message: vm.statusMessage)
            }
        } else if vm.transcript == nil && vm.entryId != nil {
            VStack(spacing: 12) {
                Text("录音已保存").font(.title3)
                Text(formatDuration(vm.durationMs)).foregroundStyle(.secondary)
                Button("开始语音识别") { vm.startTranscription() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                Button("开始录制新的记事") { vm.reset() }
            }
        } else if vm.transcript == nil {
            VStack(spacing: 16) {
                Button {
                    vm.toggleRecording()
                } label: {
                    Image(systemName: vm.isRecording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 44))
                        .frame(width: 96, height: 96)
                        .background(vm.isRecording ? Color.red.opacity(0.85) : Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                Text(vm.isRecording ? "点击停止录音" : "点击开始录音")
                    .foregroundStyle(.secondary)

                Button {
                    showingImporter = true
                } label: {
                    Label("导入录音文件", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(vm.isRecording)
                Text("支持 WAV、MP3、M4A 等常见格式")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text("识别稿").font(.headline)
                DiaryTextEditor(text: Binding(
                    get: { vm.transcript ?? "" },
                    set: { vm.updateTranscript($0) }
                ), placeholder: "识别稿将显示在这里，可编辑")
                Button("直接保存为润色稿") { vm.saveDirect(onSaved: onSaved) }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                LlmProfilePicker(
                    profiles: vm.llmProfiles,
                    selectedId: vm.selectedLlmProfileId,
                    onSelected: { vm.selectLlmProfile($0) }
                )
                Button("LLM 加工后保存") { vm.saveWithLlm(onSaved: onSaved) }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
                    .disabled(vm.isProcessing)
                Button("开始录制新的记事") { vm.reset() }
                    .frame(maxWidth: .infinity)
            }
        }
    }
}
