# iOS 26 HIG Compliance - Quick Reference

**Essential iOS 26 Human Interface Guidelines patterns for BooksTrack**

---

## 🚨 Critical Rules

### Rule #1: Don't Mix @FocusState with .searchable()

```swift
// ❌ WRONG: Manual focus creates keyboard conflicts
@FocusState var searchFocused: Bool
var body: some View {
    SearchView()
        .searchable(text: $query)
        .focused($searchFocused)  // ❌ Conflict!
}

// ✅ CORRECT: Let .searchable() manage focus
var body: some View {
    SearchView()
        .searchable(text: $query)  // ✅ iOS handles focus
}
```

**Why:** iOS 26's `.searchable()` manages keyboard focus internally. Manual `@FocusState` creates conflicts.

---

### Rule #2: Push Navigation for Drill-Down

```swift
// ✅ CORRECT: Push navigation for details
.navigationDestination(item: $selectedBook) { book in
    WorkDetailView(work: book.work)
}

// ❌ WRONG: Sheets break navigation stack
.sheet(item: $selectedBook) { book in
    WorkDetailView(work: book.work)
}

// ✅ CORRECT: Sheets for modals only
.sheet(isPresented: $showingSettings) {
    NavigationStack { SettingsView() }
}
```

**Why:** Sheets are for modals (Settings, filters, etc.), not drill-down navigation (iOS 26 HIG).

---

### Rule #3: 3-5 Tabs Optimal

```swift
// ✅ CORRECT: 4 tabs (optimal per iOS 26 HIG)
TabView {
    LibraryView().tabItem { Label("Library", systemImage: "books.vertical") }
    SearchView().tabItem { Label("Search", systemImage: "magnifyingglass") }
    ShelfView().tabItem { Label("Shelf", systemImage: "camera") }
    InsightsView().tabItem { Label("Insights", systemImage: "chart.bar") }
}

// ❌ WRONG: 6+ tabs (creates "More" tab clutter)
TabView {
    // Too many tabs...
}
```

**Why:** iOS 26 HIG recommends 3-5 tabs. More than 5 creates "More" tab (poor UX).

---

## 🎨 Navigation Patterns

### Tab Bar Navigation

**Placement:**
- Bottom on iPhone
- Sidebar on iPad (automatic)

**Icon Guidelines:**
- Use SF Symbols (consistent, scalable)
- Label text: 1-2 words max
- Avoid custom icons (poor accessibility)

```swift
TabView {
    LibraryView()
        .tabItem {
            Label("Library", systemImage: "books.vertical")
        }
}
```

---

### Navigation Stack

**Use for:**
- Drill-down navigation (list → detail)
- Multi-level hierarchies

```swift
NavigationStack {
    List(works) { work in
        NavigationLink(value: work) {
            BookCard(work: work)
        }
    }
    .navigationDestination(for: Work.self) { work in
        WorkDetailView(work: work)
    }
}
```

---

### Sheets (Modals)

**Use for:**
- Settings/preferences
- Filters/sort options
- Non-navigation contexts (photo picker, share sheet)

```swift
.sheet(isPresented: $showingSettings) {
    NavigationStack {
        SettingsView()
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showingSettings = false }
                }
            }
    }
}
```

---

## 🎨 Typography

### Dynamic Type Support

**Always use system fonts with Dynamic Type:**
```swift
// ✅ CORRECT: Dynamic Type
Text("Book Title")
    .font(.title)  // Scales with user's font size preference

// ❌ WRONG: Fixed font size
Text("Book Title")
    .font(.system(size: 24))  // Doesn't scale!
```

---

### Text Styles

| Style | Use Case |
|-------|----------|
| `.largeTitle` | Screen titles (rare) |
| `.title` | Main content title |
| `.title2` | Section headers |
| `.title3` | Sub-section headers |
| `.headline` | Emphasized text, list row titles |
| `.body` | Primary content |
| `.callout` | Secondary content |
| `.subheadline` | Metadata, labels |
| `.footnote` | Supplementary info |
| `.caption` | Timestamps, counts |
| `.caption2` | Very small text (rare) |

---

## 🎨 Color & Contrast

### Semantic Colors (Auto-Adapt to Dark Mode)

```swift
// ✅ CORRECT: System semantic colors
Text("Author").foregroundColor(.secondary)
Text("Publisher").foregroundColor(.tertiary)
Text(work.title).foregroundColor(.primary)

// ❌ WRONG: Custom colors (don't adapt)
Text("Author").foregroundColor(.gray)  // ❌ Same in light/dark!
```

---

### WCAG AA Compliance

**Required:** 4.5:1 contrast ratio (text < 18pt), 3:1 (text ≥ 18pt)

```swift
// ✅ CORRECT: System colors ensure WCAG AA
Text("Metadata").foregroundColor(.secondary)

// ⚠️ VERIFY: Custom brand colors
Text("Featured").foregroundColor(themeStore.primaryColor)
// Must test with Accessibility Inspector (Xcode)
```

**Tool:** Xcode → Accessibility Inspector → Color Contrast Calculator

---

## ♿ Accessibility

### VoiceOver Labels

**All interactive elements need labels:**
```swift
// ✅ CORRECT: Descriptive label
Button("Add to Library", systemImage: "plus") {
    addToLibrary()
}
.accessibilityLabel("Add \(work.title) to library")

// ❌ WRONG: Icon-only button without label
Button(action: addToLibrary) {
    Image(systemName: "plus")
}
// VoiceOver: "Button" (unhelpful!)
```

---

### Accessibility Hints

```swift
Button("Scan Bookshelf") {
    startScanning()
}
.accessibilityHint("Opens camera to scan book spines")
```

---

### Accessibility Traits

```swift
// Custom view that acts like a button
BookCard(work: work)
    .onTapGesture { selectWork(work) }
    .accessibilityAddTraits(.isButton)
    .accessibilityLabel("Open \(work.title)")
```

---

## 🔊 Haptic Feedback

### Impact Feedback (Physical Interaction)

```swift
// Success (e.g., book added to library)
let generator = UIImpactFeedbackGenerator(style: .medium)
generator.impactOccurred()

// Error (e.g., scan failed)
let generator = UINotificationFeedbackGenerator()
generator.notificationOccurred(.error)

// Selection (e.g., changing tabs)
let generator = UISelectionFeedbackGenerator()
generator.selectionChanged()
```

**Styles:**
- `.light` - Subtle (checkboxes, switches)
- `.medium` - Standard (buttons, list selections)
- `.heavy` - Strong (drag & drop, major actions)

---

## 🎨 Material Design 3 (iOS 26)

### Liquid Glass Effects

**Background Materials:**
```swift
// Translucent background (Liquid Glass)
.background(.ultraThinMaterial)

// Stronger blur
.background(.thinMaterial)

// Strongest blur
.background(.regularMaterial)
```

**Levels:**
- `.ultraThinMaterial` - Subtle translucency
- `.thinMaterial` - More visible blur
- `.regularMaterial` - Strong blur
- `.thickMaterial` - Very strong blur
- `.ultraThickMaterial` - Opaque-like blur

---

### Rounded Corners (iOS 26 Standard)

```swift
// Standard corner radius
.cornerRadius(12)

// Large corners (cards, sheets)
.cornerRadius(16)

// Small corners (chips, badges)
.cornerRadius(8)
```

---

## 📱 Layout

### Safe Areas

**Always respect safe areas:**
```swift
// ✅ CORRECT: Content avoids notch/home indicator
ScrollView {
    content
}
.safeAreaInset(edge: .bottom) {
    // Fixed toolbar (above home indicator)
}

// ❌ WRONG: Content behind notch
.ignoresSafeArea()  // Use sparingly!
```

---

### Spacing

**iOS 26 Standard Spacing:**
- 4pt - Tiny gap (icon-text)
- 8pt - Small gap (list row padding)
- 12pt - Standard gap (between sections)
- 16pt - Large gap (section spacing)
- 20pt - Extra large (screen edges)

```swift
VStack(spacing: 12) {  // Standard gap
    Text("Title")
    Text("Subtitle")
}
.padding(.horizontal, 20)  // Screen edges
```

---

## 🔍 Search

### Searchable Modifier

```swift
NavigationStack {
    List(filteredWorks) { work in
        Text(work.title)
    }
    .navigationTitle("Library")
    .searchable(text: $query, prompt: "Search books")
}
```

**Don't:**
- ❌ Mix with `@FocusState` (keyboard conflict)
- ❌ Manually show/hide keyboard
- ❌ Custom search bar (use `.searchable()`)

---

### Search Scopes

```swift
@State private var searchScope: SearchScope = .all

NavigationStack {
    List(filteredWorks) { work in
        Text(work.title)
    }
    .searchable(text: $query, prompt: "Search books")
    .searchScopes($searchScope) {
        Text("All").tag(SearchScope.all)
        Text("Title").tag(SearchScope.title)
        Text("Author").tag(SearchScope.author)
        Text("ISBN").tag(SearchScope.isbn)
    }
}
```

---

## 🖼️ Images

### Async Image Loading

```swift
// ✅ CORRECT: CachedAsyncImage (custom, with cache)
CachedAsyncImage(url: coverURL) { image in
    image.resizable().aspectRatio(contentMode: .fit)
} placeholder: {
    ProgressView()
}

// ❌ WRONG: AsyncImage (no cache, slow)
AsyncImage(url: coverURL)
```

---

### SF Symbols

```swift
// Standard usage
Image(systemName: "books.vertical")
    .font(.title)
    .foregroundColor(.blue)

// Multicolor symbols
Image(systemName: "person.circle.fill")
    .symbolRenderingMode(.multicolor)

// Variable value (e.g., volume, brightness)
Image(systemName: "speaker.wave.3.fill")
    .symbolVariant(.slash)  // Crossed out
```

---

## 🎯 Lists

### Standard List Style

```swift
List(works) { work in
    BookCard(work: work)
}
.listStyle(.insetGrouped)  // iOS 26 default
```

**Styles:**
- `.insetGrouped` - iOS 26 default (rounded corners, spacing)
- `.plain` - No grouping (edge-to-edge)
- `.sidebar` - iPad sidebar (collapsible)

---

### Swipe Actions

```swift
List(works) { work in
    BookCard(work: work)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                deleteWork(work)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading) {
            Button {
                toggleFavorite(work)
            } label: {
                Label("Favorite", systemImage: "star")
            }
            .tint(.yellow)
        }
}
```

---

## 📋 Forms

### Form Layout

```swift
Form {
    Section("Personal Info") {
        TextField("Name", text: $name)
        DatePicker("Date", selection: $date, displayedComponents: .date)
    }

    Section("Preferences") {
        Toggle("Enable Notifications", isOn: $notificationsEnabled)
        Picker("Theme", selection: $theme) {
            Text("Liquid Blue").tag(Theme.liquidBlue)
            Text("Cosmic Purple").tag(Theme.cosmicPurple)
        }
    }
}
.navigationTitle("Settings")
.navigationBarTitleDisplayMode(.inline)
```

---

## 🔄 Progress Indicators

### Determinate Progress

```swift
// Circular progress
ProgressView(value: progress, total: 1.0)
    .progressViewStyle(.circular)

// Linear progress
ProgressView(value: progress, total: 1.0)
    .progressViewStyle(.linear)
```

---

### Indeterminate Progress

```swift
// Loading spinner
ProgressView()
    .progressViewStyle(.circular)

// With label
ProgressView("Loading...")
```

---

## 🎨 Theming

### Custom Themes (BooksTrack Pattern)

```swift
@Environment(iOS26ThemeStore.self) private var themeStore

var body: some View {
    Text("Featured")
        .foregroundColor(themeStore.primaryColor)  // Brand color
    Text("Author")
        .foregroundColor(.secondary)  // System semantic
}
```

**Rule:**
- Use `themeStore.primaryColor` for brand/highlights
- Use `.secondary`/`.tertiary` for metadata (auto-adapts)

---

## 📱 iPad Considerations

### Split View

```swift
NavigationSplitView {
    // Sidebar
    List(works, selection: $selectedWork) { work in
        Text(work.title)
    }
} detail: {
    // Detail pane
    if let work = selectedWork {
        WorkDetailView(work: work)
    } else {
        Text("Select a book")
    }
}
```

---

## 🐛 Common HIG Violations

### Issue: Keyboard doesn't appear in search
**Cause:** Mixing `@FocusState` with `.searchable()`
**Fix:** Remove `@FocusState`

---

### Issue: Back button doesn't work
**Cause:** Using sheets for drill-down
**Fix:** Use push navigation (`.navigationDestination`)

---

### Issue: Text too small on large text settings
**Cause:** Fixed font size (`.system(size: 18)`)
**Fix:** Use Dynamic Type (`.font(.body)`)

---

### Issue: Poor contrast in dark mode
**Cause:** Custom colors don't adapt
**Fix:** Use system semantic colors (`.secondary`, `.tertiary`)

---

### Issue: VoiceOver says "Button" (unhelpful)
**Cause:** Missing accessibility label
**Fix:** Add `.accessibilityLabel("Descriptive text")`

---

**Keep this reference handy! iOS 26 HIG compliance ensures great UX across all devices.**
