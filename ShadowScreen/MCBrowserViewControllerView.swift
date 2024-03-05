import SwiftUI
import MultipeerConnectivity

struct MCBrowserViewControllerView {
    var browser: MCNearbyServiceBrowser
    var session: MCSession

    func makeNSViewController(context: Context) -> MCBrowserViewController {
        let vc = MCBrowserViewController(browser: browser, session: session)
        vc.delegate = context.coordinator
        vc.maximumNumberOfPeers = 1
        return vc
    }

    func makeUIViewController(context: Context) -> MCBrowserViewController {
        makeNSViewController(context: context)
    }

    func makeCoordinator() -> Coordinator {
        .init()
    }

    func updateNSViewController(_ vc: MCBrowserViewController, context: Context) {
        vc.delegate = context.coordinator
    }

    func updateUIViewController(_ vc: MCBrowserViewController, context: Context) {
        vc.delegate = context.coordinator
    }

    final class Coordinator: NSObject, MCBrowserViewControllerDelegate {
        func browserViewControllerDidFinish(_ browserViewController: MCBrowserViewController) {
            NSLog("%@", "🍓 \(#function) Done pressed. ignored. continue searching...")
        }
        func browserViewControllerWasCancelled(_ browserViewController: MCBrowserViewController) {
            NSLog("%@", "🍓 \(#function) Cancel pressed. ignored. continue searching...")
        }

        func browserViewController(_ browserViewController: MCBrowserViewController, shouldPresentNearbyPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) -> Bool {
            NSLog("%@", "🍓 \(#function) peerID = \(peerID), info = \(String(describing: info))")
            guard info == MultipeerConnectivityConstants.serverDiscoveryInfo else {
                NSLog("%@", "🍓 \(#function) ignore peer \(peerID) as it's not a server")
                return false
            }
            return true
        }
    }
}

#if canImport(AppKit)
import AppKit
extension MCBrowserViewControllerView: NSViewControllerRepresentable {}
#elseif canImport(UIKit)
import UIKit
extension MCBrowserViewControllerView: UIViewControllerRepresentable {}
#endif
