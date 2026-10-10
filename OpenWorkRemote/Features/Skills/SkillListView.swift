import OpenWorkRemoteCore
import SwiftUI

struct SkillEditPresentation: Identifiable {
  let id = UUID()
  let context: SkillContext
  let detail: SkillDetail?
}
struct SkillListView: View {
  @Environment(AppModel.self) private var model
  @State private var editor: SkillEditPresentation?
  var body: some View {
    List {
      Section {
        Text(
          "Skills contain instructions used by OpenWork. Select skills for your next message; OpenWork keeps its tool approval rules."
        ).foregroundStyle(Theme.muted)
      }
      if model.skills.loading { ProgressView("Checking skills…") }
      if let notice = model.skills.notice {
        Section {
          Text(notice).foregroundStyle(Theme.muted).accessibilityIdentifier("skill-notice")
        }
      }
      if let catalog = model.skills.catalog, let c = model.skillContext {
        Section {
          ForEach(
            catalog.items.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
          ) { item in
            NavigationLink {
              SkillDetailView(item: item, context: c)
            } label: {
              VStack(alignment: .leading, spacing: 6) {
                HStack {
                  Text(item.name).font(.headline)
                  if model.selectedSkillIDs.contains(item.id) {
                    Image(systemName: "checkmark.circle.fill").accessibilityLabel(
                      "Selected for next message")
                  }
                }
                Text(item.sourceLabel + " · " + (item.editable ? "Editable" : "Read only")).font(
                  .caption
                ).foregroundStyle(Theme.muted)
              }.padding(.vertical, 6)
            }.accessibilityIdentifier("skill-row-" + item.id)
          }
          if catalog.items.isEmpty {
            Text("No skills available in this workspace.").foregroundStyle(Theme.muted)
          }
        }
        Section {
          Button("Add workspace skill") { editor = SkillEditPresentation(context: c, detail: nil) }
            .disabled(!model.skills.canEdit).accessibilityIdentifier("skill-add")
          if !model.skills.administration {
            Text(
              "Allow workspace administration for this phone in Remote access on your computer to add or edit skills."
            ).font(.caption).foregroundStyle(Theme.muted)
          } else if !model.skills.writeSupported {
            Text("Skill editing is unavailable on this computer. Manage skills in OpenWork.").font(
              .caption
            ).foregroundStyle(Theme.muted)
          }
        }
      } else if !model.skills.loading {
        Section {
          Text(
            model.connection == .ready
              ? "Skills are unavailable on this computer. Update OpenWork Remote Preview or manage them in OpenWork."
              : "Reconnect to check skills. Your saved drafts stay on this phone."
          ).foregroundStyle(Theme.muted)
        }
      }
      Section {
        Button("Refresh skills") { Task { await model.refreshSkills() } }.disabled(
          model.skills.saving
        ).accessibilityIdentifier("skills-refresh")
        if model.skills.canReview, let c = model.skillContext {
          Button("I’ve reviewed this change") {
            Task { try? await model.skills.acknowledgeCurrent(context: c) }
          }.accessibilityIdentifier("skills-acknowledge")
        }
      }
    }.navigationTitle("Skills").navigationBarTitleDisplayMode(.inline).scrollContentBackground(
      .hidden
    ).background(Theme.background)
      .task(id: model.skillsRefreshID) { await model.refreshSkills() }
      .sheet(item: $editor) { value in
        NavigationStack { SkillEditor(context: value.context, detail: value.detail) }
      }
  }
}
