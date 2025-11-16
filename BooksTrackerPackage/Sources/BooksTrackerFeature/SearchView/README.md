# SearchView Components

This directory contains the extracted state-specific views from the main SearchView, improving modularity and maintainability.

## Components

### SearchView+InitialState.swift
Contains `InitialStateView` which displays:
- Welcome section with app introduction
- Recent searches list with clear functionality
- Trending books grid
- Quick tips for first-time users

### SearchView+Results.swift
Contains `ResultsStateView` which displays:
- Results header with cache hit rate indication
- Paginated book results list
- Back-to-top button for long lists
- Edition comparison handling for duplicate detection

### SearchView+Loading.swift
Contains:
- `LoadingTrendingView` - Loading state while fetching trending books
- `SearchingView` - Active search state with previous results overlay

### SearchView+EmptyStates.swift
Contains:
- `NoResultsView` - Helpful empty state with contextual suggestions
- `ErrorStateView` - Clear error display with retry options

## Architecture Benefits

**Modularity**: Each view handles one specific state, making the code easier to understand and maintain.

**Testability**: Smaller, focused views are easier to unit test individually.

**Reusability**: State views can potentially be reused in other contexts.

**Performance**: Better SwiftUI diffing and rendering with smaller view hierarchies.

## Usage Pattern

The components follow a consistent pattern of accepting:
- Data parameters (e.g., `items`, `trending`, `query`)
- `@Bindable` reference to `SearchModel` for state interaction
- Callback closures for user actions (e.g., `onBookSelected`)

Example:
```swift
case .initial(let trending, let recentSearches):
    InitialStateView(
        trending: trending,
        recentSearches: recentSearches,
        searchModel: searchModel,
        onBookSelected: { book in
            selectedBook = book
        }
    )
```

## Swift 6 Compatibility

All components use `@Bindable` instead of `@ObservedObject` to support the new `@Observable` macro introduced in Swift 6.

## Context

Extracted as part of issue #458 to reduce the main SearchView from 1000+ lines to ~350 lines, improving maintainability and reducing cognitive load.
