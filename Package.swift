// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "OpenWorkRemoteCore", platforms: [.iOS(.v18), .macOS(.v15)],
  products: [.library(name: "OpenWorkRemoteCore", targets: ["OpenWorkRemoteCore"])],
  targets: [
    .target(name: "OpenWorkRemoteCore"),
    .testTarget(name: "OpenWorkRemoteCoreTests", dependencies: ["OpenWorkRemoteCore"], resources: [.copy("Fixtures")]),
    .target(name: "OpenWorkRemoteAppState", dependencies: ["OpenWorkRemoteCore"],
      path: "OpenWorkRemote",
      exclude: ["App/OpenWorkRemoteApp.swift", "Assets.xcassets", "Design", "Features",
                "Info.plist", "PrivacyInfo.xcprivacy", "Rendering"],
      sources: ["App/AppModel.swift", "State", "Storage"]),
    .testTarget(name: "OpenWorkRemoteAppTests", dependencies: ["OpenWorkRemoteAppState", "OpenWorkRemoteCore"]),
  ], swiftLanguageModes: [.v6])
