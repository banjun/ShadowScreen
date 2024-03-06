import Foundation

actor OutputStreamActor {
    let stream: OutputStream
    init(stream: OutputStream) {
        self.stream = stream
        stream.open()
        Task {
            try await run()
        }
    }

    private var queue: [Data] = []
    private var processing: Data? // workaround for actor reentrancy
    func enqueue(_ data: Data) {
        queue.append(data)
    }

    private func run() async throws {
        func ensureAvailable() async throws -> Data {
            while true {
                try Task.checkCancellation()
                if stream.hasSpaceAvailable, processing == nil, !queue.isEmpty {
                    return queue.remove(at: 0)
                }
                try await Task.sleep(for: .milliseconds(10))
            }
        }
        func ensureAvailable2() async throws {
            while true {
                try Task.checkCancellation()
                if stream.hasSpaceAvailable {
                    return
                }
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        while true {
            let data = try await ensureAvailable()
            self.processing = data

            // data size
            guard (Data(uint32NetworkByteOrder: UInt32(data.count)).withUnsafeBytes { stream.write($0.baseAddress!, maxLength: 4) }) == 4 else {
                NSLog("%@", "error writing peer stream, streamError = \(String(describing: stream.streamError))")
                throw stream.streamError ?? NSError()
            }

            // data body
            var remaining = data.count
            while remaining > 0 {
                try await ensureAvailable2()
                try data.withUnsafeBytes {
                    let p = $0.baseAddress!.advanced(by: data.count - remaining).assumingMemoryBound(to: UInt8.self)
                    let sent = stream.write(p, maxLength: remaining)
                    if sent <= 0 {
                        NSLog("%@", "error writing peer stream: remaining = \(remaining), sent = \(sent), streamError = \(String(describing: stream.streamError))")
                        throw stream.streamError!
                    }
                    remaining -= sent
                    NSLog("%@", "sent \(sent) bytes, remaining = \(remaining) bytes")
                }
            }
            processing = nil
        }
    }
}

enum ATOM {
    static func send(stream: OutputStream, data: Data) async throws {
        func ensureAvailable() async throws {
            while true {
                try Task.checkCancellation()
                if stream.hasSpaceAvailable {
                    return
                }
                try await Task.sleep(for: .milliseconds(10))
            }
        }
        try await ensureAvailable()

        // data size
        guard (Data(uint32NetworkByteOrder: UInt32(data.count)).withUnsafeBytes { stream.write($0.baseAddress!, maxLength: 4) }) == 4 else {
            NSLog("%@", "error writing peer stream, streamError = \(String(describing: stream.streamError))")
            throw stream.streamError ?? NSError()
        }

        // data body
        var remaining = data.count
        while remaining > 0 {
            try await ensureAvailable()
            try data.withUnsafeBytes {
                let p = $0.baseAddress!.advanced(by: data.count - remaining).assumingMemoryBound(to: UInt8.self)
                let sent = stream.write(p, maxLength: remaining)
                if sent <= 0 {
                    NSLog("%@", "error writing peer stream: remaining = \(remaining), sent = \(sent), streamError = \(String(describing: stream.streamError))")
                    throw stream.streamError!
                }
                remaining -= sent
                NSLog("%@", "sent \(sent) bytes, remaining = \(remaining) bytes")
            }
        }
    }

    static func parse(stream: InputStream) -> AsyncStream<Data> {
        @Sendable func ensureAvailable() async throws {
            while true {
                try Task.checkCancellation()
                if stream.hasBytesAvailable {
                    return
                }
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        return .init { continuation in
            Task.detached {
                do {
                    var buffer = Data(count: 1_000_000)
                    while true {
                        try await ensureAvailable()

                        // data size
                        buffer.withUnsafeMutableBytes {
                            stream.read($0.baseAddress!.assumingMemoryBound(to: UInt8.self), maxLength: 4)
                        }
                        let size = UInt32(dataNetworkByteOrder: buffer)!

                        // data body
                        var remaining = Int(size)
                        while remaining > 0 {
                            try await ensureAvailable()
                            let read = buffer.withUnsafeMutableBytes {
                                stream.read($0.baseAddress!.advanced(by: Int(size) - remaining).assumingMemoryBound(to: UInt8.self), maxLength: remaining)
                            }
                            if read > 0 {
                                remaining -= read
                            } else {
                                NSLog("%@", "stream.read error = \(String(describing: stream.streamError))")
                            }
                        }

                        continuation.yield(Data(buffer[0..<(size)]))
                    }
                } catch {
                    NSLog("%@", "error = \(error)")
                }
            }
        }
    }
}
