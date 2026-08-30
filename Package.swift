// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "AgentFiles",
  platforms: [
    .macOS(.v26)
  ],
  products: [
    .executable(name: "AgentFiles", targets: ["AgentFiles"])
  ],
  targets: [
    .executableTarget(
      name: "AgentFiles",
      path: "Sources/AgentFiles"
    ),
    .testTarget(
      name: "AgentFilesTests",
      dependencies: ["AgentFiles"],
      path: "Tests/AgentFilesTests"
    ),
  ]
)
