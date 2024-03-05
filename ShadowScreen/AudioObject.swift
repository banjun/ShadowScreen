#if os(macOS)
import Foundation
import AVKit

struct AudioObject {
    var id: AudioObjectID
    var uid: String?
    var name: String?
    var deviceLatency: Int32 // frames
    var sampleRate: Float64
    var streams: [Stream]
    var totalLatency: Double { Double((streams.map {$0.latency}.max() ?? 0) + deviceLatency) / sampleRate }
    struct Stream {
        var id: AudioStreamID
        var latency: Int32 // frames
    }

    static func collect() -> [AudioObject] {
        var outputDevicesAddress = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        var outputDevicesCount: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &outputDevicesAddress, 0, nil, &outputDevicesCount) == noErr else { return [] }

        var ids: [AudioObjectID] = .init(repeating: 0, count: Int(outputDevicesCount) / MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &outputDevicesAddress, 0, nil, &outputDevicesCount, &ids) == noErr else { return [] }

        return ids.map {
            var uidAddress = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceUID, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            var uidSize: UInt32 = UInt32(MemoryLayout<CFString?>.size)
            var uid: CFString?
            AudioObjectGetPropertyData($0, &uidAddress, 0, nil, &uidSize, &uid)

            var nameAddress = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceNameCFString, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            var nameSize: UInt32 = UInt32(MemoryLayout<CFString?>.size)
            var name: CFString?
            AudioObjectGetPropertyData($0, &nameAddress, 0, nil, &nameSize, &name)

            var deviceLatencyAddress = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyLatency, mScope: kAudioObjectPropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
            var deviceLatencySize: UInt32 = UInt32(MemoryLayout<Int32>.size)
            var deviceLatency: Int32 = 0
            AudioObjectGetPropertyData($0, &deviceLatencyAddress, 0, nil, &deviceLatencySize, &deviceLatency)

            var sampleRateAddress = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyNominalSampleRate, mScope: kAudioObjectPropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
            var sampleRateSize: UInt32 = UInt32(MemoryLayout<Float64>.size)
            var sampleRate: Float64 = 0
            AudioObjectGetPropertyData($0, &sampleRateAddress, 0, nil, &sampleRateSize, &sampleRate)

            var streamsAddress = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams, mScope: kAudioObjectPropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
            var streamsCount: UInt32 = 0
            AudioObjectGetPropertyDataSize($0, &streamsAddress, 0, nil, &streamsCount)
            var streamIDs: [AudioStreamID] = .init(repeating: 0, count: Int(streamsCount))
            AudioObjectGetPropertyData($0, &streamsAddress, 0, nil, &streamsCount, &streamIDs)
            let streams = streamIDs.map {
                var latencyAddress = AudioObjectPropertyAddress(mSelector: kAudioStreamPropertyLatency, mScope: kAudioObjectPropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
                var latencySize: UInt32 = UInt32(MemoryLayout<Int32>.size)
                var latency: Int32 = 0
                AudioObjectGetPropertyData($0, &latencyAddress, 0, nil, &latencySize, &latency)

                return Stream(id: $0, latency: latency)
            }

            return AudioObject(id: $0, uid: uid as? String, name: name as? String, deviceLatency: deviceLatency, sampleRate: sampleRate, streams: streams)
        }
    }
}
#endif
