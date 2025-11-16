import SwiftUI

#if canImport(UIKit)

/// Reusable confidence badge component for displaying AI confidence scores
public struct ConfidenceBadge: View {
    let confidence: Double
    let style: ConfidenceStyle
    
    public enum ConfidenceStyle {
        case compact  // Just percentage
        case detailed // With icon and label
        case minimal // Color indicator only
    }
    
    public init(confidence: Double, style: ConfidenceStyle = .detailed) {
        self.confidence = confidence
        self.style = style
    }
    
    private var confidenceLevel: ConfidenceLevel {
        switch confidence {
        case ConfidenceThresholds.high...1.0: return .high
        case ConfidenceThresholds.medium..<ConfidenceThresholds.high: return .medium
        default: return .low
        }
    }
    
    public var body: some View {
        switch style {
        case .compact:
            compactView
        case .detailed:
            detailedView
        case .minimal:
            minimalView
        }
    }
    
    private var compactView: some View {
        Text("\(Int(confidence * 100))%")
            .font(.caption.weight(.semibold))
            .foregroundColor(confidenceLevel.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background {
                Capsule()
                    .fill(confidenceLevel.color.opacity(0.2))
            }
    }
    
    private var detailedView: some View {
        HStack(spacing: 4) {
            confidenceLevel.icon
                .font(.caption)
            Text("\(Int(confidence * 100))%")
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background {
            Capsule()
                .fill(confidenceLevel.color.opacity(0.2))
        }
        .foregroundColor(confidenceLevel.color)
    }
    
    private var minimalView: some View {
        Circle()
            .fill(confidenceLevel.color)
            .frame(width: 8, height: 8)
    }
}

// MARK: - Confidence Level

private enum ConfidenceLevel {
    case high      // 80-100%
    case medium    // 60-79%
    case low       // <60%
    
    var color: Color {
        switch self {
        case .high: return .green
        case .medium: return .orange
        case .low: return .red
        }
    }
    
    var icon: Image {
        switch self {
        case .high: return Image(systemName: "checkmark.circle.fill")
        case .medium: return Image(systemName: "exclamationmark.circle.fill")
        case .low: return Image(systemName: "questionmark.circle.fill")
        }
    }
    
    var accessibilityLabel: String {
        switch self {
        case .high: return "High confidence"
        case .medium: return "Medium confidence"
        case .low: return "Low confidence"
        }
    }
}

// MARK: - Confidence Explanation Sheet

public struct ConfidenceExplanationSheet: View {
    let confidence: Double
    @Environment(\.dismiss) private var dismiss
    
    public init(confidence: Double) {
        self.confidence = confidence
    }
    
    private var confidenceLevel: ConfidenceLevel {
        switch confidence {
        case 0.8...1.0: return .high
        case 0.6..<0.8: return .medium
        default: return .low
        }
    }
    
    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            confidenceLevel.icon
                                .font(.largeTitle)
                                .foregroundColor(confidenceLevel.color)
                            
                            Text("Confidence Score: \(Int(confidence * 100))%")
                                .font(.title2.bold())
                        }
                        
                        Text(confidenceDescription)
                            .foregroundColor(.secondary)
                    }
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Text("What This Means")
                            .font(.headline)
                        
                        if confidence >= ConfidenceThresholds.high {
                            confidenceRow(
                                icon: "checkmark.circle.fill",
                                color: .green,
                                text: "High confidence - Book automatically added to library"
                            )
                        } else if confidence >= ConfidenceThresholds.medium {
                            confidenceRow(
                                icon: "exclamationmark.circle.fill",
                                color: .orange,
                                text: "Medium confidence - Added with review recommended"
                            )
                        } else {
                            confidenceRow(
                                icon: "questionmark.circle.fill",
                                color: .red,
                                text: "Low confidence - Sent to review queue for verification"
                            )
                        }
                    }
                    
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("How We Calculate Confidence")
                            .font(.headline)
                        
                        Text("Our AI analyzes book spine images using Google Gemini 2.0 Flash. Confidence is based on:")
                        
                        VStack(alignment: .leading, spacing: 6) {
                            confidenceRow(icon: "text.magnifyingglass", color: .secondary, text: "Text clarity in the image")
                            confidenceRow(icon: "books.vertical", color: .secondary, text: "Match quality with book databases")
                            confidenceRow(icon: "checkmark.seal", color: .secondary, text: "Consistency across multiple detections")
                        }
                        .font(.callout)
                        .foregroundColor(.secondary)
                    }
                }
                .padding()
            }
            .navigationTitle("About Confidence Scores")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
    
    private func confidenceRow(icon: String, color: Color, text: String) -> some View {
        Label(text, systemImage: icon)
            .foregroundColor(color)
    }
    
    private var confidenceDescription: String {
        switch confidence {
        case 0.8...1.0:
            "This is a high-confidence detection. The AI is very certain about the title and author."
        case 0.6..<0.8:
            "This is a medium-confidence detection. The book was added, but you may want to verify details."
        default:
            "This is a low-confidence detection. Please review and correct the title or author if needed."
        }
    }
}

// MARK: - Preview

@available(iOS 26.0, *)
#Preview {
    VStack(spacing: 20) {
        ConfidenceBadge(confidence: 0.95, style: .detailed)
        ConfidenceBadge(confidence: 0.72, style: .detailed)
        ConfidenceBadge(confidence: 0.54, style: .detailed)
        
        ConfidenceBadge(confidence: 0.95, style: .compact)
        ConfidenceBadge(confidence: 0.72, style: .compact)
        ConfidenceBadge(confidence: 0.54, style: .compact)
    }
    .padding()
}

#endif