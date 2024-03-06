import Foundation
import CoreMedia

struct HEVC {
    var dummySequenceNumber: UInt32
    var presentationTimeStamp: Double
    var nalUnitHeaderLength: UInt8
    var videoParameterSet: Data
    var sequenceParameterSet: Data
    var pictureParameterSet: Data
    var data: Data
}

extension Data {
    init(uint32NetworkByteOrder value: UInt32) {
        var bigEndian = value.bigEndian
        self.init(bytes: &bigEndian, count: 4)
    }

    init(doubleNetworkByteOrder value: Double) {
        var bigEndian = value.bitPattern.bigEndian
        self.init(bytes: &bigEndian, count: 8)
    }

    init(hevc: HEVC) {
        self.init(
            Data(uint32NetworkByteOrder: hevc.dummySequenceNumber)
            + Data(doubleNetworkByteOrder: hevc.presentationTimeStamp)
            + Data([hevc.nalUnitHeaderLength])
            + Data(uint32NetworkByteOrder: UInt32(hevc.videoParameterSet.count))
            + hevc.videoParameterSet
            + Data(uint32NetworkByteOrder: UInt32(hevc.sequenceParameterSet.count))
            + hevc.sequenceParameterSet
            + Data(uint32NetworkByteOrder: UInt32(hevc.pictureParameterSet.count))
            + hevc.pictureParameterSet
            + hevc.data)
    }
}
extension UInt32 {
    init?(dataNetworkByteOrder data: Data) {
        guard data.count >= 4 else { return nil }
        self.init(data.withUnsafeBytes {
            $0.baseAddress!.assumingMemoryBound(to: UInt32.self).pointee.bigEndian
        })
    }
}
extension Double {
    init?(dataNetworkByteOrder data: Data) {
        guard data.count >= 8 else { return nil }
        self.init(bitPattern: data.withUnsafeBytes {
            $0.baseAddress!.assumingMemoryBound(to: UInt64.self).pointee.bigEndian
        })
    }
}
extension HEVC {
    init?(data: Data) {
        var offset = 0

        let dummySequenceNumber = UInt32(dataNetworkByteOrder: data[offset...])!
        offset += 4

        let presentationTimeStamp = Double(dataNetworkByteOrder: data[offset...])!
        offset += 8

        let nalUnitHeaderLength: UInt8 = data[offset]
        offset += 1

        guard let videoParameterSetSize = UInt32(dataNetworkByteOrder: data[offset...]) else { return nil }
        let vpsOffset = offset + 4

        offset = vpsOffset + Int(videoParameterSetSize)
        guard let sequenceParameterSetSize = UInt32(dataNetworkByteOrder: data[offset...]) else { return nil }
        let spsOffset = offset + 4

        offset = spsOffset + Int(sequenceParameterSetSize)
        guard let pictureParameterSetSize = UInt32(dataNetworkByteOrder: data[offset...]) else { return nil }
        let ppsOffset = offset + 4

        offset = ppsOffset + Int(pictureParameterSetSize)
        self.init(
            dummySequenceNumber: dummySequenceNumber,
            presentationTimeStamp: presentationTimeStamp,
            nalUnitHeaderLength: nalUnitHeaderLength,
            videoParameterSet: data[vpsOffset..<(vpsOffset + Int(videoParameterSetSize))],
            sequenceParameterSet: data[spsOffset..<(spsOffset + Int(sequenceParameterSetSize))],
            pictureParameterSet: data[ppsOffset..<(ppsOffset + Int(pictureParameterSetSize))],
            data: data[offset...])
    }

    /// encodedFrameSampleBuffer should be produced by
    /// VTCompressionSessionEncodeFrame(...)
    init?(encodedFrameSampleBuffer sampleBuffer: CMSampleBuffer, dummySequenceNumber: UInt32) {
        var nalUnitHeaderLength: Int32 = 0
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) else { return nil }
        func parameterSet(at index: Int) -> Data? {
            var parameterSetPointer: UnsafePointer<UInt8>?
            var parameterSetSize: Int = 0
            var parameterSetCount: Int = 0
            CMVideoFormatDescriptionGetHEVCParameterSetAtIndex(formatDescription, parameterSetIndex: index, parameterSetPointerOut: &parameterSetPointer, parameterSetSizeOut: &parameterSetSize, parameterSetCountOut: &parameterSetCount, nalUnitHeaderLengthOut: &nalUnitHeaderLength)
            return Data(buffer: UnsafeBufferPointer(start: parameterSetPointer, count: parameterSetSize))
       }
        guard let videoParameterSet = parameterSet(at: 0) else { return nil }
        guard let sequenceParameterSet = parameterSet(at: 1) else { return nil }
        guard let pictureParameterSet = parameterSet(at: 2) else { return nil }
        guard let data = try? sampleBuffer.dataBuffer?.dataBytes() else { return nil }
        let presentationTimeStamp = sampleBuffer.presentationTimeStamp.seconds

//            let attachmentsArray = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as Array?
//            let dependsOnOthers = attachmentsArray?.compactMap {$0 as? [String: Any]}.map {$0?["DependsOnOthers"] as? Bool}
//            NSLog("%@", "DependsOnOthers = \(dependsOnOthers)")
//            NSLog("%@", "sampleBuffer.numSamples = \(sampleBuffer.numSamples)")
        self.init(dummySequenceNumber: dummySequenceNumber, presentationTimeStamp: presentationTimeStamp, nalUnitHeaderLength: UInt8(nalUnitHeaderLength), videoParameterSet: videoParameterSet, sequenceParameterSet: sequenceParameterSet, pictureParameterSet: pictureParameterSet, data: data)
    }
}
extension CMSampleBuffer {
    static func decode(hevc: HEVC) -> CMSampleBuffer? {
        var formatDescription: CMFormatDescription?
        hevc.videoParameterSet.withUnsafeBytes { vps in
            hevc.sequenceParameterSet.withUnsafeBytes { sps in
                hevc.pictureParameterSet.withUnsafeBytes { pps in
                    var parameterSetPointers: [UnsafePointer<UInt8>] = [
                        vps.baseAddress!.assumingMemoryBound(to: UInt8.self),
                        sps.baseAddress!.assumingMemoryBound(to: UInt8.self),
                        pps.baseAddress!.assumingMemoryBound(to: UInt8.self)]
                    var parameterSetSizes: [Int] = [vps.count, sps.count, pps.count]
                    let nalUnitHeaderLength: Int32 = .init(hevc.nalUnitHeaderLength)

                    CMVideoFormatDescriptionCreateFromHEVCParameterSets(allocator: nil, parameterSetCount: parameterSetSizes.count, parameterSetPointers: &parameterSetPointers, parameterSetSizes: &parameterSetSizes, nalUnitHeaderLength: nalUnitHeaderLength, extensions: nil, formatDescriptionOut: &formatDescription)
                }
            }
        }

        let dataBuffer: CMBlockBuffer = try! CMBlockBuffer(length: hevc.data.count)
        _ = hevc.data.withUnsafeBytes {
            CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: dataBuffer, offsetIntoDestination: 0, dataLength: hevc.data.count)
        }
        var timing: CMSampleTimingInfo = CMSampleTimingInfo(duration: CMTime(seconds: 0.1, preferredTimescale: 600), presentationTimeStamp: CMTime(seconds: hevc.presentationTimeStamp, preferredTimescale: 600), decodeTimeStamp: .invalid)
        var decoded: CMSampleBuffer?
        CMSampleBufferCreateReady(allocator: nil, dataBuffer: dataBuffer, formatDescription: formatDescription, sampleCount: 1, sampleTimingEntryCount: 1, sampleTimingArray: &timing, sampleSizeEntryCount: 1, sampleSizeArray: [1], sampleBufferOut: &decoded)

//        if let decoded {
//            let attachments: CFArray = CMSampleBufferGetSampleAttachmentsArray(decoded, createIfNecessary: true)!
//            let firstAttachments = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
//            CFDictionarySetValue(firstAttachments, Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(), Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
//        }

        return decoded
    }
}
