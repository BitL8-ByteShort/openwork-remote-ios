import OpenWorkRemoteCore
import SwiftUI

struct SkillDetailView: View {
  let item: SkillSummary, context: SkillContext
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State private var detail: SkillDetail?
  @State private var notice: String?
  @State private var loading = false
  @State private var editor: SkillEditPresentation?
  @State private var confirmDelete = false
  private var current: SkillSummary { detail?.item ?? item }
  var body: some View {
    List {
      Section {
        Text(current.description)
        LabeledContent("Source", value: current.sourceLabel)
        LabeledContent("Editing", value: current.editable ? "Workspace text" : "Read only")
      }
      if loading { ProgressView("Loading instructions…") }
      if let notice { Section { Text(notice).foregroundStyle(Theme.muted) } }
      if let notice = model.skills.notice { Section { Text(notice).foregroundStyle(Theme.muted) } }
      Section {
        Button(
          model.selectedSkillIDs.contains(current.id)
            ? "Remove from next message" : "Use for next message"
        ) { model.toggleSelectedSkill(current) }.disabled(
          !current.selectable || model.host?.capabilities.skillsSelect != true
            || model.selectedSession == nil || model.sending || model.skillContext != context
        ).accessibilityIdentifier("skill-select")
        if !current.selectable {
          Text("This entry is not available for selection in OpenWork’s current skill catalog.")
            .font(.caption).foregroundStyle(Theme.muted)
        }
      }
      Section {
        Button("Edit workspace skill") {
          editor = SkillEditPresentation(context: context, detail: detail)
        }.disabled(
          detail?.content == nil || !current.editable || !model.skills.canEdit
            || model.skillContext != context
        ).accessibilityIdentifier("skill-edit")
        Button("Remove workspace skill", role: .destructive) { confirmDelete = true }.disabled(
          !current.editable || !model.skills.canEdit || model.skillContext != context
        ).accessibilityIdentifier("skill-delete")
        if !current.editable {
          Text(
            "Inherited, global and managed skills are read-only here. Manage their source on your computer."
          ).font(.caption).foregroundStyle(Theme.muted)
        }
      }
      Section("Instructions") {
        if let content = detail?.content {
          Text(content).font(.body.monospaced()).textSelection(.enabled).accessibilityIdentifier(
            "skill-content")
        } else if !loading {
          Text(
            "These instructions stay on your computer. This skill can still be selected when OpenWork permits it."
          ).foregroundStyle(Theme.muted)
        }
      }
      Section {
        Button("Refresh instructions") { Task { await load() } }.disabled(model.skills.saving)
      }
    }.navigationTitle(current.name).navigationBarTitleDisplayMode(.inline).scrollContentBackground(
      .hidden
    ).background(Theme.background)
      .task(id: model.skills.catalog?.revision) { await load() }
      .sheet(item: $editor) { value in
        NavigationStack { SkillEditor(context: value.context, detail: value.detail) }
      }
      .confirmationDialog(
        "Remove \(current.name)?", isPresented: $confirmDelete, titleVisibility: .visible
      ) {
        Button("Remove skill", role: .destructive) {
          Task {
            if await model.changeSkill(
              .delete(id: current.id, revision: current.revision), context: context)
            {
              dismiss()
            }
          }
        }
        Button("Keep skill", role: .cancel) {}
      } message: {
        Text(
          "This permanently removes the workspace text skill from your computer. There is no undo.")
      }
  }
  private func load() async {
    guard model.skillContext == context else { return }
    loading = true
    defer { loading = false }
    do {
      let value = try await model.skillDetail(item.id, context: context)
      guard model.skillContext == context else { return }
      detail = value
      notice = nil
    } catch {
      notice =
        "These instructions could not be checked. Refresh or review this skill on your computer."
    }
  }
}
