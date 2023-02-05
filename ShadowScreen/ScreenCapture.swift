import Foundation
import AppKit
import ScreenCaptureKit

final class ScreenCapture: ObservableObject {
    @Published private(set) var windows: [Window] = []
    @Published private(set) var displays: [SCDisplay] = []

    struct Window: Equatable {
        var scWindow: SCWindow
        var scRunningApplication: SCRunningApplication
        var nsRunningApplication: NSRunningApplication
    }

    init() {
        reload()
    }

    func reload() {
        SCShareableContent.getExcludingDesktopWindows(true, onScreenWindowsOnly: true) { content, error in
            let nsRunningApplications = NSWorkspace.shared.runningApplications
            self.windows = (content?.windows ?? []).compactMap { window -> Window? in
                guard let scApp = window.owningApplication,
                      let nsApp = (nsRunningApplications.first {$0.bundleIdentifier == scApp.bundleIdentifier}) else { return nil }
                return Window(scWindow: window, scRunningApplication: scApp, nsRunningApplication: nsApp)
            }.sorted { (a: Window, b: Window) in
                guard a.nsRunningApplication.activationPolicy.rawValue == b.nsRunningApplication.activationPolicy.rawValue else {
                    return a.nsRunningApplication.activationPolicy.rawValue < b.nsRunningApplication.activationPolicy.rawValue
                }
                switch a.scRunningApplication.applicationName.localizedCaseInsensitiveCompare(b.scRunningApplication.applicationName) {
                case .orderedAscending: return true
                case .orderedDescending: return false
                case .orderedSame: return a.scWindow.title ?? "" < b.scWindow.title ?? ""
                }
            }
            self.displays = content?.displays ?? []
        }
    }
}
