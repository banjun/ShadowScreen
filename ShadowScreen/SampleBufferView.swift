import Foundation
import AppKit
import AVKit
import SwiftUI

struct SampleBufferView: NSViewRepresentable {
    var sampleBufferDisplayLayer: AVSampleBufferDisplayLayer?

    func updateNSView(_ nsView: NSView, context: Context) {
        nsView.layer!.sublayers?.forEach {$0.removeFromSuperlayer()}
        if let layer = sampleBufferDisplayLayer {
            nsView.layer!.addSublayer(layer)
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
