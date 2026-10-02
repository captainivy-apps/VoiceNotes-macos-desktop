import Foundation

@MainActor
final class DiaryListViewModel: ObservableObject {
    @Published var entries: [DiaryEntry] = []
    @Published var selection: Set<Int64> = []

    private let services: AppServices

    init(services: AppServices) {
        self.services = services
    }

    func load() async {
        entries = (try? await services.store.allOrdered()) ?? []
        selection = selection.intersection(entries.map(\.id))
    }

    func deleteEntries(_ ids: [Int64]) async {
        guard !ids.isEmpty else { return }
        try? await services.store.deleteEntries(ids: ids)
        selection.removeAll()
        await load()
    }
}
