import SwiftUI

struct ReadingHabitsModule: View {
    @State private var viewModel: ReadingHabitsViewModel

    init(work: Work) {
        _viewModel = State(initialValue: ReadingHabitsViewModel(work: work))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ModuleHeader(title: "Habits", icon: "flame.fill")

            HStack(spacing: 16) {
                // Reading Pace
                VStack(alignment: .leading) {
                    Text("Pace")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if let pace = viewModel.averagePace {
                        Text("\(Int(pace)) pgs/hr")
                            .font(.title2.bold())
                            .foregroundColor(.primary)
                    } else {
                        Text("-")
                            .font(.title2.bold())
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                // Reading Streak
                VStack(alignment: .leading) {
                    Text("Streak")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(viewModel.readingStreak) Days")
                        .font(.title2.bold())
                        .foregroundColor(.primary)
                }
            }
            .padding(.top, 8)

            Spacer()
        }
        .padding()
        .background(GlassEffect(tint: .purple.opacity(0.1)))
        .cornerRadius(20)
    }
}

// A generic header for bento box modules
struct ModuleHeader: View {
    let title: String
    let icon: String

    var body: some View {
        HStack {
            Text(title)
                .font(.headline.bold())
            Spacer()
            Image(systemName: icon)
                .foregroundColor(.secondary)
        }
    }
}
