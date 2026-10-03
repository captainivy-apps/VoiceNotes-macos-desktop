import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case notes = "记事"
    case record = "录制"
    case settings = "设置"

    var id: Self { self }

    var systemImage: String {
        switch self {
        case .notes: return "book"
        case .record: return "mic"
        case .settings: return "gearshape"
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var services: AppServices
    @State private var selection: SidebarItem? = .record
    @State private var selectedNoteId: Int64?

    var body: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, selection: $selection) { item in
                Label(item.rawValue, systemImage: item.systemImage)
                    .tag(item)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(180)
        } detail: {
            switch selection ?? .record {
            case .notes:
                NotesScreen(services: services, selectedId: $selectedNoteId)
            case .record:
                RecordScreen(services: services) { id in
                    selectedNoteId = id
                    selection = .notes
                }
            case .settings:
                SettingsScreen(services: services)
            }
        }
    }
}
