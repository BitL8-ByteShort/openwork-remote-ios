// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "OpenWorkRemoteCore", platforms: [.iOS(.v18), .macOS(.v15)],
  products: [.library(name: "OpenWorkRemoteCore", targets: ["OpenWorkRemoteCore"])],
  targets: [
    .target(name: "OpenWorkRemoteCore"),
    .testTarget(name: "OpenWorkRemoteCoreTests", dependencies: ["OpenWorkRemoteCore"], resources: [.copy("Fixtures")]),
  ], swiftLanguageModes: [.v6])
