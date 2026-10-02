import SwiftUI

private enum DetailTab: String, CaseIterable, Identifiable {
    case audio = "录音"
    case transcript = "识别稿"
    case polished = "润色稿"
    var id: String { rawValue }
}

private enum ConfirmAction: Identifiable {
    case deleteAudio
    case deleteTranscript
    case deleteDiaryText
    case deleteEntry

    var id: Int { hashValue }

    var message: String {
        switch self {
        case .deleteAudio: return "确定删除录音吗？此操作不可恢复。"
        case .deleteTranscript: return "确定删除识别稿吗？此操作不可恢复。"
        case .deleteDiaryText: return "确定删除润色稿吗？此操作不可恢复。"
        case .deleteEntry: return "确定删除整篇记事及所有内容吗？此操作不可恢复。"
        }
    }
}

struct DiaryDetailScreen: View {
    let services: AppServices
    let entryId: Int64
    var onNavigate: (Int64) -> Void
    var onDeleted: () -> Void
    var onChanged: () -> Void

    @StateObject private var vm: DiaryDetailViewModel
    @StateObject private var player = AudioPlayer()
    @State private var selectedTab: DetailTab = .audio
    @State private var waveformPeaks: [Float] = []
    @State private var audioDurationMs: Int64 = 0
    @State private var confirmAction: ConfirmAction?

    init(
        services: AppServices,
        entryId: Int64,
        onNavigate: @escaping (Int64) -> Void,
        onDeleted: @escaping () -> Void,
        onChanged: @escaping () -> Void
    ) {
        self.services = services
        self.entryId = entryId
        self.onNavigate = onNavigate
        self.onDeleted = onDeleted
        self.onChanged = onChanged
        _vm = StateObject(wrappedValue: DiaryDetailViewModel(services: services, entryId: entryId))
    }

    var body: some View {
        Group {
            if vm.loading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                content
            }
        }
        .task {
            vm.refreshLlmProfiles()
            await vm.load()
        }
        .onChange(of: vm.audioPath) { newPath in
            loadWaveform(path: newPath)
        }
        .onChange(of: selectedTab) { _ in
            player.stop()
        }
        .onChange(of: vm.navigateBack) { back in
            if back { onDeleted() }
        }
        .onChange(of: vm.prevId) { _ in }
        .toast($vm.toast)
    }

    private var content: some View {
        VStack(spacing: 0) {
            header
            Divider()
            Picker("", selection: $selectedTab) {
                ForEach(DetailTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 16)
            .padding(.top, 10)

            if let error = vm.error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
            }

            Group {
                switch selectedTab {
                case .audio: audioTab
                case .transcript: transcriptTab
                case .polished: polishedTab
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            footer
        }
        .alert(item: $confirmAction) { action in
            Alert(
                title: Text("确认删除"),
                message: Text(action.message),
                primaryButton: .destructive(Text("删除")) {
                    performDelete(action)
                },
                secondaryButton: .cancel(Text("取消"))
            )
        }
    }

    private var header: some View {
        HStack {
            Text("记事详情").font(.title3.bold())
            Spacer()
            Button {
                confirmAction = .deleteEntry
            } label: {
                Image(systemName: "trash")
            }
            .help("删除整篇记事")
        }
        .padding(12)
    }

    // MARK: - Audio tab

    private var audioTab: some View {
        VStack(spacing: 12) {
            Text("录音大小：\(formatFileSize(audioFileSize(vm.audioPath))) · \(WavFile.formatLabel)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 8)

            if vm.isProcessing, let progress = vm.asrProgress {
                ProcessingOverlay(progress: progress, message: vm.statusMessage, elapsedMs: vm.asrElapsedMs)
                    .padding(.horizontal, 16)
                Spacer()
            } else if vm.audioPath != nil {
                let positionMs = Int64(player.currentTime * 1000)
                let windowStart = WaveformMath.windowStartMs(durationMs: audioDurationMs, playbackPositionMs: positionMs)
                let visible = WaveformMath.windowSlice(allBars: waveformPeaks, durationMs: audioDurationMs, windowStartMs: windowStart)
                let playhead = player.isPlaying
                    ? WaveformMath.playheadFraction(durationMs: audioDurationMs, windowStartMs: windowStart, playbackPositionMs: positionMs)
                    : nil

                VStack(spacing: 12) {
                    Text(player.isPlaying
                         ? "\(formatDuration(positionMs)) / \(formatDuration(audioDurationMs))"
                         : formatDuration(audioDurationMs))
                        .font(.title3.monospacedDigit())
                        .foregroundStyle(player.isPlaying ? Color.accentColor : Color.secondary)

                    WaveformView(samples: visible, playheadFraction: playhead)
                        .frame(height: 120)
                        .padding(.horizontal, 16)

                    Button {
                        togglePlayback()
                    } label: {
                        Image(systemName: player.isPlaying ? "stop.fill" : "play.fill")
                            .font(.system(size: 30))
                            .frame(width: 68, height: 68)
                            .background(Color.accentColor)
                            .foregroundStyle(.white)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    Text(player.isPlaying ? "点击停止播放" : "点击播放录音")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            } else {
                Spacer()
                Text("暂无录音").foregroundStyle(.secondary)
                Spacer()
            }

            actionBar {
                Button {
                    togglePlayback()
                } label: { Image(systemName: player.isPlaying ? "stop" : "play") }
                    .help(player.isPlaying ? "停止" : "试听")
                    .disabled(vm.audioPath == nil)
                Button { confirmAction = .deleteAudio } label: { Image(systemName: "trash") }
                    .help("删除录音")
                    .disabled(vm.audioPath == nil)
                Button { vm.exportAudio() } label: { Image(systemName: "arrow.down.circle") }
                    .help("下载录音")
                    .disabled(vm.audioPath == nil)
                Button { player.stop(); vm.runAsr() } label: { Image(systemName: "waveform") }
                    .help("重新 ASR 识别")
                    .disabled(vm.audioPath == nil || vm.isProcessing)
            }
        }
    }

    // MARK: - Transcript tab

    private var transcriptTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("识别稿大小：\(formatFileSize(textByteSize(vm.transcript)))")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 8)

            if vm.isProcessing {
                if let progress = vm.asrProgress {
                    ProcessingOverlay(progress: progress, message: vm.statusMessage, elapsedMs: vm.asrElapsedMs)
                        .padding(.horizontal, 16)
                } else if let progress = vm.llmProgress {
                    ProcessingOverlay(progress: progress, message: vm.statusMessage, elapsedMs: vm.llmElapsedMs)
                        .padding(.horizontal, 16)
                }
            }

            DiaryTextEditor(text: Binding(
                get: { vm.transcript },
                set: { vm.updateTranscript($0) }
            ), placeholder: "识别稿将显示在这里，可编辑")
            .padding(.horizontal, 16)

            LlmProfilePicker(
                profiles: vm.llmProfiles,
                selectedId: vm.selectedLlmProfileId,
                onSelected: { vm.selectLlmProfile($0) }
            )
            .padding(.horizontal, 16)

            Spacer(minLength: 0)

            actionBar {
                Button { confirmAction = .deleteTranscript } label: { Image(systemName: "trash") }
                    .help("删除识别稿")
                    .disabled(vm.transcript.isEmpty)
                Button { vm.exportTranscript() } label: { Image(systemName: "arrow.down.circle") }
                    .help("下载识别稿")
                    .disabled(vm.transcript.isEmpty)
                Button { copyToClipboard(vm.transcript); vm.toast = "识别稿已复制" } label: { Image(systemName: "doc.on.doc") }
                    .help("复制识别稿")
                    .disabled(vm.transcript.isEmpty)
                Button { vm.copyTranscriptToDiary(); onChanged() } label: { Image(systemName: "arrow.right") }
                    .help("直接当作润色稿")
                    .disabled(vm.transcript.isEmpty)
                Button { vm.runLlm() } label: { Image(systemName: "wand.and.stars") }
                    .help("LLM 加工识别稿")
                    .disabled(vm.transcript.isEmpty || vm.isProcessing)
            }
        }
    }

    // MARK: - Polished tab

    private var polishedTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("润色稿大小：\(formatFileSize(textByteSize(vm.diaryText)))")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 8)

            DiaryTextEditor(text: Binding(
                get: { vm.diaryText },
                set: { vm.updateDiaryText($0) }
            ), placeholder: "润色稿将显示在这里，可编辑")
            .padding(.horizontal, 16)

            Spacer(minLength: 0)

            actionBar {
                Button { confirmAction = .deleteDiaryText } label: { Image(systemName: "trash") }
                    .help("删除润色稿")
                    .disabled(vm.diaryText.isEmpty)
                Button { vm.exportDiaryText() } label: { Image(systemName: "arrow.down.circle") }
                    .help("下载润色稿")
                    .disabled(vm.diaryText.isEmpty)
                Button { copyToClipboard(vm.diaryText); vm.toast = "润色稿已复制" } label: { Image(systemName: "doc.on.doc") }
                    .help("复制润色稿")
                    .disabled(vm.diaryText.isEmpty)
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 4) {
            Text(formatDateTime(vm.createdAt))
                .font(.caption)
                .foregroundStyle(.secondary)
            if vm.updatedAt > vm.createdAt {
                Text("更新于 \(formatDateTime(vm.updatedAt))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text("整篇记事大小：\(formatFileSize(diaryTotalSize(audioPath: vm.audioPath, transcript: vm.transcript, diaryText: vm.diaryText)))")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Button {
                    if let prev = vm.prevId { player.stop(); onNavigate(prev) }
                } label: {
                    Label("上一篇", systemImage: "chevron.left")
                }
                .disabled(vm.prevId == nil)
                Spacer()
                Button {
                    if let next = vm.nextId { player.stop(); onNavigate(next) }
                } label: {
                    Label("下一篇", systemImage: "chevron.right")
                }
                .disabled(vm.nextId == nil)
            }
            .padding(.top, 4)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
    }

    private func actionBar<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 28) {
            Spacer()
            content()
            Spacer()
        }
        .padding(.vertical, 10)
        .buttonStyle(.borderless)
        .font(.system(size: 18))
    }

    // MARK: - Actions

    private func togglePlayback() {
        if player.isPlaying {
            player.stop()
            vm.toast = "已停止播放"
            return
        }
        guard let path = vm.audioPath else {
            vm.toast = "录音已删除"
            return
        }
        do {
            try player.play(url: URL(fileURLWithPath: path))
            vm.toast = "正在播放录音"
        } catch {
            vm.toast = "播放失败：\(error.localizedDescription)"
        }
    }

    private func loadWaveform(path: String?) {
        player.stop()
        waveformPeaks = []
        audioDurationMs = 0
        guard let path else { return }
        let url = URL(fileURLWithPath: path)
        Task {
            let result = await Task.detached(priority: .utility) { () -> (peaks: [Float], durationMs: Int64)? in
                try? WavFile.readWaveformPeaks(url: url, windowMs: WaveformMath.windowMs, barsPerWindow: WaveformMath.barsPerWindow)
            }.value
            if let result {
                waveformPeaks = result.peaks
                audioDurationMs = result.durationMs
            }
        }
    }

    private func performDelete(_ action: ConfirmAction) {
        switch action {
        case .deleteAudio:
            player.stop()
            vm.deleteAudio()
        case .deleteTranscript:
            vm.deleteTranscript()
        case .deleteDiaryText:
            vm.deleteDiaryText()
        case .deleteEntry:
            player.stop()
            vm.deleteEntry()
        }
        confirmAction = nil
    }
}
