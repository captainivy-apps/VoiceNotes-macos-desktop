import SwiftUI

struct ProcessingOverlay: View {
    var progress: Float
    var message: String
    var elapsedMs: Int64

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ProgressView(value: Double(min(max(progress, 0), 1)))
            Text(message)
                .font(.callout)
            Text(formatDuration(elapsedMs))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color.gray.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct IndeterminateProcessing: View {
    var message: String

    var body: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text(message).font(.callout)
        }
        .padding(12)
        .background(Color.gray.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
