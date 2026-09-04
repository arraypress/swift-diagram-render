// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "DiagramRender",
    platforms: [.macOS(.v14)],
    products: [.library(name: "DiagramRender", targets: ["DiagramRender"])],
    targets: [
        .target(name: "DiagramRender", resources: [.process("Resources")]),
        .testTarget(name: "DiagramRenderTests", dependencies: ["DiagramRender"]),
    ]
)
