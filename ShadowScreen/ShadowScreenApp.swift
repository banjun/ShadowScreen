import SwiftUI
import AVFoundation
import CoreImage
import Combine

@main
struct ShadowScreenApp: App {
    @StateObject var appState: State = .init()
    @StateObject var captureSession = CaptureSession()

    class State: ObservableObject {
        @Published private(set) var window: ScreenCapture.Window?
        private let screenCapture: ScreenCapture = .init()
        private var cancellables: Set<AnyCancellable> = []

        init() {
            screenCapture.$windows.compactMap {$0.first {$0.scRunningApplication.bundleIdentifier == "com.macblurayplayer.BlurayPlayer"}}.receive(on: DispatchQueue.main).sink { [weak self] window in
                self?.window = window
            }.store(in: &cancellables)
        }
    }

    var body: some Scene {
        WindowGroup() {
            SampleBufferView(sampleBufferDisplayLayer: captureSession.sampleBufferDisplayLayer)
                .onAppear {}
                .onDisappear {captureSession.stopRunning()}
        }.onChange(of: appState.window) { _ in
            if let window = appState.window {
                captureSession.startRunning(window: window.scWindow)
            }
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
