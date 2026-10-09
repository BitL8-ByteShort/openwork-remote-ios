import SwiftUI
import UIKit
#if DEBUG && targetEnvironment(simulator)
import CryptoKit
import Synchronization

/// An explicit local receiver for native share-sheet qualification. Release
/// builds contain neither this activity nor its test destination.
// UIKit's overrides are nonisolated. Selection storage is synchronized; all
// UI completion runs on MainActor and the copy runs on a utility task.
private final class ArtifactQualificationActivity: UIActivity, @unchecked Sendable {
  private let selected = Mutex<URL?>(nil)
  let saved: @MainActor @Sendable (String) -> Void
  init(saved: @escaping @MainActor @Sendable (String) -> Void) { self.saved = saved; super.init() }
  override var activityType: UIActivity.ActivityType? { UIActivity.ActivityType("com.saltypanda.openworkremote.qualification.save") }
  override var activityTitle: String? { "Save test copy" }
  override var activityImage: UIImage? { UIImage(systemName:"folder") }
  override func canPerform(withActivityItems items: [Any]) -> Bool { items.count == 1 && (items.first as? URL)?.isFileURL == true }
  override func prepare(withActivityItems items: [Any]) {
    let url = items.first as? URL
    selected.withLock { $0 = url }
  }
  override func perform() {
    Task { @MainActor in await saveSelectedCopy() }
  }
  @MainActor private func saveSelectedCopy() async {
    guard let source = selected.withLock({ $0 }) else { activityDidFinish(false); return }
    let folder = FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0]
      .appending(path:"ArtifactShareQualification",directoryHint:.isDirectory)
      let checksum: String? = await Task.detached(priority:.utility) {
        do {
          let attributes = try FileManager.default.attributesOfItem(atPath:source.path)
          guard let size=attributes[.size] as? Int, size > 0, size <= 20*1024*1024 else { return nil }
          let data=try Data(contentsOf:source); guard data.count == size else { return nil }
          let destination=folder.appending(path:UUID().uuidString,directoryHint:.isDirectory)
          try FileManager.default.createDirectory(at:destination,withIntermediateDirectories:true,
            attributes:[.posixPermissions:0o700,.protectionKey:FileProtectionType.complete])
          let file=destination.appending(path:source.lastPathComponent)
          try data.write(to:file,options:[.atomic,.completeFileProtection])
          try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:file.path)
          guard try Data(contentsOf:file) == data else { return nil }
          let hash=SHA256.hash(data:data).map {String(format:"%02x",$0)}.joined()
          let receipt: [String:Any] = ["filename":source.lastPathComponent,"bytes":data.count,
            "sha256":hash,"activityItemCount":1,"destinationReadbackMatched":true]
          try JSONSerialization.data(withJSONObject:receipt).write(to:destination.appending(path:"receipt.json"),options:[.atomic,.completeFileProtection])
          return hash
        } catch { return nil }
      }.value
      if let checksum { saved(checksum) }; activityDidFinish(checksum != nil)
  }
}
#endif

struct ArtifactShareSheet: UIViewControllerRepresentable {
  let url: URL
  let completion: @MainActor () -> Void
  var testSaved: @MainActor (String) -> Void = {_ in}
  func makeUIViewController(context: Context) -> UIActivityViewController {
    var activities: [UIActivity] = []
    #if DEBUG && targetEnvironment(simulator)
    if ProcessInfo.processInfo.arguments.contains("-artifact-test-save") {
      activities.append(ArtifactQualificationActivity(saved:testSaved))
    }
    #endif
    let controller = UIActivityViewController(activityItems:[url],applicationActivities:activities)
    controller.completionWithItemsHandler = { _, _, _, _ in completion() }
    return controller
  }
  func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
