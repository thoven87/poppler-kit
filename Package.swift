// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "poppler-kit",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        /// C++-backed library — calls `libpoppler-cpp` in-process.
        /// Requires `libpoppler-cpp-dev` (Linux) or `poppler` (Homebrew).
        .library(name: "PopplerKit", targets: ["PopplerKit"]),

        /// Subprocess-backed library — wraps the `poppler-utils` CLI tools.
        /// Provides features outside `libpoppler-cpp`: split, merge, embedded-image
        /// extraction, SVG/PS/EPS rendering, and digital-signature inspection.
        /// Requires `poppler-utils` installed via `apt-get` or `brew`.
        .library(name: "PopplerUtils", targets: ["PopplerUtils"]),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .systemLibrary(
            name: "CPoppler",
            pkgConfig: "poppler-cpp",
            providers: [
                .apt(["libpoppler-cpp-dev"]),
                .brew(["poppler"]),
            ]
        ),
        .target(
            name: "PopplerKit",
            dependencies: ["CPoppler"],
            swiftSettings: [.interoperabilityMode(.Cxx)]
        ),
        // ── PopplerUtils ────────────────────────────────────────────────────
        .target(
            name: "PopplerUtils"
                // No CPoppler dependency — pure Swift subprocess calls.
                // No interoperabilityMode needed.
        ),
        .testTarget(
            name: "PopplerKitTests",
            dependencies: ["PopplerKit", "PopplerUtils"],
            resources: [.process("Resources")],
            swiftSettings: [.interoperabilityMode(.Cxx)]
        ),
    ],
    swiftLanguageModes: [.v6],
    cxxLanguageStandard: .cxx17
)
