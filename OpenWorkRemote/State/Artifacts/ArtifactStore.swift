import Foundation
import Observation
import OpenWorkRemoteCore

struct ArtifactContext: Equatable, Sendable {
  let key: DraftKey
  let generation: UUID
  let selection: UUID
}
@MainActor @Observable final class ArtifactStore {
  let files: ProtectedArtifactFiles
  private(set) var context: ArtifactContext?
  private(set) var availability: FeatureAvailability = .unsupported
  private(set) var items: [ArtifactRef] = []
  private(set) var moreOnComputer = false
  private(set) var loading = false
  private(set) var downloading: ArtifactRef?
  private(set) var receivedBytes = 0
  private(set) var ready: LocalArtifact?
  private(set) var preview: ArtifactPreviewData?
  private(set) var notice: String?
  @ObservationIgnored private var readID = UUID()
  @ObservationIgnored private var downloadID = UUID()
  @ObservationIgnored private var previewID = UUID()
  @ObservationIgnored private var downloadTask: Task<LocalArtifact, any Error>?
  @ObservationIgnored private var previewTask: Task<ArtifactPreviewData, any Error>?
  init(directory: URL? = nil) { files = ProtectedArtifactFiles(directory:directory?.appending(path:"ArtifactDownloads",directoryHint:.isDirectory)) }
  var canShare: Bool { ready != nil && preview != nil && downloading == nil && availability == .available }
  func activate(_ value: ArtifactContext?) {
    guard context != value else { return }
    closePreview(); readID = UUID(); context = value; items = []; moreOnComputer = false
    loading = false; availability = .unsupported; notice = nil
  }
  func closePreview() {
    downloadID = UUID(); previewID = UUID(); downloadTask?.cancel(); previewTask?.cancel()
    downloadTask = nil; previewTask = nil; downloading = nil; receivedBytes = 0; preview = nil
    if let old = ready { let files = files; Task { try? await files.remove(old) } }
    ready = nil
  }
  func discardCopies() -> Task<Void, any Error> {
    let download=downloadTask, rendering=previewTask, files=files
    closePreview()
    return Task {
      _ = await download?.result; _ = await rendering?.result
      try await files.reset()
    }
  }
  func refresh(client: BridgeClient, context: ArtifactContext, supported: Bool) async {
    guard self.context == context else { return }
    let read = UUID(); readID = read
    guard supported else { availability = .unsupported; items = []; closePreview(); return }
    loading = true
    defer { if readID == read { loading = false } }
    do {
      let access = try await client.deviceAccess()
      guard self.context == context, readID == read, !Task.isCancelled else { return }
      guard access.features.fileTransfer else {
        availability = .needsHostGrant(.fileTransfer); items = []; closePreview(); return
      }
      let catalog = try await client.artifacts(context.key.workspaceId,context.key.sessionId)
      guard self.context == context, readID == read, !Task.isCancelled else { return }
      try await files.cleanup()
      guard self.context == context, readID == read, !Task.isCancelled else { return }
      items = catalog.items; moreOnComputer = catalog.moreOnComputer; availability = .available; notice = nil
      if let ready, !items.contains(ready.ref) { closePreview() }
    } catch {
      guard self.context == context, readID == read, !Task.isCancelled else { return }
      availability = .unsupported; items = []; closePreview()
      notice = "Files could not be checked. Reconnect or continue on your computer."
    }
  }
  private func progress(_ count: Int, context: ArtifactContext, run: UUID) {
    guard self.context == context, downloadID == run else { return }; receivedBytes = count
  }
  func download(_ ref: ArtifactRef, client: BridgeClient, context: ArtifactContext) async {
    guard self.context == context, availability == .available, items.contains(ref) else { return }
    closePreview(); let run = UUID(); downloadID = run; downloading = ref; receivedBytes = 0; notice = nil
    let files = files, wid = context.key.workspaceId
    let task = Task { [weak self] in
      try await files.download(ref,client:client,workspaceId:wid) { [weak self] count in
        await self?.progress(count,context:context,run:run)
      }
    }
    downloadTask = task
    var downloaded: LocalArtifact?
    defer { if downloadID == run { downloadTask = nil; downloading = nil } }
    do {
      let local = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
      downloaded = local
      guard self.context == context, downloadID == run, !Task.isCancelled else { try? await files.remove(local); return }
      let value = try await files.preview(local)
      guard self.context == context, downloadID == run, !Task.isCancelled else { try? await files.remove(local); return }
      ready = local; preview = value
    } catch {
      if let downloaded { try? await files.remove(downloaded) }
      guard self.context == context, downloadID == run, !Task.isCancelled else { return }
      switch error {
      case RemoteError.conflict, RemoteError.notFound:
        notice = "This file changed or is no longer available. Refresh the files and try again."
      case RemoteError.oversized:
        notice = "The file could not be downloaded within the allowed size. Check it on your computer."
      case RemoteError.invalidResponse:
        notice = "This file could not be previewed. It may be damaged or unsupported. Check it on your computer."
      default: notice = "The download did not finish. Check your connection and available storage, then try again."
      }
    }
  }
  func showPage(_ page: Int, context: ArtifactContext) async {
    guard self.context == context, let ready, ready.ref.previewKind == .pdf else { return }
    previewTask?.cancel(); let run = UUID(); previewID = run
    let files = files, task = Task { try await files.preview(ready,page:page) }; previewTask = task
    do {
      let value = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
      guard self.context == context, previewID == run, self.ready == ready, !Task.isCancelled else { return }
      preview = value; notice = nil
    } catch {
      guard self.context == context, previewID == run, !Task.isCancelled else { return }
      notice = "This page could not be displayed. Check the PDF on your computer."
    }
  }
  func prepareShare(client: BridgeClient, context: ArtifactContext) async -> URL? {
    guard self.context == context, canShare, let ready else { return nil }
    let run = downloadID
    do {
      let access = try await client.deviceAccess()
      guard self.context == context, downloadID == run else { return nil }
      guard access.features.fileTransfer else { availability = .needsHostGrant(.fileTransfer); closePreview(); return nil }
      let catalog = try await client.artifacts(context.key.workspaceId,context.key.sessionId)
      guard self.context == context, downloadID == run else { return nil }
      guard catalog.items.contains(ready.ref) else { throw RemoteError.conflict }
      try await files.verify(ready)
      guard self.context == context, downloadID == run, !Task.isCancelled else { return nil }
      return ready.url
    } catch {
      guard self.context == context, downloadID == run else { return nil }
      closePreview(); notice = "The file or its access changed. Refresh the files before sharing."
      return nil
    }
  }
}
