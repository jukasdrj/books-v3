import SwiftUI
import SwiftData

/// Displays reading streak visualization with flame icon and statistics
@available(iOS 26.0, *)
public struct StreakVisualizationView: View {
    let streakData: StreakData

    @Environment(\.iOS26ThemeStore) private var themeStore

    public init(streakData: StreakData) {
        self.streakData = streakData
    }

    public var body: some View {
        VStack(spacing: 20) {
            // Flame icon with streak count
            flameVisualization

            // Stats grid
            statsGrid

            // Weekly calendar
            weeklyCalendar
        }
        .padding()
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        }
    }

    // MARK: - Flame Visualization

    private var flameVisualization: some View {
        VStack(spacing: 12) {
            // Flame icon
            ZStack {
                Circle()
                    .fill(
                        streakData.isOnStreak
                            ? LinearGradient(
                                colors: [.orange.opacity(0.3), .red.opacity(0.1)],
                                startPoint: .top,
                                endPoint: .bottom
                              )
                            : LinearGradient(
                                colors: [.gray.opacity(0.2), .gray.opacity(0.1)],
                                startPoint: .top,
                                endPoint: .bottom
                              )
                    )
                    .frame(width: 120, height: 120)

                Text(streakData.isOnStreak ? "🔥" : "💨")
                    .font(.system(size: 64))
            }

            // Streak count
            VStack(spacing: 4) {
                Text("\(streakData.currentStreak)")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundStyle(streakData.isOnStreak ? themeStore.primaryColor : .secondary)

                Text(streakData.currentStreak == 1 ? "day streak" : "days streak")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // Status message
            if streakData.isOnStreak {
                Text("Keep it going! 🚀")
                    .font(.caption)
                    .foregroundStyle(.green)
            } else if streakData.currentStreak == 0 {
                Text("Start a new streak today")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Stats Grid

    private var statsGrid: some View {
        Grid(horizontalSpacing: 16, verticalSpacing: 12) {
            GridRow {
                statCard(
                    value: "\(streakData.longestStreak)",
                    label: "Longest Streak",
                    icon: "trophy.fill",
                    color: .yellow
                )

                statCard(
                    value: "\(streakData.totalSessions)",
                    label: "Total Sessions",
                    icon: "book.fill",
                    color: .blue
                )
            }

            GridRow {
                statCard(
                    value: "\(streakData.sessionsThisWeek)",
                    label: "This Week",
                    icon: "calendar",
                    color: .green
                )

                statCard(
                    value: String(format: "%.0f", streakData.averagePagesPerHour),
                    label: "Pages/Hour",
                    icon: "speedometer",
                    color: .purple
                )
            }
        }
    }

    private func statCard(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)

            Text(value)
                .font(.title2.bold())
                .foregroundStyle(.primary)

            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(color.opacity(0.1))
        }
    }

    // MARK: - Weekly Calendar

    private var weeklyCalendar: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Last 7 Days")
                .font(.headline)
                .foregroundStyle(.primary)

            HStack(spacing: 8) {
                ForEach(0..<7, id: \.self) { dayOffset in
                    let date = Calendar.current.date(byAdding: .day, value: -6 + dayOffset, to: Date())!
                    let isToday = Calendar.current.isDateInToday(date)
                    let hasSession = hasSessionOn(date: date)

                    VStack(spacing: 4) {
                        Text(dayName(for: date))
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        Circle()
                            .fill(hasSession ? themeStore.primaryColor : Color.secondary.opacity(0.2))
                            .frame(width: 32, height: 32)
                            .overlay {
                                if isToday {
                                    Circle()
                                        .stroke(themeStore.primaryColor, lineWidth: 2)
                                }
                            }

                        Text(dayNumber(for: date))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Helper Methods

    private func hasSessionOn(date: Date) -> Bool {
        // Check if date is before last session date
        Calendar.current.startOfDay(for: date) <= Calendar.current.startOfDay(for: streakData.lastSessionDate)
    }

    private func dayName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: date).prefix(1).uppercased()
    }

    private func dayNumber(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter.string(from: date)
    }
}

// MARK: - Preview

#Preview {
    @Previewable @State var streakData = StreakData(
        userId: "preview-user",
        currentStreak: 5,
        longestStreak: 12,
        lastSessionDate: Date(),
        totalSessions: 48,
        totalMinutesRead: 1440,
        averagePagesPerHour: 42.5,
        sessionsThisWeek: 3,
        sessionsThisMonth: 12
    )

    StreakVisualizationView(streakData: streakData)
        .padding()
}
