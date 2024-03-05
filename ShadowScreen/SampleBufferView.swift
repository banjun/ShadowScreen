import Foundation
import AVKit
import SwiftUI

#if canImport(AppKit)
import AppKit

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

#elseif canImport(UIKit)
import UIKit

struct SampleBufferView: UIViewRepresentable {
    var sampleBufferDisplayLayer: AVSampleBufferDisplayLayer?

    func updateUIView(_ uiView: UIView, context: Context) {
        uiView.layer.sublayers?.forEach {$0.removeFromSuperlayer()}
        if let layer = sampleBufferDisplayLayer {
            uiView.layer.addSublayer(layer)
        }
        context.coordinator.uiView = uiView
    }
    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        updateUIView(v, context: context)
        return v
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {
        var uiView: UIView? {
            didSet {
                if let uiView {
                    uiView.layer.sublayers?.forEach {$0.frame = uiView.bounds}
                }
                observation = uiView?.observe(\.frame) { uiView, _ in
                    uiView.layer.sublayers?.forEach {$0.frame = uiView.bounds}
                }
            }
        }
        private var observation: NSKeyValueObservation?
    }
}

#endif
