import AVFoundation
import CoreGraphics
import IOSurface

class CaptureSession: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private var session: AVCaptureSession? {
        didSet {
            previewLayer = session.map {AVCaptureVideoPreviewLayer(session: $0)}
        }
    }
    @Published private(set) var previewLayer: AVCaptureVideoPreviewLayer?
    @Published private(set) var presentedImage: CGImage?

    override init() {
        super.init()
        NSLog("%@", "CGRequestScreenCaptureAccess() = \(CGRequestScreenCaptureAccess())")
    }

    func startRunning() {
        var activeDisplayIDsBase: CGDirectDisplayID = 0
        var activeDisplayCount: UInt32 = 0
        CGGetActiveDisplayList(0, &activeDisplayIDsBase, &activeDisplayCount)
        let activeDisplayIDs = [CGDirectDisplayID](UnsafeBufferPointer(start: &activeDisplayIDsBase, count: Int(activeDisplayCount)))
        NSLog("%@", "activeDisplayIDs = \(activeDisplayIDs)")

        let session = AVCaptureSession()

        let input = AVCaptureScreenInput(displayID: activeDisplayIDs.first!)!
        input.minFrameDuration = CMTime(seconds: 1 / 120, preferredTimescale: 10000)
        input.capturesMouseClicks = false
        input.capturesCursor = false
        session.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.setSampleBufferDelegate(self, queue: DispatchQueue(label: String(describing: self), qos: .userInteractive))
        output.videoSettings = nil
        output.alwaysDiscardsLateVideoFrames = true
        session.addOutput(output)

        self.session = session
        session.startRunning()
    }

    func stopRunning() {
        session?.stopRunning()
    }

    private var bufferOrigin: CMTime?
    private let captureScale = 0.5 // performance may be limited by combination with scale & fps
    private let bufferFPS: Double = 60 // performance may be limited by combination with scale & fps
    private var bufferDelaySeconds = 1.8 // currently hardcoded to sync with AirPlay
    private var buffer: [(CMTime, CGImage)?] = .init(repeating: nil, count: 200)
    private var bufferWriteIndex: Int = 0
    private let ciContext = CIContext()

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let imageBuffer = sampleBuffer.imageBuffer else { return }
        let timestamp = sampleBuffer.presentationTimeStamp
        let bufferOrigin = bufferOrigin ?? timestamp
        self.bufferOrigin = bufferOrigin

        let bufferDelayFrames = Int(self.bufferDelaySeconds * Double(self.bufferFPS))
        let previousBufferWriteIndex = self.bufferWriteIndex
        let nextBufferWriteIndex = Int((timestamp.seconds - bufferOrigin.seconds) * self.bufferFPS) % bufferDelayFrames
        guard previousBufferWriteIndex != nextBufferWriteIndex else {
            //            NSLog("%@", "index same \(nextBufferWriteIndex), skipped")
            return
        }

        autoreleasepool {
            let ciImage = CIImage(cvImageBuffer: imageBuffer)
                .transformed(by: CGAffineTransform(scaleX: captureScale, y: captureScale))
            let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent)

            let item = cgImage.map {(timestamp, $0)}
            let skippedFrameIndices = ((previousBufferWriteIndex + 1)...(nextBufferWriteIndex + ((previousBufferWriteIndex + 1) <= nextBufferWriteIndex ? 0 : bufferDelayFrames))).map {$0 % bufferDelayFrames}
            skippedFrameIndices.forEach {self.buffer[$0] = item}
            if skippedFrameIndices.count - 1 > 0 {
                NSLog("%@", "index = \(previousBufferWriteIndex) .. \(nextBufferWriteIndex), skipped \(skippedFrameIndices.count - 1) frames")
            }

            self.bufferWriteIndex = nextBufferWriteIndex

            let delayedFrameIndex = (nextBufferWriteIndex + 1) % bufferDelayFrames
            let delayedFrame = self.buffer[delayedFrameIndex]

            if let delayedFrame = delayedFrame {
                DispatchQueue.main.async {
                    self.presentedImage = delayedFrame.1

                    let actualDelay = timestamp.seconds - delayedFrame.0.seconds
                    if abs(actualDelay - self.bufferDelaySeconds) > 0.1 {
                        NSLog("%@", "delay error > 0.1, expected = \(self.bufferDelaySeconds), actual = \(actualDelay)")
                    }
                }
            }
        }
    }
}
