# Gemini API Token Usage - iOS Integration Guide

**Date:** November 6, 2025  
**API Version:** Gemini 2.0 Flash Experimental  
**Related:** `docs/architecture/gemini-api-best-practices-audit.md`

## Pricing Constants (November 2025)

```swift
// Gemini 2.0 Flash Pricing (as of Nov 2025)
enum GeminiPricing {
    static let inputTokenCostPer1M: Double = 0.075   // $0.075 per 1M tokens
    static let outputTokenCostPer1M: Double = 0.30   // $0.30 per 1M tokens
    
    // Typical token distribution for bookshelf scans
    static let inputTokenRatio: Double = 0.85  // ~85% input tokens
    static let outputTokenRatio: Double = 0.15 // ~15% output tokens
    
    // Alert thresholds
    static let highTokenUsageThreshold: Int = 10000  // Warn users above this
}
```

**⚠️ Update these values when Gemini pricing changes.**

## Overview

Backend now includes **token usage tracking** in all Gemini API responses. This enables cost monitoring, usage analytics, and budget alerts on iOS.

## What Changed

### Backend Response Schema

All Gemini-powered endpoints now include `tokenUsage` in metadata:

```json
{
  "books": [...],
  "metadata": {
    "provider": "gemini",
    "model": "gemini-2.0-flash-exp",
    "timestamp": "2025-11-06T03:45:00Z",
    "processingTimeMs": 28500,
    "tokenUsage": {
      "promptTokens": 4200,
      "outputTokens": 500,
      "totalTokens": 4700
    }
  }
}
```

### Affected Endpoints

1. **Bookshelf Scanner** (`POST /api/scan-bookshelf`)
   - WebSocket progress messages include `tokenUsage` in final result
   - Location: `metadata.tokenUsage` in completion payload

2. **CSV Import** (`POST /api/import/csv-gemini`)
   - Token usage tracked for parsing phase
   - Available in import completion response

## iOS Implementation Guide

### 1. Update Response Models

Add `tokenUsage` to existing metadata structs:

```swift
// BooksTrackerPackage/Sources/BooksTrackerFeature/BookshelfScanning/Models/

public struct ScanMetadata: Codable, Sendable {
    public let provider: String
    public let model: String
    public let timestamp: String
    public let processingTime: Int
    public let tokenUsage: TokenUsage?  // NEW: Optional for backward compatibility
    
    enum CodingKeys: String, CodingKey {
        case provider
        case model
        case timestamp
        case processingTime = "processingTimeMs"
        case tokenUsage
    }
}

public struct TokenUsage: Codable, Sendable {
    public let promptTokens: Int
    public let outputTokens: Int
    public let totalTokens: Int
    
    enum CodingKeys: String, CodingKey {
        case promptTokens
        case outputTokens
        case totalTokens
    }
}
```

### 2. Display Token Usage (Optional)

**Settings Screen Enhancement:**

```swift
// Settings → Advanced → API Usage

struct APIUsageView: View {
    @State private var recentScans: [ScanRecord] = []
    
    var body: some View {
        List {
            Section("Recent Bookshelf Scans") {
                ForEach(recentScans) { scan in
                    VStack(alignment: .leading) {
                        Text("\(scan.booksCount) books")
                            .font(.headline)
                        if let usage = scan.tokenUsage {
                            Text("\(usage.totalTokens) tokens")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text(scan.timestamp, style: .relative)
                            .font(.caption)
                    }
                }
            }
            
            Section("Estimated Monthly Cost") {
                Text("$\(estimatedMonthlyCost, specifier: "%.2f")")
                    .font(.title2)
            }
        }
        .navigationTitle("API Usage")
    }
    
    var estimatedMonthlyCost: Double {
        let totalTokens = recentScans.reduce(0) { $0 + ($1.tokenUsage?.totalTokens ?? 0) }
        let avgPerScan = Double(totalTokens) / Double(max(recentScans.count, 1))
        let estimatedMonthlyScans = 30.0 // Assume 1 scan/day
        
        // Use pricing constants
        let inputCost = avgPerScan * GeminiPricing.inputTokenRatio * GeminiPricing.inputTokenCostPer1M / 1_000_000
        let outputCost = avgPerScan * GeminiPricing.outputTokenRatio * GeminiPricing.outputTokenCostPer1M / 1_000_000
        
        return (inputCost + outputCost) * estimatedMonthlyScans
    }
}
```

### 3. Analytics Tracking (Optional)

**Track token usage for analytics:**

```swift
// Analytics service integration
func logScanCompletion(result: BookshelfScanResult) {
    if let tokenUsage = result.metadata?.tokenUsage {
        Analytics.track("bookshelf_scan_complete", properties: [
            "books_detected": result.books.count,
            "total_tokens": tokenUsage.totalTokens,
            "prompt_tokens": tokenUsage.promptTokens,
            "output_tokens": tokenUsage.outputTokens,
            "processing_time_ms": result.metadata?.processingTime ?? 0
        ])
    }
}
```

### 4. Budget Alerts (Optional)

**Warn users of high token usage:**

```swift
// After scan completes
if let tokenUsage = result.metadata?.tokenUsage {
    if tokenUsage.totalTokens > GeminiPricing.highTokenUsageThreshold {
        // High token usage alert
        showAlert(
            title: "Large Scan Processed",
            message: "This scan used \(tokenUsage.totalTokens) tokens. Consider using smaller images or fewer books per photo for lower costs."
        )
    }
}
```

## Expected Token Usage

### Bookshelf Scans

**Typical scan (3072px × 3072px image):**
- **Prompt tokens:** ~150 (system instruction + user prompt)
- **Image tokens:** ~580 (Gemini's tiling algorithm)
- **Output tokens:** ~500 (10 books × 50 tokens/book)
- **Total:** ~1,230 tokens per scan

**Cost per scan:** ~$0.00012 (Nov 2025 pricing)

### CSV Import

**Typical import (100 books):**
- **Prompt tokens:** ~200 (system instruction + few-shot examples)
- **Input tokens:** ~2,000 (CSV content)
- **Output tokens:** ~5,000 (100 books × 50 tokens/book)
- **Total:** ~7,200 tokens per import

**Cost per import:** ~$0.00165 (Nov 2025 pricing)

## Token Calculation Formula

Gemini 2.0 Flash uses a tiling algorithm for images:

```swift
// For images > 384px in any dimension
let cropUnit = floor(min(width, height) / 1.5)
let tiles = (width / cropUnit) * (height / cropUnit)
let imageTokens = tiles * 258

// Example: 3072 × 3072 image
// cropUnit = floor(3072 / 1.5) = 2048
// tiles = (3072 / 2048) * (3072 / 2048) = 1.5 * 1.5 = 2.25
// imageTokens = 2.25 * 258 ≈ 580 tokens
```

**Small images (≤384px both dimensions):** 258 tokens flat rate

## Backward Compatibility

**Token usage is optional** - existing iOS code works without changes:

```swift
// Safe to use even if backend doesn't include tokenUsage
if let tokenUsage = result.metadata?.tokenUsage {
    print("Scan used \(tokenUsage.totalTokens) tokens")
} else {
    print("Token usage not available (older backend)")
}
```

## Testing

**Unit tests for token usage decoding:**

```swift
@Test("Token usage decodes from bookshelf scan result")
func testTokenUsageDecoding() throws {
    let json = """
    {
      "books": [],
      "metadata": {
        "provider": "gemini",
        "model": "gemini-2.0-flash-exp",
        "timestamp": "2025-11-06T03:45:00Z",
        "processingTimeMs": 28500,
        "tokenUsage": {
          "promptTokens": 4200,
          "outputTokens": 500,
          "totalTokens": 4700
        }
      }
    }
    """
    
    let decoder = JSONDecoder()
    let result = try decoder.decode(BookshelfScanResult.self, from: json.data(using: .utf8)!)
    
    #expect(result.metadata?.tokenUsage != nil)
    #expect(result.metadata?.tokenUsage?.totalTokens == 4700)
}
```

## Logging & Debugging

**Backend logs token usage automatically:**

```
[GeminiProvider] Token usage - Prompt: 4200, Output: 500, Total: 4700
```

**Check CloudWatch logs:**
1. Open CloudWatch console
2. Search for `[GeminiProvider] Token usage`
3. Analyze patterns over time

## Cost Optimization Tips

**If token usage is higher than expected:**

1. **Reduce image size:** 3072px → 2048px saves ~50% image tokens (but reduces accuracy)
2. **Use fewer books per photo:** 5-8 books optimal, 15+ increases output tokens
3. **Compress aggressively:** Current 90% quality is good balance
4. **Batch scans:** Multiple photos processed sequentially reuses system instruction

**Current implementation is already optimized:**
- System instructions separated (not repeated per request)
- Stop sequences prevent unnecessary output
- Temperature tuned for deterministic output (fewer retries)

## Related Documentation

- **Backend Audit:** `docs/architecture/gemini-api-best-practices-audit.md`
- **Bookshelf Scanner:** `docs/features/BOOKSHELF_SCANNER.md`
- **CSV Import:** `docs/features/GEMINI_CSV_IMPORT.md`
- **Gemini Pricing:** https://ai.google.dev/pricing

## Questions?

**Token usage seems high?**
- Check image dimensions (3072px is max, smaller images use fewer tokens)
- Verify book count (more books = more output tokens)
- Review logs for actual vs. estimated token counts

**Token usage not appearing?**
- Ensure backend is updated (deployed after Nov 6, 2025)
- Check response JSON in network logs
- Verify `tokenUsage` is optional in Swift models

---

**Last Updated:** November 6, 2025  
**Backend Version:** 3.0.1+  
**iOS Compatibility:** All versions (backward compatible)
