import Foundation

public enum SnapshotStoreError: Error { case invalidated, invalidRemovalTarget }

/// Older queued autosaves cannot replace a newer, durably saved mutation intent.
public actor RevisionedSnapshotStore<State: Codable & Sendable> {
  private let url: URL
  private var savedRevision: UInt64 = 0
  private var invalidated = false
  public init(url: URL) { self.url = url }
  public func load() throws -> State? {
    guard !invalidated else { throw SnapshotStoreError.invalidated }
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    return try JSONDecoder().decode(State.self, from: Data(contentsOf: url))
  }
  public func save(_ state: State, revision: UInt64) throws {
    guard !invalidated else { throw SnapshotStoreError.invalidated }
    guard revision > savedRevision else { return }
    var directory = url.deletingLastPathComponent(), values = URLResourceValues()
    values.isExcludedFromBackup = true
    try directory.setResourceValues(values)
    try JSONEncoder().encode(state).write(to: url, options: [.atomic, .completeFileProtection])
    savedRevision = revision
  }
  /// Retire this writer before removal, including when removal fails. A fresh
  /// app state owns a new store; old queued tasks can never recreate its data.
  public func invalidateAndRemove() throws {
    invalidated = true
    guard FileManager.default.fileExists(atPath: url.path) else { return }
    let type = try FileManager.default.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType
    guard type == .typeRegular || type == .typeSymbolicLink else { throw SnapshotStoreError.invalidRemovalTarget }
    try FileManager.default.removeItem(at: url)
  }
}
