import SwiftUI

struct LibraryStatusBadge: View {
    let status: ReadingStatus

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: status.systemImage)
                .font(.caption)
                .foregroundColor(.white)
            Text(status.shortName)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.white)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(status.color)
        .cornerRadius(8)
    }
}
