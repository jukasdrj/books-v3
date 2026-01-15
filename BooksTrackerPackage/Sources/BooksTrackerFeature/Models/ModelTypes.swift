import SwiftUI
import Foundation

// MARK: - Edition Format (Updated to match UI references)

public enum EditionFormat: String, Codable, CaseIterable, Identifiable, Sendable {
    case hardcover = "Hardcover"
    case paperback = "Paperback"
    case ebook = "E-book"
    case audiobook = "Audiobook"
    case massMarket = "Mass Market"

    public var id: Self { self }

    var icon: String {
        switch self {
        case .hardcover: return "book.closed.fill"
        case .paperback: return "book.closed"
        case .ebook: return "ipad"
        case .audiobook: return "headphones"
        case .massMarket: return "book"
        }
    }

    var displayName: String {
        return rawValue
    }

    var shortName: String {
        switch self {
        case .hardcover: return "HC"
        case .paperback: return "PB"
        case .ebook: return "Digital"
        case .audiobook: return "Audio"
        case .massMarket: return "MM"
        }
    }
}

// Cultural region displayName is already available in the main enum

// MARK: - Reading Status Extensions

extension ReadingStatus {
    var shortName: String {
        switch self {
        case .wishlist: return "Want"
        case .toRead: return "To Read"
        case .reading: return "Reading"
        case .read: return "Read"
        case .onHold: return "On Hold"
        case .dnf: return "DNF"
        }
    }
}