import SwiftUI

/// Recovery state from the reviewed Penpot ST-02 frame.
struct RevokedConnectionView: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 28) {
        Image(systemName: "checkmark.shield")
          .font(.title).foregroundStyle(.orange).padding(20)
          .background(.orange.opacity(0.1), in: Circle())
          .padding(.top, 40)
        Text("This phone’s access was removed.")
          .font(.largeTitle.weight(.semibold)).tracking(-0.8)
        Text("Pair again to restore access. In OpenWork on your computer, open Settings → Remote access and create a new pairing code.")
          .foregroundStyle(Theme.muted).lineSpacing(4)
        Label("Your drafts are still on this phone. They stay with this computer.", systemImage: "checkmark")
          .font(.callout).foregroundStyle(Theme.muted).padding(20)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20))
        if let notice = model.notice {
          Label(notice, systemImage: "exclamationmark.circle")
            .font(.callout).foregroundStyle(.red)
        }
        Button("Pair again") { model.connect() }
          .buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("pair-again")
      }.padding(24)
    }.background(Theme.background).foregroundStyle(Theme.ink)
      .navigationTitle("Your connection").navigationBarTitleDisplayMode(.inline)
  }
}
