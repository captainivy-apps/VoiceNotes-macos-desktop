import SwiftUI

struct NotesScreen: View {
    let services: AppServices
    @Binding var selectedId: Int64?

    @StateObject private var vm: DiaryListViewModel
    @State private var selectionMode = false
    @State private var showDeleteConfirm = false

    init(services: AppServices, selectedId: Binding<Int64?>) {
        self.services = services
        _selectedId = selectedId
        _vm = StateObject(wrappedValue: DiaryListViewModel(services: services))
    }

    var body: some View {
        HSplitView {
            listColumn
                .frame(minWidth: 260, idealWidth: 300, maxWidth: 380)
            detailColumn
                .frame(minWidth: 460)
        }
        .task { await vm.load() }
        .navigationTitle("记事")
    }

    private var listColumn: some View {
        VStack(spacing: 0) {
            HStack {
                Text("记事列表").font(.title3.bold())
                Spacer()
                if selectionMode {
                    Button("删除(\(vm.selection.count))") {
                        if !vm.selection.isEmpty { showDeleteConfirm = true }
                    }
                    .disabled(vm.selection.isEmpty)
                    Button("取消") {
                        selectionMode = false
                        vm.selection.removeAll()
                    }
                } else {
                    Button {
                        selectionMode = true
                    } label: {
                        Image(systemName: "checklist")
                    }
                    .help("多选删除")
                }
            }
            .padding(12)
            Divider()

            if vm.entries.isEmpty {
                Spacer()
                Text("还没有记事，去录制页说点什么吧")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(vm.entries) { entry in
                            row(entry)
                            Divider()
                        }
                    }
                }
            }
        }
        .alert("确认删除", isPresented: $showDeleteConfirm) {
            Button("删除", role: .destructive) {
                let ids = Array(vm.selection)
                if let selectedId, ids.contains(selectedId) { self.selectedId = nil }
                selectionMode = false
                Task { await vm.deleteEntries(ids) }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将永久删除选中的 \(vm.selection.count) 篇记事，此操作不可恢复。")
        }
    }

    private func row(_ entry: DiaryEntry) -> some View {
        HStack(spacing: 10) {
            if selectionMode {
                Image(systemName: vm.selection.contains(entry.id) ? "checkmark.square.fill" : "square")
                    .foregroundStyle(vm.selection.contains(entry.id) ? Color.accentColor : Color.secondary)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(diaryPreview(entry))
                    .font(.headline)
                    .lineLimit(1)
                Text(formatDateTime(entry.createdAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(formatFileSize(diaryTotalSize(entry)))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .background(selectedId == entry.id && !selectionMode ? Color.accentColor.opacity(0.15) : Color.clear)
        .onTapGesture {
            if selectionMode {
                if vm.selection.contains(entry.id) {
                    vm.selection.remove(entry.id)
                } else {
                    vm.selection.insert(entry.id)
                }
            } else {
                selectedId = entry.id
            }
        }
    }

    @ViewBuilder
    private var detailColumn: some View {
        if let id = selectedId, vm.entries.contains(where: { $0.id == id }) {
            DiaryDetailScreen(
                services: services,
                entryId: id,
                onNavigate: { newId in selectedId = newId },
                onDeleted: {
                    selectedId = nil
                    Task { await vm.load() }
                },
                onChanged: {
                    Task { await vm.load() }
                }
            )
            .id(id)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "book")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
                Text("选择左侧记事查看详情")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
