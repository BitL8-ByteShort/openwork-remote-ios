import Foundation

/// Older queued autosaves cannot replace a newer, durably saved mutation intent.
public actor RevisionedSnapshotStore<State: Codable & Sendable> {
  private let url: URL
  private var savedRevision: UInt64 = 0
  public init(url: URL) { self.url = url }
  public func load() throws -> State? {
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    return try JSONDecoder().decode(State.self, from: Data(contentsOf: url))
  }
  public func save(_ state: State, revision: UInt64) throws {
    guard revision > savedRevision else { return }
    try JSONEncoder().encode(state).write(to: url, options: [.atomic, .completeFileProtection])
    savedRevision = revision
  }
}
