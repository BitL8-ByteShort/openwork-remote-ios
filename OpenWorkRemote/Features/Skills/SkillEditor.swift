import OpenWorkRemoteCore
import SwiftUI

struct SkillEditor: View {
  let context: SkillContext, detail: SkillDetail?
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State private var draft: SkillDraft?
  @State private var notice: String?
  @State private var preview = false
  @State private var replaceCurrent = false
  var body: some View {
    Form {
      Section {
        Text(
          "This changes one workspace skill on your computer. It does not grant tool permissions."
        ).foregroundStyle(Theme.muted)
      }
      if let notice { Section { Text(notice).foregroundStyle(Theme.muted) } }
      if let notice = model.skills.notice {
        Section {
          Text(notice).foregroundStyle(Theme.muted).accessibilityIdentifier("skill-editor-notice")
        }
      }
      if let draft {
        Section("Name") {
          if draft.id == nil {
            TextField("my-skill", text: nameBinding).textInputAutocapitalization(.never)
              .autocorrectionDisabled().accessibilityIdentifier("skill-name")
          } else {
            Text(draft.name)
          }
        }
        Section {
          TextEditor(text: contentBinding).font(.body.monospaced()).frame(minHeight: 260)
            .accessibilityIdentifier("skill-editor-content")
        } header: {
          Text("Skill instructions")
        } footer: {
          Text(
            "OpenWork’s skill format includes name and description at the top. Keep those fields when editing. Up to 64 KiB of text; larger encoded requests stay on this phone."
          )
        }
        Section {
          DisclosureGroup("Preview", isExpanded: $preview) {
            Text(draft.content).font(.body.monospaced()).textSelection(.enabled)
          }
          Text("Draft saved on this phone").font(.caption).foregroundStyle(Theme.muted)
        }
        Section {
          Button {
            Task { await save() }
          } label: {
            HStack {
              Text("Save workspace skill")
              if model.skills.saving {
                Spacer()
                ProgressView()
              }
            }
          }.disabled(!model.skills.canEdit || model.skillContext != context)
            .accessibilityIdentifier("skill-save")
          if draft.id != nil {
            Button("Replace draft with current instructions") { replaceCurrent = true }.disabled(
              model.skills.saving || model.skillContext != context)
          } else {
            Button("Refresh catalog and keep draft") { Task { await reviewNew() } }.disabled(
              model.skills.saving || model.skillContext != context)
          }
        }
      } else {
        ProgressView("Opening draft…")
      }
    }.disabled(model.skills.saving).navigationTitle(detail == nil ? "Add skill" : "Edit skill")
      .navigationBarTitleDisplayMode(.inline).scrollContentBackground(.hidden).background(
        Theme.background
      )
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Done") {
            Task {
              do {
                try await model.skills.flush()
                dismiss()
              } catch {
                notice = "Your draft could not be saved. Copy the instructions before leaving."
              }
            }
          }.disabled(model.skills.saving).accessibilityIdentifier("skill-editor-done")
        }
      }
      .task {
        guard draft == nil else { return }
        do {
          draft = try model.skills.beginDraft(detail: detail, context: context)
          try await model.skills.flush()
        } catch { notice = "This draft could not be opened. Review the skill on your computer." }
      }
      .confirmationDialog(
        "Replace your saved draft?", isPresented: $replaceCurrent, titleVisibility: .visible
      ) {
        Button("Use current instructions", role: .destructive) { Task { await replace() } }
        Button("Keep draft", role: .cancel) {}
      } message: {
        Text(
          "Your edits on this phone will be replaced with the current instructions from your computer."
        )
      }
  }
  private var nameBinding: Binding<String> {
    Binding(
      get: { draft?.name ?? "" },
      set: { value in
        guard var d = draft else { return }
        let old = d.name
        d.name = value
        if d.content.hasPrefix("---\n"), d.content.contains("\nname: " + old + "\n") {
          d.content = d.content.replacingOccurrences(
            of: "\nname: " + old + "\n", with: "\nname: " + value + "\n")
        }
        update(d)
      })
  }
  private var contentBinding: Binding<String> {
    Binding(
      get: { draft?.content ?? "" },
      set: { value in
        guard var d = draft else { return }
        d.content = value
        update(d)
      })
  }
  private func update(_ d: SkillDraft) {
    do {
      try model.skills.updateDraft(d, context: context)
      draft = d
      notice = nil
    } catch { notice = "This edit could not be saved. Keep the text within 64 KiB." }
  }
  private func save() async {
    guard let draft else { return }
    if await model.changeSkill(
      .save(
        name: draft.name, content: draft.content, revision: draft.revision,
        catalogRevision: draft.catalogRevision), context: context)
    {
      dismiss()
    }
  }
  private func replace() async {
    guard let id = draft?.id else { return }
    do {
      let current = try await model.skillDetail(id, context: context)
      draft = try await model.skills.replaceDraft(detail: current, context: context)
      notice = nil
    } catch { notice = "Current instructions could not be checked. Your draft is kept." }
  }
  private func reviewNew() async {
    await model.refreshSkills()
    guard let old = draft, let catalog = model.skills.catalog, model.skillContext == context else {
      return
    }
    let value = SkillDraft(
      hostId: old.hostId, workspaceId: old.workspaceId, id: old.id, revision: old.revision,
      catalogRevision: catalog.revision, name: old.name, content: old.content)
    update(value)
  }
}
