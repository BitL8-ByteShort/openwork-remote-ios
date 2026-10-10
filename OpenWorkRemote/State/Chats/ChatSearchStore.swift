import Foundation
import Observation
import OpenWorkRemoteCore

struct ChatSearchContext: Equatable, Sendable {
  let hostId: String, workspaceId: String
  let generation: UUID
}
@MainActor @Observable final class ChatSearchStore {
  private(set) var context: ChatSearchContext?
  private(set) var query = ""
  private(set) var results: [ChatSession] = []
  private(set) var cursor: String?
  private(set) var scanned = 0
  private(set) var complete = false
  private(set) var loading = false
  private(set) var availability: FeatureAvailability = .unsupported
  private(set) var notice: String?
  @ObservationIgnored private var task: Task<Void, Never>?
  @ObservationIgnored private var runID = UUID()
  func activate(_ c: ChatSearchContext?) {
    guard context != c else { return }
    task?.cancel()
    task = nil
    runID = UUID()
    context = c
    query = ""
    results = []
    cursor = nil
    scanned = 0
    complete = false
    loading = false
    availability = .unsupported
    notice = nil
  }
  func schedule(
    _ text: String, client: BridgeClient, context c: ChatSearchContext, supported: Bool,
    debounce: Bool = true
  ) {
    guard context == c else { return }
    task?.cancel()
    runID = UUID()
    query = text.trimmingCharacters(in: .whitespacesAndNewlines)
    results = []
    cursor = nil
    scanned = 0
    complete = false
    notice = nil
    loading = false
    availability = supported ? .available : .unsupported
    guard supported, !query.isEmpty else { return }
    guard text.unicodeScalars.count <= 200, text.utf8.count <= 800,
      !text.unicodeScalars.contains(where: {
        $0.properties.generalCategory == .control || $0.properties.generalCategory == .format
      })
    else {
      notice = "Use a title search of up to 200 characters."
      return
    }
    let id = runID
    let q = query
    loading = true
    task = Task {
      do {
        if debounce { try await Task.sleep(for: .milliseconds(300)) }
        try Task.checkCancellation()
      } catch { return }
      await self.load(client: client, context: c, query: q, cursor: nil, id: id)
    }
  }
  func more(client: BridgeClient, context c: ChatSearchContext) async {
    guard context == c, !loading, availability == .available, let next = cursor else { return }
    let id = runID
    let q = query
    loading = true
    notice = nil
    let pending = Task {
      await self.load(client: client, context: c, query: q, cursor: next, id: id)
    }
    task = pending
    await withTaskCancellationHandler {
      await pending.value
    } onCancel: {
      pending.cancel()
    }
  }
  private func load(
    client: BridgeClient, context c: ChatSearchContext, query q: String, cursor next: String?,
    id: UUID
  ) async {
    defer {
      if context == c, runID == id {
        loading = false
        task = nil
      }
    }
    do {
      let access = try await client.deviceAccess()
      guard access.allWorkspaces || access.workspaceIds.contains(c.workspaceId) else {
        throw RemoteError.forbidden
      }
      try Task.checkCancellation()
      let page = try await client.searchSessions(c.workspaceId, query: q, cursor: next)
      guard context == c, runID == id, !Task.isCancelled else { return }
      for row in page.data {
        if let n = results.firstIndex(where: { $0.id == row.id }) {
          results[n] = row
        } else {
          results.append(row)
        }
      }
      scanned += page.scanned
      complete = page.complete
      cursor = page.cursor
      notice = nil
      if results.count >= 2000, !complete {
        cursor = nil
        notice = "Many chats match. Narrow your search to check more titles."
      }
    } catch {
      guard context == c, runID == id, !Task.isCancelled else { return }
      if case RemoteError.forbidden = error {
        results = []
        cursor = nil
        availability = .unsupported
        notice = "This project is no longer allowed. Change project access on your computer."
      } else if case RemoteError.unauthorized = error {
        results = []
        cursor = nil
        notice = "Reconnect to search this computer."
      } else {
        notice = "Search could not finish. Try the search again; current matches are kept."
      }
    }
  }
}
