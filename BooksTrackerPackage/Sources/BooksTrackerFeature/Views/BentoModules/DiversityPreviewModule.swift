import SwiftUI
import SwiftData

/// Diversity Preview Module - Representation Radar mini-preview
/// Bottom-left module in Bento Grid (wide layout)
@available(iOS 26.0, *)
public struct DiversityPreviewModule: View {
    @Bindable var work: Work
    
    @Environment(\.iOS26ThemeStore) private var themeStore
    @State private var showFullRadar = false
    
    public init(work: Work) {
        self.work = work
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Diversity percentage (overall completion)
            HStack(spacing: 8) {
                Image(systemName: "chart.pie")
                    .foregroundStyle(themeStore.primaryColor)
                    .font(.title3)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(Int(diversityPercentage))% Diverse")
                        .font(.headline.bold())
                        .foregroundStyle(.primary)
                    
                    Text(diversityLabel)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                // View full chart button
                Button(action: {
                    showFullRadar = true
                }) {
                    Image(systemName: "arrow.up.forward.circle")
                        .foregroundStyle(themeStore.primaryColor)
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }
            
            // Cultural origin preview (if available)
            if let culturalRegion = work.culturalRegion {
                HStack(spacing: 6) {
                    Image(systemName: "globe.americas")
                        .font(.caption)
                        .foregroundStyle(themeStore.culturalColors.color(for: culturalRegion))
                    
                    Text("Origin: \(culturalRegion.displayName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background {
                    Capsule()
                        .fill(themeStore.culturalColors.color(for: culturalRegion).opacity(0.15))
                }
            }
            
            // Mini radar preview (simplified visualization)
            HStack(spacing: 6) {
                ForEach(radarDimensions, id: \.name) { dimension in
                    VStack(spacing: 4) {
                        Circle()
                            .fill(dimension.isComplete ? themeStore.primaryColor : Color.secondary.opacity(0.3))
                            .frame(width: 8, height: 8)
                        
                        Text(dimension.name.prefix(3))
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            
            // Call to action if data is incomplete
            if diversityPercentage < 100 {
                Button(action: {
                    showFullRadar = true
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle.fill")
                            .font(.caption)
                        Text("Complete the Graph")
                            .font(.caption.bold())
                    }
                    .foregroundStyle(themeStore.primaryColor)
                }
                .buttonStyle(.plain)
            }
        }
        .sheet(isPresented: $showFullRadar) {
            DiversityDetailView(work: work)
                .iOS26SheetGlass()
        }
    }
    
    // MARK: - Computed Properties
    
    private var radarDimensions: [RadarDimension] {
        return [
            RadarDimension(
                name: "Cultural",
                completionPercentage: work.culturalRegion != nil ? 100 : 0,
                isComplete: work.culturalRegion != nil
            ),
            RadarDimension(
                name: "Gender",
                completionPercentage: work.authorGender != nil && work.authorGender != .unknown ? 100 : 0,
                isComplete: work.authorGender != nil && work.authorGender != .unknown
            ),
            RadarDimension(
                name: "Translation",
                completionPercentage: work.originalLanguage != nil ? 100 : 0,
                isComplete: work.originalLanguage != nil
            ),
            RadarDimension(
                name: "Own Voices",
                completionPercentage: 0, // TODO: Add own voices flag to model
                isComplete: false
            ),
            RadarDimension(
                name: "Access",
                completionPercentage: 0, // TODO: Add accessibility tags
                isComplete: false
            )
        ]
    }
    
    private var diversityPercentage: Double {
        let complete = radarDimensions.filter(\.isComplete).count
        return Double(complete) / Double(radarDimensions.count) * 100
    }
    
    private var diversityLabel: String {
        let percentage = Int(diversityPercentage)
        switch percentage {
        case 90...100:
            return "Highly Diverse"
        case 70..<90:
            return "Diverse"
        case 50..<70:
            return "Moderate"
        case 30..<50:
            return "Limited"
        default:
            return "Needs Data"
        }
    }
}

/// Full diversity detail view with radar chart
@available(iOS 26.0, *)
private struct DiversityDetailView: View {
    @Bindable var work: Work
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.iOS26ThemeStore) private var themeStore
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Full radar chart
                    RepresentationRadarChart(
                        data: RadarChartData(dimensions: radarDimensions),
                        onAddData: { dimension in
                            // TODO: Show progressive profiling prompt for this dimension
                            #if DEBUG
                            print("Add data for: \(dimension)")
                            #endif
                        }
                    )
                    .padding()
                    
                    // Overall score
                    VStack(spacing: 8) {
                        Text("\(Int(diversityPercentage))% Complete")
                            .font(.title2.bold())
                            .foregroundStyle(themeStore.primaryColor)
                        
                        Text(diversityLabel)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    
                    // Dimension details
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(radarDimensions, id: \.name) { dimension in
                            HStack {
                                Circle()
                                    .fill(dimension.isComplete ? Color.green : Color.secondary)
                                    .frame(width: 8, height: 8)
                                
                                Text(dimension.name)
                                    .font(.subheadline)
                                
                                Spacer()
                                
                                Text("\(Int(dimension.completionPercentage))%")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding()
                    .background {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.ultraThinMaterial)
                    }
                    .padding(.horizontal)
                }
                .padding()
            }
            .navigationTitle("Diversity Representation")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private var radarDimensions: [RadarDimension] {
        return [
            RadarDimension(
                name: "Cultural",
                completionPercentage: work.culturalRegion != nil ? 100 : 0,
                isComplete: work.culturalRegion != nil
            ),
            RadarDimension(
                name: "Gender",
                completionPercentage: work.authorGender != nil && work.authorGender != .unknown ? 100 : 0,
                isComplete: work.authorGender != nil && work.authorGender != .unknown
            ),
            RadarDimension(
                name: "Translation",
                completionPercentage: work.originalLanguage != nil ? 100 : 0,
                isComplete: work.originalLanguage != nil
            ),
            RadarDimension(
                name: "Own Voices",
                completionPercentage: 0,
                isComplete: false
            ),
            RadarDimension(
                name: "Accessible",
                completionPercentage: 0,
                isComplete: false
            )
        ]
    }
    
    private var diversityPercentage: Double {
        let complete = radarDimensions.filter(\.isComplete).count
        return Double(complete) / Double(radarDimensions.count) * 100
    }
    
    private var diversityLabel: String {
        let percentage = Int(diversityPercentage)
        switch percentage {
        case 90...100:
            return "Highly Diverse"
        case 70..<90:
            return "Diverse"
        case 50..<70:
            return "Moderate"
        case 30..<50:
            return "Limited"
        default:
            return "Needs Data"
        }
    }
}

// MARK: - Preview

@available(iOS 26.0, *)
#Preview("Diversity Preview") {
    @Previewable @State var container: ModelContainer = {
        let container = try! ModelContainer(for: Work.self, Edition.self, UserLibraryEntry.self, Author.self)
        let context = container.mainContext
        
        let author = Author(name: "Chimamanda Ngozi Adichie")
        let work = Work(title: "Half of a Yellow Sun")
        
        context.insert(author)
        context.insert(work)
        
        author.culturalRegion = .africa
        author.gender = .female
        work.authors = [author]
        work.originalLanguage = "English"
        
        return container
    }()
    
    let work = try! container.mainContext.fetch(FetchDescriptor<Work>()).first!
    let themeStore = BooksTrackerFeature.iOS26ThemeStore()
    
    BentoModule(title: "Diversity & Representation", icon: "globe") {
        DiversityPreviewModule(work: work)
    }
    .modelContainer(container)
    .environment(\.iOS26ThemeStore, themeStore)
    .padding()
    .themedBackground()
}
