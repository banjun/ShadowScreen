import SwiftUI
import AVFoundation
import CoreImage
import Combine
import CryptoKit

struct HEVC {
    var videoParameterSetSize: UInt32
    var videoParameterSet: Data
    var sequenceParameterSetSize: UInt32
    var sequenceParameterSet: Data
    var pictureParameterSetSize: UInt32
    var pictureParameterSet: Data
    var data: Data
}
extension Data {
    init(hevc: HEVC) {
        self.init(
            Data([
                UInt8((hevc.videoParameterSetSize >> 24) & 0xff),
                UInt8((hevc.videoParameterSetSize >> 16) & 0xff),
                UInt8((hevc.videoParameterSetSize >> 8) & 0xff),
                UInt8((hevc.videoParameterSetSize >> 0) & 0xff)])
            + hevc.videoParameterSet
            + Data([
                UInt8((hevc.sequenceParameterSetSize >> 24) & 0xff),
                UInt8((hevc.sequenceParameterSetSize >> 16) & 0xff),
                UInt8((hevc.sequenceParameterSetSize >> 8) & 0xff),
                UInt8((hevc.sequenceParameterSetSize >> 0) & 0xff)])
            + hevc.sequenceParameterSet
            + Data([
                UInt8((hevc.pictureParameterSetSize >> 24) & 0xff),
                UInt8((hevc.pictureParameterSetSize >> 16) & 0xff),
                UInt8((hevc.pictureParameterSetSize >> 8) & 0xff),
                UInt8((hevc.pictureParameterSetSize >> 0) & 0xff)])
            + hevc.pictureParameterSet
            + hevc.data)
    }
}
extension HEVC {
    init(data: Data) {
        let videoParameterSetSize: UInt32 =
        (UInt32(data[0]) << 24)
        + (UInt32(data[1]) << 16)
        + (UInt32(data[2]) << 8)
        + UInt32(data[3])
        let sequenceParameterSetSize: UInt32 =
        (UInt32(data[4 + Int(videoParameterSetSize)]) << 24)
        + (UInt32(data[4 + Int(videoParameterSetSize) + 1]) << 16)
        + (UInt32(data[4 + Int(videoParameterSetSize) + 2]) << 8)
        + UInt32(data[4 + Int(videoParameterSetSize) + 3])
        let pictureParameterSetSize: UInt32 =
        (UInt32(data[4 + Int(videoParameterSetSize) + 4 + Int(sequenceParameterSetSize)]) << 24)
        + (UInt32(data[4 + Int(videoParameterSetSize) + 4 + Int(sequenceParameterSetSize) + 1]) << 16)
        + (UInt32(data[4 + Int(videoParameterSetSize) + 4 + Int(sequenceParameterSetSize) + 2]) << 8)
        + UInt32(data[4 + Int(videoParameterSetSize) + 4 + Int(sequenceParameterSetSize) + 3])

        self.init(
            videoParameterSetSize: videoParameterSetSize,
            videoParameterSet: Data(data[4..<(4 + videoParameterSetSize)]),
            sequenceParameterSetSize: sequenceParameterSetSize,
            sequenceParameterSet: Data(data[(4 + videoParameterSetSize + 4)..<(4 + videoParameterSetSize + 4 + sequenceParameterSetSize)]),
            pictureParameterSetSize: pictureParameterSetSize,
            pictureParameterSet: Data(data[(4 + videoParameterSetSize + 4 + sequenceParameterSetSize + 4)..<(4 + videoParameterSetSize + 4 + sequenceParameterSetSize + 4 + pictureParameterSetSize)]),
            data: Data(data[(4 + videoParameterSetSize + 4 + sequenceParameterSetSize + 4 + pictureParameterSetSize)...]))
    }
}
extension CMSampleBuffer {
    static func decode(hevc: HEVC, firstFrameTimestamp: TimeInterval) -> CMSampleBuffer? {
        var formatDescription: CMFormatDescription?
        hevc.videoParameterSet.withUnsafeBytes { vps in
            hevc.sequenceParameterSet.withUnsafeBytes { sps in
                hevc.pictureParameterSet.withUnsafeBytes { pps in
                    var parameterSetPointers: [UnsafePointer<UInt8>] = [
                        vps.baseAddress!.assumingMemoryBound(to: UInt8.self),
                        sps.baseAddress!.assumingMemoryBound(to: UInt8.self),
                        pps.baseAddress!.assumingMemoryBound(to: UInt8.self)]
                    var parameterSetSizes: [Int] = [vps.count, sps.count, pps.count]
                    let nalUnitHeaderLength: Int32 = 4 // 1,2,4 ?

                    CMVideoFormatDescriptionCreateFromHEVCParameterSets(allocator: nil, parameterSetCount: parameterSetSizes.count, parameterSetPointers: &parameterSetPointers, parameterSetSizes: &parameterSetSizes, nalUnitHeaderLength: nalUnitHeaderLength, extensions: nil, formatDescriptionOut: &formatDescription)
                }
            }
        }

        let dataBuffer: CMBlockBuffer = try! CMBlockBuffer(length: hevc.data.count)
        _ = hevc.data.withUnsafeBytes {
            CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: dataBuffer, offsetIntoDestination: 0, dataLength: hevc.data.count)
        }
        let now = NSDate().timeIntervalSince1970
        var timing: CMSampleTimingInfo = CMSampleTimingInfo(duration: CMTime(seconds: 0.1, preferredTimescale: 600), presentationTimeStamp: CMTime(seconds: now - firstFrameTimestamp, preferredTimescale: 600), decodeTimeStamp: .invalid)
        var decoded: CMSampleBuffer?
        CMSampleBufferCreateReady(allocator: nil, dataBuffer: dataBuffer, formatDescription: formatDescription, sampleCount: 1, sampleTimingEntryCount: 1, sampleTimingArray: &timing, sampleSizeEntryCount: 1, sampleSizeArray: [1], sampleBufferOut: &decoded)
        return decoded
    }
}

#if os(macOS)
@main
struct ShadowScreenApp: App {
    @StateObject var appState: State = .init()
    @StateObject var captureSession = CaptureSession()

    class State: ObservableObject {
        @Published private(set) var window: ScreenCapture.Window?
        private let screenCapture: ScreenCapture = .init()
        private var cancellables: Set<AnyCancellable> = []
        private var captureSessionCancellables: Set<AnyCancellable> = []
        let peerBrowser = PeerBrowser()
        private(set) var runtimePeer: RuntimePeer?

        init() {
            screenCapture.$windows.compactMap {$0.first {$0.scRunningApplication.bundleIdentifier == "developer.apple.wwdc-Release"}}.receive(on: DispatchQueue.main).sink { [weak self] window in
                self?.window = window
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
                do {
                    let digest = SHA256.hash(data: imageBufferData).prefix(6)
                    NSLog("%@", "🍓 sending \(imageBufferData.count) bytes (digest: \(digest)) to the peer")
                    try runtimePeer.session.send(imageBufferData, toPeers: [runtimePeer.peerID], with: .unreliable)
                } catch {
                    NSLog("%@", "🍓 error during runtimePeer.session.send: \(String(describing: error))")
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
        private var firstFrameTimestamp: Double?

        init() {
            Task {
                await peerAdvertiser.start()

                await peerAdvertiser.receivedData
//                    .throttle(for: 1, scheduler: DispatchQueue.main, latest: true)
                    .sink { [weak self] imageBufferData in
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

        func receive(imageBufferData: Data) {
            let hevc = HEVC(data: imageBufferData)
            if firstFrameTimestamp == nil {
                firstFrameTimestamp = NSDate().timeIntervalSince1970
            }
            let sampleBuffer = CMSampleBuffer.decode(hevc: hevc, firstFrameTimestamp: firstFrameTimestamp!)
            NSLog("%@", "decoded = \(sampleBuffer)")
            guard let sampleBuffer else { return }
            receive(sampleBuffer: sampleBuffer)

            return

//
//            let digest = SHA256.hash(data: imageBufferData).prefix(6)
//            print("digest = \(digest)")
//
//            var imageBufferData = imageBufferData
//            imageBufferData.withUnsafeMutableBytes { p in
//                var imageBuffer: CVPixelBuffer?
//                // NOTE: CVPixelBufferCreateWithPlanarBytes cannot create IOSurface backed buffer. AVSampleBufferDisplayLayer implicitly requires a IOSurface backed CVPixelBuffer backed CVSampleBuffer.
//                CVPixelBufferCreate(kCFAllocatorDefault, 1920, 1080, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &imageBuffer)
//                guard let imageBuffer else { return }
//
//                CVPixelBufferLockBaseAddress(imageBuffer, .readOnly)
//                defer { CVPixelBufferUnlockBaseAddress(imageBuffer, .readOnly) }
//
//                let planeY = CVPixelBufferGetBaseAddressOfPlane(imageBuffer, 0)
//                let planeUV = CVPixelBufferGetBaseAddressOfPlane(imageBuffer, 1)
////                print(CVPixelBufferGetPlaneCount(imageBuffer!))
////                print(planeY)
////                print(planeUV)
//
//                let magicAlignment = 7168 // ?? observed in original image buffer
//                let planeBaseAddresses: [UnsafeMutableRawPointer?] = [p.baseAddress, UnsafeMutableRawPointer(p.assumingMemoryBound(to: UInt8.self).baseAddress!.advanced(by: 1920 * 1080 + magicAlignment))]
//                memcpy(planeY, planeBaseAddresses[0], 1920 * 1080)
//                memcpy(planeUV, planeBaseAddresses[1], 1920 / 2 * 1080 / 2 * 2)
//
//                do {
//                    let format = try CMVideoFormatDescription(imageBuffer: imageBuffer)
//                    let now = Date().timeIntervalSince1970// CFAbsoluteTime()
//                    if firstFrameTimestamp == nil {
//                        firstFrameTimestamp = now
//                    }
//                    let timing = CMSampleTimingInfo(duration: .init(seconds: 0.01, preferredTimescale: 600), presentationTimeStamp: .init(seconds: now - firstFrameTimestamp!, preferredTimescale: 600), decodeTimeStamp: .invalid)
//                    let sampleBuffer = try CMSampleBuffer.init(imageBuffer: imageBuffer, formatDescription: format, sampleTiming: timing)
//                    let attachments: CFArray = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: true)!
//                    let firstAttachments = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
//                    CFDictionarySetValue(firstAttachments, Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(), Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
//                    receive(sampleBuffer: sampleBuffer)
//                } catch {
//                    NSLog("%@", "🍓 error converting image buffer to sample buffer = \(error)")
//                }
//            }
        }
        func receive(sampleBuffer: CMSampleBuffer) {
            if sampleBufferDisplayLayer == nil {
                connect()
            }
            sampleBufferDisplayLayer!.enqueue(sampleBuffer)
        }

        func disconnect() {
            sampleBufferDisplayLayer = nil
            firstFrameTimestamp = nil
        }
    }

    var body: some Scene {
        WindowGroup {
            if let layer = model.sampleBufferDisplayLayer {
                SampleBufferView(sampleBufferDisplayLayer: layer)
            } else {
                Text("sampleBufferDisplayLayer = nil")
                    .font(.largeTitle)
                    .padding()
            }
        }
    }
}
#endif
