import SwiftUI

struct LlmProfilePicker: View {
    var profiles: [LlmProfile]
    var selectedId: String
    var onSelected: (String) -> Void

    var body: some View {
        if !profiles.isEmpty {
            Picker("LLM 配置", selection: Binding(
                get: { profiles.contains(where: { $0.id == selectedId }) ? selectedId : (profiles.first?.id ?? "") },
                set: { onSelected($0) }
            )) {
                ForEach(profiles) { profile in
                    Text(profile.summary).tag(profile.id)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: 320, alignment: .leading)
        }
    }
}
