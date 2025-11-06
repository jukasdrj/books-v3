# BooksTracker Project Overview

This document provides a comprehensive overview of the BooksTracker iOS project, designed to be used as a context for AI-powered development assistants.

## Project Summary

BooksTracker is a modern iOS application for tracking personal book libraries. It's built with Swift 6.1+, SwiftUI, and the "iOS 26 Liquid Glass" design system. The app features a robust set of functionalities including a powerful CSV import wizard, cultural diversity insights, barcode scanning, and data synchronization via SwiftData and CloudKit.

The project follows a modern, modular architecture, with the core business logic encapsulated in a Swift Package Manager (SPM) module. This separation of concerns makes the codebase clean, scalable, and easy to maintain.

The backend is powered by Cloudflare Workers, providing a scalable and efficient serverless infrastructure for features like book data enrichment and advanced search.

## Building and Running

The project includes a set of scripts to automate common development tasks.

### One-Time Setup

To get started, run the following script to install the necessary git hooks for automated versioning:

```bash
./Scripts/setup_hooks.sh
```

### Running the App

1.  Open the `BooksTracker.xcworkspace` file in Xcode.
2.  Select the "BooksTracker" scheme.
3.  Choose a simulator or a connected device.
4.  Click the "Run" button.

### Running Tests

The project has both unit and UI tests.

*   **Unit Tests:** Located in `BooksTrackerPackage/Tests/BooksTrackerFeatureTests/`.
*   **UI Tests:** Located in `BooksTrackerUITests/`.

To run all tests, you can use the "Test" action in Xcode (Product > Test or Command-U).

### Versioning and Releases

The `Scripts` directory contains scripts for managing application versions and creating releases.

*   **Update Version:**

    ```bash
    # Update the patch version (e.g., 1.0.0 -> 1.0.1)
    ./Scripts/update_version.sh patch

    # Update the minor version (e.g., 1.0.0 -> 1.1.0)
    ./Scripts/update_version.sh minor

    # Update the major version (e.g., 1.0.0 -> 2.0.0)
    ./Scripts/update_version.sh major
    ```

*   **Create a Release:**

    The `release.sh` script automates the entire release process, including running tests, updating the version, committing the changes, and creating a git tag.

    ```bash
    # Create a minor release with a message
    ./Scripts/release.sh minor "Added new reading statistics"
    ```

## Development Conventions

### Architecture

*   **Workspace + SPM:** The project uses an Xcode workspace that contains the main application project and a separate SPM package (`BooksTrackerPackage`) for the core feature development.
*   **App Shell:** The `BooksTracker` project is a thin shell responsible for the app's lifecycle and entry point.
*   **Feature Module:** All the business logic, UI, and data models reside in the `BooksTrackerFeature` target within the `BooksTrackerPackage`.

### Code Style

*   **Swift 6+ Concurrency:** The project embraces modern Swift concurrency features like `async/await` and actors.
*   **SwiftUI State Management:** The project uses pure SwiftUI state management patterns, avoiding the use of ViewModels.
*   **Performance:** The code emphasizes performance, using `@Observable` over `@Published` and other optimization techniques.
*   **Swift 6.2 Adoption:** The project actively adopts new features from Swift 6.2 to improve code quality and maintainability. This includes:
    *   **Modern `NotificationCenter` API:** Using `async/await` for handling notifications, resulting in cleaner and more readable code.
    *   **`@concurrent` Attribute:** Applying the `@concurrent` attribute to functions that are safe to run concurrently, allowing the compiler to verify their safety.
    *   **Swift Testing Enhancements:** Leveraging new features in Swift Testing, such as parameterized tests, to write more concise and effective tests.

### AI-Assisted Development

The project is designed to be used with AI coding assistants. The `README.md`, `CLAUDE.md`, and `.github/copilot-instructions.md` files provide detailed instructions and rules for AI agents. It is crucial to review these files before making any changes to the codebase.
