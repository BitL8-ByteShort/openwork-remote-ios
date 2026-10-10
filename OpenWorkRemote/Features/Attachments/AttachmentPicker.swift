import SwiftUI
import PhotosUI
import CoreTransferable
import UniformTypeIdentifiers
import OpenWorkRemoteCore

private struct SelectedPhoto: Transferable, Sendable {
  let png: Data
  static var transferRepresentation: some TransferRepresentation {
    FileRepresentation(importedContentType:.image) { received in
      // The picker owns this URL only during import. Convert before returning;
      // no source URL or metadata survives into the view or a JSON draft.
      SelectedPhoto(png:try await ProtectedAttachmentFiles.shared.normalizedPhoto(received.file))
    }
  }
}

struct AttachmentPicker: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  let context: AttachmentContext
  @State private var photo: PhotosPickerItem?
  @State private var importing = false
  @State private var browse = false
  @State private var error: String?
  private var store: AttachmentStore { model.attachments }
  private var available: Bool { model.attachmentContext == context && model.connection == .ready && store.canChoose && store.rows.count < 4 && !importing }
  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment:.leading,spacing:20) {
          Text("ATTACHMENTS").font(.caption.weight(.semibold)).foregroundStyle(Theme.muted)
          Text("Give your chat\na little context.").font(.largeTitle.weight(.semibold))
          Text("Choose a photo or PDF. You can remove it before sending.").foregroundStyle(Theme.muted)
          if let reason { Text(reason).font(.callout).foregroundStyle(Theme.muted).accessibilityIdentifier("attachment-availability") }
          VStack(spacing:12) {
            PhotosPicker(selection:$photo,matching:.images,preferredItemEncoding:.current) {
              AttachmentChoice("Choose photos",symbol:"photo")
            }.disabled(!available || store.limits?.inputMIMEs.contains("image/png") != true)
              .accessibilityLabel("Choose photos")
            Button { browse = true } label: { AttachmentChoice("Browse files",symbol:"doc") }
              .disabled(!available).accessibilityLabel("Browse files")
          }.padding(.vertical,12)
          if importing { ProgressView("Preparing selected file…").accessibilityIdentifier("attachment-preparing") }
          if let error { Text(error).font(.callout).foregroundStyle(.red) }
          if let notice = store.notice { Text(notice).font(.callout).foregroundStyle(Theme.muted) }
          ForEach(store.rows) { row in
            AttachmentRow(row:row,context:context)
          }
          #if DEBUG
          if ProcessInfo.processInfo.arguments.contains("-attachment-fixture-files") {
            Button("Use fixture PDF") { Task { await addAttachmentUITestSample(model:model,context:context,photo:false) } }
              .disabled(!available)
            Button("Use fixture photo") { Task { await addAttachmentUITestSample(model:model,context:context,photo:true) } }
              .disabled(!available || store.limits?.inputMIMEs.contains("image/png") != true)
          }
          #endif
          Text("Photos become PNGs up to 2,048 pixels on the longest edge. Location and camera metadata are not copied. Your original stays unchanged.")
            .font(.footnote).foregroundStyle(Theme.muted)
          Text("Not sent as a message yet. Attachments go to your paired computer and may reach its model provider when you send.")
            .font(.footnote).foregroundStyle(Theme.muted)
          Text("Up to four files, 20 MiB per file and 40 MiB per message. Your computer or model may allow less.")
            .font(.footnote).foregroundStyle(Theme.muted)
          Button("Add to message") { dismiss() }.buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("attachment-add-to-message")
        }.padding(24)
      }.background(Theme.background).foregroundStyle(Theme.ink)
        .navigationTitle("Add to your message").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement:.topBarTrailing) { Button("Done") { dismiss() }.accessibilityIdentifier("attachment-done") } }
        .task { await model.refreshAttachments() }
        .onChange(of:photo) { _, value in
          guard let value else { return }
          importing = true; error = nil
          Task {
            defer { importing = false; photo = nil }
            do {
              guard let selected = try await value.loadTransferable(type:SelectedPhoto.self) else { throw RemoteError.invalidResponse }
              guard model.attachmentContext == context else { return }
              let file = try await store.files.savePhotoPNG(selected.png)
              await model.addAttachment(file,context:context)
            } catch { self.error = "This photo could not be prepared. Choose a JPEG, HEIC or PNG up to 20 MiB." }
          }
        }
        .fileImporter(isPresented:$browse,allowedContentTypes:allowedTypes,allowsMultipleSelection:false) { result in
          guard case let .success(urls) = result, let selected = urls.first else { return }
          importing = true; error = nil
          Task {
            defer { importing = false }
            do {
              let file: LocalAttachmentFile
              if selected.pathExtension.lowercased() == "pdf" { file = try await store.files.importPDF(selected) }
              else { file = try await store.files.importPhoto(selected) }
              await model.addAttachment(file,context:context)
            } catch { self.error = "This file could not be prepared. Choose a supported photo or PDF up to 20 MiB, and check free storage." }
          }
        }
    }
  }
  private var reason: String? {
    if model.attachmentContext != context { return "This chat changed. Close this sheet and open attachments in the current chat." }
    if model.connection != .ready { return "Reconnect to your computer before adding files. Your selected files are kept." }
    if store.limits?.inputMIMEs.isEmpty == true { return "This chat's current model does not accept photos or PDFs. Change its model on your computer or in Model settings." }
    switch store.availability {
    case .available: return nil
    case .needsHostGrant: return "File access is not allowed for this phone. Allow file transfer in Remote access on your computer."
    case .unsupported:
      if model.host?.capabilities.attachments != true { return "This computer does not support attachments yet. Update OpenWork Remote on your computer." }
      return store.checkingAccess ? "Checking attachment access…" : "Attachments are unavailable on this connection. Reconnect or continue on your computer."
    }
  }
  private var allowedTypes: [UTType] {
    var types: [UTType] = []
    if store.limits?.inputMIMEs.contains("application/pdf") == true { types.append(.pdf) }
    if store.limits?.inputMIMEs.contains("image/png") == true { types += [.jpeg,.heic,.png] }
    return types
  }
}
private struct AttachmentChoice: View {
  let label: String
  let symbol: String
  nonisolated init(_ label: String, symbol: String) { self.label = label; self.symbol = symbol }
  var body: some View {
    HStack { Label(label,systemImage:symbol).font(.headline); Spacer(); Image(systemName:"chevron.right") }
      .frame(minHeight:44).padding(.horizontal,16).padding(.vertical,8)
      .foregroundStyle(Theme.ink).background(Theme.raised,in:RoundedRectangle(cornerRadius:18))
      .overlay(RoundedRectangle(cornerRadius:18).stroke(Theme.line))
  }
}

struct AttachmentRow: View {
  @Environment(AppModel.self) private var model
  let row: AttachmentDraft
  let context: AttachmentContext
  var body: some View {
    VStack(alignment:.leading,spacing:8) {
      Text(row.file.name).font(.callout.weight(.semibold)).lineLimit(2)
      Text(ByteCountFormatter.string(fromByteCount:Int64(row.file.bytes),countStyle:.file) + " · " + label)
        .font(.caption).foregroundStyle(Theme.muted)
      if [.uploading,.committing,.allocating].contains(row.phase) {
        ProgressView(value:Double(row.receivedBytes),total:Double(row.file.bytes))
      }
      HStack {
        if row.phase == .failed || row.phase == .selected {
          Button("Retry") { Task { await model.retryAttachment(row.id,context:context) } }.frame(minHeight:44)
        }
        if row.phase == .uncertain || row.phase == .expired {
          Button("Check status") { Task { await model.retryAttachment(row.id,context:context,check:true) } }.frame(minHeight:44)
        }
        if row.promptID == nil || row.promptReviewed == true {
          Button([.uploading,.committing,.allocating].contains(row.phase) ? "Cancel upload" : "Remove",role:.destructive) {
            Task { await model.removeAttachment(row.id,context:context) }
          }.frame(minHeight:44)
        }
      }.font(.caption.weight(.semibold))
    }.frame(maxWidth:.infinity,alignment:.leading).padding(16)
      .background(Theme.surface,in:RoundedRectangle(cornerRadius:18))
      .accessibilityIdentifier("attachment-row-" + row.id.uuidString.lowercased())
  }
  private var label: String {
    switch row.phase {
    case .selected: "Selected"
    case .allocating: "Preparing upload"
    case .uploading: "Uploading"
    case .committing: "Checking on computer"
    case .ready: "Ready to send"
    case .failed: "Upload paused"
    case .uncertain: "Status unconfirmed"
    case .sending: "Sending message"
    case .attached: "Sent"
    case .cancelPending: "Cleanup unconfirmed"
    case .cancelled: "Removed"
    case .expired: "Expired — remove and select again"
    }
  }
}
