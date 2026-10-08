import SwiftUI

struct PairingView: View {
  @Environment(AppModel.self) private var model
  @State private var payload = ""
  @State private var scanning = false
  @State private var paste = false
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        BrandMark()
        Text(model.pendingPhone ? "Confirm on your computer." : "Connect your computer.").font(
          .largeTitle.weight(.semibold)
        ).tracking(-0.8)
        Text(
          model.pendingPhone
            ? "Your phone is waiting. Choose its workspaces and approve the connection in the setup page."
            : "Scan the pairing code from your computer’s setup page."
        ).foregroundStyle(Theme.muted).lineSpacing(4)
        ZStack {
          RoundedRectangle(cornerRadius: 28).fill(Theme.surface)
          VStack(spacing: 20) {
            if model.pendingPhone {
              ProgressView().controlSize(.large)
              Text("Waiting for approval").font(.headline)
            } else {
              Image(systemName: "qrcode.viewfinder").font(.system(size: 92, weight: .light))
                .foregroundStyle(Theme.accent)
              Text("Your code stays private.").font(.callout).foregroundStyle(Theme.muted)
            }
          }
        }.frame(height: 230)
        if let error = model.pairingError {
          Label(error, systemImage: "exclamationmark.circle").font(.callout).foregroundStyle(.red)
            .padding(16).background(.red.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
            .accessibilityIdentifier("pairing-error")
        }
        if model.pendingPhone {
          Button("Cancel pairing") { model.cancelPairing() }.frame(
            maxWidth: .infinity, minHeight: 44)
        } else {
          Button("Scan pairing code") { scanning = true }.buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("scan-pairing")
          Button("Paste pairing code") { paste = true }.frame(maxWidth: .infinity, minHeight: 44)
            .accessibilityIdentifier("paste-pairing")
        }
        Text("Your computer chooses what this phone can access.").font(.caption).foregroundStyle(
          Theme.muted
        ).frame(maxWidth: .infinity)
      }.padding(24)
    }.background(Theme.background).foregroundStyle(Theme.ink).navigationTitle("Pair your computer")
      .navigationBarTitleDisplayMode(.inline).sheet(isPresented: $scanning) {
        QRScannerView { value in
          scanning = false
          model.pair(value)
        }
      }.sheet(isPresented: $paste) {
        NavigationStack {
          VStack(alignment: .leading, spacing: 20) {
            Text("Paste the pairing payload copied from your computer.").foregroundStyle(
              Theme.muted)
            TextEditor(text: $payload).font(.body.monospaced()).frame(minHeight: 180).padding(12)
              .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
              .accessibilityIdentifier("pairing-payload")
            Button("Connect") {
              paste = false
              model.pair(payload)
              payload = ""
            }.buttonStyle(PrimaryButtonStyle()).disabled(payload.isEmpty).accessibilityIdentifier(
              "connect-payload")
            Spacer()
          }.padding(24).background(Theme.background).navigationTitle("Paste pairing code")
            .navigationBarTitleDisplayMode(.inline).toolbar {
              ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                  paste = false
                  payload = ""
                }
              }
            }
        }
      }
  }
}
