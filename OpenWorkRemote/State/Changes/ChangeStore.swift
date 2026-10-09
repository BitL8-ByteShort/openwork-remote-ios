import Foundation
import Observation
import OpenWorkRemoteCore

struct ChangeContext: Equatable, Sendable {
  let key: DraftKey
  let generation: UUID
  let selection: UUID
}
@MainActor @Observable final class ChangeStore {
  private(set) var context: ChangeContext?
  private(set) var availability: FeatureAvailability = .unsupported
  private(set) var catalog: ChangeSet?
  private(set) var loading = false
  private(set) var opening: ChangeRef?
  private(set) var diff: FileDiff?
  private(set) var lines: [DiffLine] = []
  private(set) var notice: String?
  private(set) var needsRefresh = false
  @ObservationIgnored private var readID = UUID()
  @ObservationIgnored private var openID = UUID()
  @ObservationIgnored private var readTask: Task<ChangeSet?,any Error>?
  @ObservationIgnored private var openTask: Task<FileDiff?,any Error>?
  func activate(_ value: ChangeContext?) {
    guard context != value else { return }
    closeDiff();readID=UUID();readTask?.cancel();readTask=nil
    context=value;availability = .unsupported;catalog=nil;loading=false;notice=nil;needsRefresh=false
  }
  func closeDiff() { openID=UUID();openTask?.cancel();openTask=nil;diff=nil;lines=[];opening=nil }
  func close() { readID=UUID();readTask?.cancel();readTask=nil;loading=false;closeDiff();catalog=nil;notice=nil;needsRefresh=false }
  func refresh(client: BridgeClient, context: ChangeContext, supported: Bool) async {
    guard self.context == context else { return }
    readTask?.cancel();let run=UUID();readID=run;closeDiff()
    guard supported else { availability = .unsupported;catalog=nil;loading=false;notice=nil;return }
    loading=true
    let key=context.key,task=Task<ChangeSet?,any Error> {
      guard try await client.deviceAccess().features.fileTransfer else { return nil }
      return try await client.changes(key.workspaceId,key.sessionId)
    }
    readTask=task
    defer { if readID == run {loading=false;readTask=nil} }
    do {
      let value=try await withTaskCancellationHandler {try await task.value} onCancel: {task.cancel()}
      guard self.context == context,readID == run,!Task.isCancelled else {return}
      guard let value else {availability = .needsHostGrant(.fileTransfer);catalog=nil;notice=nil;return}
      catalog=value;availability = .available;needsRefresh=false;notice=nil
    } catch {
      guard self.context == context,readID == run,!Task.isCancelled else {return}
      catalog=nil;needsRefresh=true
      if case RemoteError.forbidden = error {availability = .needsHostGrant(.fileTransfer)}
      else {notice="Changes could not be checked. Reconnect or continue on your computer."}
    }
  }
  func open(_ ref: ChangeRef, client: BridgeClient, context: ChangeContext) async {
    guard self.context == context,availability == .available,!needsRefresh,let catalog,catalog.files.contains(ref) else {return}
    closeDiff();let run=UUID();openID=run;opening=ref;notice=nil
    let key=context.key,task=Task<FileDiff?,any Error> {
      guard try await client.deviceAccess().features.fileTransfer else {return nil}
      return try await client.diff(key.workspaceId,key.sessionId,ref:ref,revision:catalog.revision)
    }
    openTask=task
    defer {if openID == run {opening=nil;openTask=nil}}
    do {
      let value=try await withTaskCancellationHandler {try await task.value} onCancel: {task.cancel()}
      guard self.context == context,openID == run,!Task.isCancelled else {return}
      guard let value else {availability = .needsHostGrant(.fileTransfer);self.catalog=nil;return}
      let parsed=await Task.detached(priority:.userInitiated) {DiffLine.parse(value.text)}.value
      guard self.context == context,openID == run,!Task.isCancelled else {return}
      diff=value;lines=parsed
    } catch {
      guard self.context == context,openID == run,!Task.isCancelled else {return}
      needsRefresh=true
      switch error {
      case RemoteError.conflict,RemoteError.notFound: notice="The workspace changed. Refresh changes before opening another file."
      case RemoteError.forbidden: availability = .needsHostGrant(.fileTransfer);self.catalog=nil;notice=nil
      default: notice="The diff could not be checked. Refresh changes or continue on your computer."
      }
    }
  }
}
