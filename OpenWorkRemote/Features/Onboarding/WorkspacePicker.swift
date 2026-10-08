import SwiftUI

struct WorkspacePicker: View {
  @Environment(AppModel.self) private var model
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        Image(systemName: "checkmark.circle.fill").font(.system(size: 44)).foregroundStyle(.green)
          .accessibilityHidden(true)
        Text("You’re connected.").font(.largeTitle.weight(.semibold))
        Text("Choose a workspace from \(model.host?.displayName ?? "your computer").")
          .foregroundStyle(Theme.muted)
        ForEach(model.workspaces) { w in
          Button {
            Task {
              await model.changeWorkspace(w)
              model.onboardingStep = 5
            }
          } label: {
            HStack(spacing: 16) {
              Image(systemName: "folder").font(.title2).foregroundStyle(Theme.accent)
              Text(w.name).font(.headline).foregroundStyle(Theme.ink)
              Spacer()
              Image(systemName: "chevron.right").foregroundStyle(Theme.muted)
            }.padding(22).background(Theme.raised, in: RoundedRectangle(cornerRadius: 20)).overlay(
              RoundedRectangle(cornerRadius: 20).stroke(Theme.line))
          }.accessibilityIdentifier("workspace-\(w.id)")
        }
        Text("Only workspaces approved on your computer appear here.").font(.caption)
          .foregroundStyle(Theme.muted)
      }.padding(24)
    }.background(Theme.background).navigationTitle("Choose workspace")
      .navigationBarTitleDisplayMode(.inline)
  }
}
