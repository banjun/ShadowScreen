import Foundation
import CoreMedia

extension Data {
    init?(sampleBuffer420v sampleBuffer: CMSampleBuffer) {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }
        guard CVPixelBufferLockBaseAddress(imageBuffer, .readOnly) == kCVReturnSuccess else { return nil }
        guard let base = CVPixelBufferGetBaseAddress(imageBuffer) else { return nil }
        defer { CVPixelBufferUnlockBaseAddress(imageBuffer, .readOnly) }
        let size = CVPixelBufferGetDataSize(imageBuffer)
        let buffer = UnsafeBufferPointer(start: base.assumingMemoryBound(to: UInt8.self), count: size)
        self.init(buffer: buffer)
    }
}

extension CMSampleBuffer {
    static func decode(_420v imageBufferData: Data, firstFrameTimestamp: TimeInterval, now: TimeInterval = Date().timeIntervalSince1970) -> CMSampleBuffer? {
        var imageBufferData = imageBufferData
        return imageBufferData.withUnsafeMutableBytes { p in
            var imageBuffer: CVPixelBuffer?
            // NOTE: CVPixelBufferCreateWithPlanarBytes cannot create IOSurface backed buffer. AVSampleBufferDisplayLayer implicitly requires a IOSurface backed CVPixelBuffer backed CVSampleBuffer.
            CVPixelBufferCreate(kCFAllocatorDefault, 1920, 1080, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &imageBuffer)
            guard let imageBuffer else { return nil }

            CVPixelBufferLockBaseAddress(imageBuffer, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(imageBuffer, .readOnly) }

            let planeY = CVPixelBufferGetBaseAddressOfPlane(imageBuffer, 0)
            let planeUV = CVPixelBufferGetBaseAddressOfPlane(imageBuffer, 1)
            //                print(CVPixelBufferGetPlaneCount(imageBuffer!))
            //                print(planeY)
            //                print(planeUV)

            let magicAlignment = 7168 // ?? observed in original image buffer
            let planeBaseAddresses: [UnsafeMutableRawPointer?] = [p.baseAddress, UnsafeMutableRawPointer(p.assumingMemoryBound(to: UInt8.self).baseAddress!.advanced(by: 1920 * 1080 + magicAlignment))]
            memcpy(planeY, planeBaseAddresses[0], 1920 * 1080)
            memcpy(planeUV, planeBaseAddresses[1], 1920 / 2 * 1080 / 2 * 2)

            do {
                let format = try CMVideoFormatDescription(imageBuffer: imageBuffer)
                let timing = CMSampleTimingInfo(duration: .init(seconds: 0.01, preferredTimescale: 600), presentationTimeStamp: .init(seconds: now - firstFrameTimestamp, preferredTimescale: 600), decodeTimeStamp: .invalid)
                let sampleBuffer = try CMSampleBuffer.init(imageBuffer: imageBuffer, formatDescription: format, sampleTiming: timing)
                let attachments: CFArray = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: true)!
                let firstAttachments = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
                CFDictionarySetValue(firstAttachments, Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(), Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
                return sampleBuffer
            } catch {
                NSLog("%@", "🍓 error converting image buffer to sample buffer = \(error)")
                return nil
            }
        }
    }
}
