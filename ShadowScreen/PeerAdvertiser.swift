import Foundation
import MultipeerConnectivity
import Combine

final actor PeerAdvertiser {
    private var shouldConnectToBuilder: (_ title: String, _ message: String) async -> Bool
    func setShouldConnectToBuilder(_ shouldConnectToBuilder: @escaping (String, String) async -> Bool) { self.shouldConnectToBuilder = shouldConnectToBuilder }

    private let peerID: MCPeerID
    private let advertiser: MCNearbyServiceAdvertiser
    private var session: MCSession? {
        didSet {
            oldValue?.disconnect()
            session?.delegate = sessionDelegate
        }
    }
    private let advertiserDelegate: AdvertiserDelegate
    private let sessionDelegate: SessionDelegate

    private let receivedDataSubject = PassthroughSubject<Data, Never>()
    var receivedData: some Publisher<Data, Never> { receivedDataSubject }

    enum Error: Swift.Error {
        case invalidFilePath(String)
        case fileAlreadyExists(String)
    }

    init(hostName: String = ProcessInfo().hostName, bundleID: String = Env.shared.CFBundleIdentifier!, processID: Int32 = ProcessInfo().processIdentifier, shouldConnectToBuilder: @escaping (_ title: String, _ message: String) async -> Bool) {
        self.shouldConnectToBuilder = shouldConnectToBuilder
        // the doc: The display name is intended for use in UI elements, and should be short and descriptive of the local peer. The maximum allowable length is 63 bytes in UTF-8 encoding. The displayName parameter may not be nil or an empty string.
        let displayName = String("\(hostName) \(bundleID)(\(processID))".utf8.prefix(63))!
        self.peerID = MCPeerID(displayName: displayName)
        self.advertiser = MCNearbyServiceAdvertiser(peer: peerID, discoveryInfo: MultipeerConnectivityConstants.serverDiscoveryInfo, serviceType: MultipeerConnectivityConstants.serviceType)
        self.advertiserDelegate = AdvertiserDelegate()
        self.sessionDelegate = SessionDelegate()

        self.advertiser.delegate = self.advertiserDelegate

        Task {
            advertiserDelegate.advertiser = self
            sessionDelegate.advertiser = self
            await start()
        }
    }

    func start() {
        advertiser.startAdvertisingPeer()
    }

    func stop() {
        advertiser.stopAdvertisingPeer()
        session = nil
    }

    // MARK: - MCNearbyServiceAdvertiserDelegate

    private final class AdvertiserDelegate: NSObject, MCNearbyServiceAdvertiserDelegate {
        unowned var advertiser: PeerAdvertiser?
        override init() { super.init() }
        func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
            NSLog("%@", "🍓 \(#function) advertiser = \(advertiser), peerID = \(peerID), context = \(context?.count ?? 0) bytes")
            Task { await self.advertiser?.advertiser(advertiser, didReceiveInvitationFromPeer: peerID, withContext: context, invitationHandler: invitationHandler) }
        }
        func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Swift.Error) {
            NSLog("%@", "🍓 \(#function) advertiser = \(advertiser), error = \(error)")
            Task { await self.advertiser?.advertiser(advertiser, didNotStartAdvertisingPeer: error) }
        }
    }

    private func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        NSLog("%@", "🍓 \(#function) advertiser = \(advertiser), peerID = \(peerID), context = \(context?.count ?? 0) bytes")
        guard session == nil else {
            NSLog("%@", "🍓 \(#function) ignored additional session")
            return
        }

        Task {
            let trusted = await shouldConnectToBuilder("⚠️ Connect to a Builder \(peerID)?", "SwiftHotReload loads any code from the Builder")
            if trusted {
                self.session = MCSession(peer: self.peerID, securityIdentity: nil, encryptionPreference: .required)
            }
            invitationHandler(trusted, self.session)
        }
    }

    private func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Swift.Error) {
        NSLog("%@", "🍓 \(#function) advertiser = \(advertiser), error = \(error)")
    }

    // MARK: - MCSessionDelegate

    private final class SessionDelegate: NSObject, MCSessionDelegate {
        unowned var advertiser: PeerAdvertiser?
        override init() { super.init() }

        func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
            NSLog("%@", "🍓 \(#function) peerID = \(peerID), state = \(state)")
            Task { await advertiser?.session(session, peer: peerID, didChange: state) }
        }

        func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
            // NSLog("%@", "🍓 \(#function) data = \(data.count) bytes, peerID = \(peerID)")
            Task { await advertiser?.session(session, didReceive: data, fromPeer: peerID) }
        }

        func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {
            NSLog("%@", "🍓 \(#function) stream = \(stream), streamName = \(streamName), peerID = \(peerID)")
            Task { await advertiser?.session(session, didReceive: stream, withName: streamName, fromPeer: peerID) }
        }

        func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {
            NSLog("%@", "🍓 \(#function) resourceName = \(resourceName), peerID = \(peerID), progress = \(progress)")
        }

        func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Swift.Error?) {
            NSLog("%@", "🍓 \(#function) resourceName = \(resourceName), peerID = \(peerID), localURL = \(String(describing: localURL)), error = \(String(describing: error))")
        }
    }

    private func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        switch state {
        case .notConnected:
            self.session = nil
        case .connecting: break
        case .connected:
            Task.detached { @MainActor in
                do {
                    NSLog("%@", "🍓 \(#function) connected: sending ... = TODO")
//                    try await self.session?.send(payload, toPeers: [peerID], with: .reliable)
                } catch {
                    NSLog("%@", "🍓 \(#function) error = \(error)")
                }
            }
        @unknown default: break
        }
    }

    private func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
//        Task.detached { @MainActor in self.receivedDataSubject.send(data) }
    }

    private func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) async {
        for await data in ATOM.parse(stream: stream) {
            // NSLog("%@", "for await seq = \(HEVC(data: data)?.dummySequenceNumber ?? 0) bytes")
            receivedDataSubject.send(data)
        }
    }
}

