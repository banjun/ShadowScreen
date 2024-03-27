#if canImport(UIKit)
import UIKit
import SwiftUI

struct WindowSceneReader<Content: View>: View {
    var content: (UIWindowScene?) -> Content
    @State private var window: UIWindow?

    var body: some View {
        content(window?.windowScene)
            .overlay { WindowReadingView(parentWindow: $window).frame(width: 0, height: 0) }
    }

    struct WindowReadingView: UIViewRepresentable {
        @Binding var parentWindow: UIWindow?
        func makeUIView(context: Context) -> UIView { WindowReadingUIView(parentWindow: _parentWindow) }
        func updateUIView(_ uiView: UIView, context: Context) {}
    }

    class WindowReadingUIView: UIView {
        @Binding var parentWindow: UIWindow?
        init(parentWindow: Binding<UIWindow?>) {
            self._parentWindow = parentWindow
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { fatalError() }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard let window else {
                parentWindow = nil
                return
            }
            Task.detached { @MainActor in
                defer { self.parentWindow = window }
                let start = Date()
                let timeout: TimeInterval = 10
                while window.windowScene == nil, Date().timeIntervalSince(start) < timeout  {
                    try! await Task.sleep(for: .milliseconds(100))
                }
            }
        }
    }
}
#endif
