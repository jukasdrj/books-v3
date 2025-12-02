// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "BooksTrackerFeature",
    platforms: [.iOS(.v26), .macOS(.v14)],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "BooksTrackerFeature",
            targets: ["BooksTrackerFeature"]
        ),
    ],
    dependencies: [
        // OpenAPI Generator temporarily disabled due to Xcode beta plugin validation bug
        // TODO: Re-enable when Xcode stable is released or plugin issue is resolved
        // Using manual V3 API client implementation instead
        //
        // .package(url: "https://github.com/apple/swift-openapi-generator", from: "1.0.0"),
        // .package(url: "https://github.com/apple/swift-openapi-runtime", from: "1.0.0"),
        // .package(url: "https://github.com/apple/swift-openapi-urlsession", from: "1.0.0"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "BooksTrackerFeature",
            dependencies: [
                // OpenAPI dependencies temporarily disabled (see dependencies block above)
                // .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
                // .product(name: "OpenAPIURLSession", package: "swift-openapi-urlsession"),
            ]
            // OpenAPI plugin temporarily disabled (see dependencies block above)
            // plugins: [
            //     .plugin(name: "OpenAPIGenerator", package: "swift-openapi-generator")
            // ]
        ),
        .testTarget(
            name: "BooksTrackerFeatureTests",
            dependencies: [
                "BooksTrackerFeature"
            ]
        ),
    ]
)
