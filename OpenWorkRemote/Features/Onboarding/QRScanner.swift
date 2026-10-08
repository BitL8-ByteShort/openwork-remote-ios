import AVFoundation
import SwiftUI

struct QRScannerView: View {
  let onCode: (String) -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var granted = false
  @State private var denied = false
  var body: some View {
    NavigationStack {
      ZStack {
        Theme.background.ignoresSafeArea()
        if granted {
          CameraView(onCode: onCode).ignoresSafeArea(edges: .bottom)
        } else if denied {
          ContentUnavailableView {
            Label("Camera access is off", systemImage: "camera")
          } description: {
            Text("You can paste the pairing code, or allow camera access in Settings.")
          } actions: {
            Button("Open Settings") {
              if let u = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(u)
              }
            }
            Button("Use paste instead") { dismiss() }
          }
        } else {
          ProgressView()
        }
      }.navigationTitle("Scan pairing code").navigationBarTitleDisplayMode(.inline).toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
      }.task {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        if status == .authorized {
          granted = true
        } else if status == .notDetermined {
          granted = await AVCaptureDevice.requestAccess(for: .video)
          denied = !granted
        } else {
          denied = true
        }
      }
    }
  }
}
private struct CameraView: UIViewRepresentable {
  let onCode: (String) -> Void
  func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }
  func makeUIView(context: Context) -> PreviewView {
    let view = PreviewView()
    context.coordinator.configure(view)
    return view
  }
  func updateUIView(_ view: PreviewView, context: Context) {}
  static func dismantleUIView(_ view: PreviewView, coordinator: Coordinator) { coordinator.stop() }
  // AVFoundation invokes this delegate on the explicitly configured main queue.
  final class Coordinator: NSObject, @preconcurrency AVCaptureMetadataOutputObjectsDelegate,
    @unchecked Sendable
  {
    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "openwork.camera")
    private let onCode: (String) -> Void
    private var used = false
    init(onCode: @escaping (String) -> Void) { self.onCode = onCode }
    @MainActor func configure(_ view: PreviewView) {
      view.preview.session = session
      queue.async { [self] in
        do {
          guard let camera = AVCaptureDevice.default(for: .video) else { return }
          let input = try AVCaptureDeviceInput(device: camera)
          guard session.canAddInput(input) else { return }
          session.addInput(input)
          let output = AVCaptureMetadataOutput()
          guard session.canAddOutput(output) else { return }
          session.addOutput(output)
          output.setMetadataObjectsDelegate(self, queue: .main)
          output.metadataObjectTypes = [.qr]
          session.startRunning()
        } catch {}
      }
    }
    @MainActor func metadataOutput(
      _ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject],
      from connection: AVCaptureConnection
    ) {
      guard !used,
        let value = (metadataObjects.first as? AVMetadataMachineReadableCodeObject)?.stringValue
      else { return }
      used = true
      stop()
      onCode(value)
    }
    func stop() { queue.async { [self] in if session.isRunning { session.stopRunning() } } }
  }
}
private final class PreviewView: UIView {
  override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
  var preview: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
  override init(frame: CGRect) {
    super.init(frame: frame)
    preview.videoGravity = .resizeAspectFill
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) is unsupported") }
}
