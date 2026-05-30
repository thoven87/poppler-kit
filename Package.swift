// swift-tools-version: 6.2
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
        .library(name: "PopplerUtils", targets: ["PopplerUtils"]),

        /// Layout analysis on top of PopplerKit.
        .library(name: "PopplerLayout", targets: ["PopplerLayout"]),
    ],
    targets: [
        // ── CPoppler ─────────────────────────────────────────────────────────
        // pkg-config shim for libpoppler-cpp (header search path + -lpoppler-cpp).
        .systemLibrary(
            name: "CPoppler",
            pkgConfig: "poppler-cpp",
            providers: [
                .apt(["libpoppler-cpp-dev"]),
                .brew(["pkg-config", "poppler"]),
            ]
        ),

        // ── CPopplerBridge ───────────────────────────────────────────────────
        // Pure-C ABI layer compiled as C++20.
        // C++20 is required because the lower-level poppler headers (PDFDoc.h,
        // GfxState.h, OutputDev.h) use std::starts_with, std::span, and
        // `requires`-clauses introduced in C++20.
        //
        // Links -lpoppler (the lower-level library) in addition to -lpoppler-cpp
        // so that PDFDoc, OutputDev, and GfxState symbols resolve at link time.
        // The -L search path is already provided by CPoppler's pkg-config flags.
        .target(
            name: "CPopplerBridge",
            dependencies: ["CPoppler"],
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedLibrary("poppler")
            ]
        ),

        // ── PopplerKit ───────────────────────────────────────────────────────
        .target(
            name: "PopplerKit",
            dependencies: ["CPopplerBridge"]
        ),

        // ── PopplerLayout ────────────────────────────────────────────────────
        .target(
            name: "PopplerLayout",
            dependencies: ["PopplerKit"]
        ),

        // ── PopplerUtils ─────────────────────────────────────────────────────
        .target(
            name: "PopplerUtils"
        ),

        .testTarget(
            name: "PopplerKitTests",
            dependencies: ["PopplerKit", "PopplerUtils", "PopplerLayout"],
            resources: [.process("Resources")]
        ),
    ],
    swiftLanguageModes: [.v6],
    // C++20 is required by poppler's lower-level headers (PDFDoc.h, GfxState.h, etc.)
    cxxLanguageStandard: .cxx20
)
