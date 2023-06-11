// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription
import CompilerPluginSupport

let package = Package(
    name: "MacroTest",
    platforms: [
        .macOS(.v10_15)
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .executable(
            name: "MacroTest",
            targets: ["MacroTest"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-syntax.git", revision: "swift-DEVELOPMENT-SNAPSHOT-2023-06-07-a"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .macro(
            name: "MacroTestImpl",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax")
            ]
        ),
        .executableTarget(
            name: "MacroTest",
            dependencies: ["MacroTestImpl"]
        ),
    ]
)
