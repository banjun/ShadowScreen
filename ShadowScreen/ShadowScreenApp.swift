import SwiftUI
import AVFoundation
import CoreImage

@main
struct ShadowScreenApp: App {
    @StateObject var captureSession = CaptureSession()

    var body: some Scene {
        WindowGroup() {
            CGImageView(image: captureSession.presentedImage)
                .onAppear {captureSession.startRunning()}
                .onDisappear {captureSession.stopRunning()}
            // PreviewLayerView(previewLayer: captureSession.presentedImage)
        }
    }
}

struct CGImageView: NSViewRepresentable {
    var image: CGImage?

    func updateNSView(_ nsView: NSViewType, context: Context) {
        nsView.layer!.contents = image
    }

    func makeNSView(context: Context) -> some NSView {
        let v = NSView()
        v.wantsLayer = true
        v.layer!.contentsGravity = .resizeAspect
        return v
    }
}

struct PreviewLayerView: NSViewRepresentable {
    var previewLayer: AVCaptureVideoPreviewLayer?

    func updateNSView(_ nsView: NSView, context: Context) {
        nsView.layer!.sublayers?.forEach {$0.removeFromSuperlayer()}
        if let previewLayer = previewLayer {
            nsView.layer!.addSublayer(previewLayer)
        }
        context.coordinator.nsView = nsView
    }

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        v.wantsLayer = true
        updateNSView(v, context: context)
        return v
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {
        var nsView: NSView? {
            didSet {
                if let nsView = nsView {
                    nsView.layer!.sublayers?.forEach {$0.frame = nsView.bounds}
                }
                observation = nsView?.observe(\.frame) { nsView, _ in
                    nsView.layer!.sublayers?.forEach {$0.frame = nsView.bounds}
                }
            }
        }
        private var observation: NSKeyValueObservation?
    }
}
