import SwiftUI
import AVFoundation
import CoreImage
import Combine

#if os(macOS)
@main
struct ShadowScreenApp: App {
    @StateObject var appState: State = .init()
    @StateObject var captureSession = CaptureSession()

    class State: ObservableObject {
        @Published private(set) var window: ScreenCapture.Window?
        @Published private(set) var display: ScreenCapture.Display?
        private let screenCapture: ScreenCapture = .init()
        private var cancellables: Set<AnyCancellable> = []
        private var captureSessionCancellables: Set<AnyCancellable> = []
        let peerBrowser = PeerBrowser()
        private(set) var runtimePeer: RuntimePeer? {
            didSet {
                runtimePeerOutStreamActor = runtimePeer.flatMap { try? $0.session.startStream(withName: "HEVC", toPeer: $0.peerID) }.map {
                    OutputStreamActor(stream: $0)
                }
            }
        }
        private var runtimePeerOutStreamActor: OutputStreamActor?

        init() {
            screenCapture.$displays.compactMap {$0.last}.receive(on: DispatchQueue.main).sink { [weak self] in
                self?.display = $0
            }.store(in: &cancellables)

            Task {
                await peerBrowser.$runtimePeers.receive(on: DispatchQueue.main).sink { [weak self] runtimePeers in
                    guard let self else { return }
                    let runtimePeer = runtimePeers.first
                    NSLog("%@", "🍓 TODO: support multiple peers: \(runtimePeers.count) peers connected. currently using only first peer \(String(describing: runtimePeer))")
                    self.runtimePeer = runtimePeer
                }.store(in: &cancellables)

                await peerBrowser.start()
            }
        }

        func adoptCaptureSessionToRuntimePeer(captureSession: CaptureSession) {
            captureSession.$latestImageBufferData.compactMap {$0}
            //                .throttle(for: 1, scheduler: DispatchQueue.main, latest: true)
                .sink { [weak self] imageBufferData in
                    guard let self else { return }
                    guard let runtimePeer else { return }
                    // NSLog("%@", "🍓 sending \(imageBufferData.count) bytes to the peer")
                    // unreliable transport can cause out of order delivery.
                    // HEVC depends on ordered frames and results in thus gray + diff screen on simulator or freeze on device
                    // TODO: use a stream transport
                    if let runtimePeerOutStreamActor {
                        Task {
                            await runtimePeerOutStreamActor.enqueue(imageBufferData)
                        }
                    } else {
                        do {
                            try runtimePeer.session.send(imageBufferData, toPeers: [runtimePeer.peerID], with: .reliable)
                        } catch {
                            NSLog("%@", "🍓 error during runtimePeer.session.send: \(String(describing: error))")
                        }
                    }
                }.store(in: &captureSessionCancellables)
        }

        func detachCaptureSessionFromRuntimePeer(captureSession: CaptureSession) {
            captureSessionCancellables.removeAll()
        }
    }

    var body: some Scene {
        WindowGroup() {
            SampleBufferView(sampleBufferDisplayLayer: captureSession.sampleBufferDisplayLayer)
                .onAppear {}
                .onDisappear {
                    captureSession.stopRunning()
                    appState.detachCaptureSessionFromRuntimePeer(captureSession: captureSession)
                }
            Divider()
            appState.peerBrowser.browserView
        }.onChange(of: appState.window) { _ in
            if let window = appState.window {
                captureSession.startRunning(window: window.scWindow)
                appState.adoptCaptureSessionToRuntimePeer(captureSession: captureSession)
            }
        }.onChange(of: appState.display) { _ in
            if let display = appState.display {
                captureSession.startRunning(display: display.scDisplay)
                appState.adoptCaptureSessionToRuntimePeer(captureSession: captureSession)
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
#elseif os(visionOS) || os(iOS)
@main
struct ShadowScreenApp: App {
    let model = Model()

    @Observable class Model {
        var sampleBufferDisplayLayer: AVSampleBufferDisplayLayer? = nil
        let peerAdvertiser = PeerAdvertiser() { _, _ in true }
        private var cancellables: Set<AnyCancellable> = []

        init() {
            Task {
                await peerAdvertiser.start()

                await peerAdvertiser.receivedData
//                    .throttle(for: 1, scheduler: DispatchQueue.main, latest: true)
                    .sink { [weak self] imageBufferData in
                        // NSLog("%@", "sink seq = \(HEVC(data: imageBufferData)?.dummySequenceNumber ?? 0) bytes")
                        self?.receive(imageBufferData: imageBufferData)
                    }.store(in: &cancellables)
            }
        }

        func startBrowsing() {
            // TODO: eventually call connect()
        }

        private func connect() {
            sampleBufferDisplayLayer = AVSampleBufferDisplayLayer()
        }

        private var previousDummySequenceNumber: UInt32 = 0
        func receive(imageBufferData: Data) {
            guard let hevc = HEVC(data: imageBufferData) else { return }
            if previousDummySequenceNumber + 1 != hevc.dummySequenceNumber {
                NSLog("%@", "frame drop detected: \(previousDummySequenceNumber) -> \(hevc.dummySequenceNumber)")
            }
            previousDummySequenceNumber = hevc.dummySequenceNumber
            let sampleBuffer = CMSampleBuffer.decode(hevc: hevc)
            // print("decoded = \(sampleBuffer)")
            guard let sampleBuffer else {
                NSLog("%@", "decode failed for \(imageBufferData.count) bytes")
                return
            }
            receive(sampleBuffer: sampleBuffer)
        }
        func receive(sampleBuffer: CMSampleBuffer) {
            if sampleBufferDisplayLayer == nil {
                connect()
            }
            sampleBufferDisplayLayer!.enqueue(sampleBuffer)
        }

        func disconnect() {
            sampleBufferDisplayLayer = nil
        }
    }

    var body: some Scene {
        WindowGroup {
            if let layer = model.sampleBufferDisplayLayer {
                SampleBufferView(sampleBufferDisplayLayer: layer)
                    .ornament(attachmentAnchor: .scene(.topLeading),
                              contentAlignment: .bottomTrailing) {
                        Button("Kill") { exit(1) }
                            .offset(z: -30)
                    }
            } else {
                Text("Connect from the companion Mac app")
                    .font(.largeTitle)
                    .padding()
                Text(model.peerAdvertiser.displayName)
                    .font(.title)
                    .padding()
            }
        }
    }
}
#endif
