import Foundation
import MultipeerConnectivity
import os

private let log = Logger(subsystem: "notchshare", category: "peer")

public enum DeviceRole: String { case mac, iphone }

/// Long-lived Multipeer object (advertiser + browser + session). Keep a strong
/// reference — if it is released the session drops silently.
public final class PeerSession: NSObject, ObservableObject {
    public static let serviceType = "notchshare"

    @Published public private(set) var connectedPeers: [MCPeerID] = []

    public var onMessage: ((NotchShareMessage, MCPeerID) -> Void)?
    public var onPeerConnected: ((MCPeerID) -> Void)?
    public var onPeerDisconnected: ((MCPeerID) -> Void)?
    public var onResourceStarted: ((String, MCPeerID, Progress) -> Void)?
    public var onResourceReceived: ((String, MCPeerID, URL?, Error?) -> Void)?

    public let role: DeviceRole
    public let myPeerID: MCPeerID
    public let session: MCSession
    private let advertiser: MCNearbyServiceAdvertiser
    private let browser: MCNearbyServiceBrowser

    public init(role: DeviceRole, displayName: String) {
        self.role = role
        myPeerID = MCPeerID(displayName: displayName)
        session = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .optional)
        advertiser = MCNearbyServiceAdvertiser(peer: myPeerID,
                                               discoveryInfo: ["role": role.rawValue],
                                               serviceType: Self.serviceType)
        browser = MCNearbyServiceBrowser(peer: myPeerID, serviceType: Self.serviceType)
        super.init()
        session.delegate = self
        advertiser.delegate = self
        browser.delegate = self
    }

    public func start() {
        advertiser.startAdvertisingPeer()
        browser.startBrowsingForPeers()
    }

    public func stop() {
        advertiser.stopAdvertisingPeer()
        browser.stopBrowsingForPeers()
        session.disconnect()
    }

    public func send(_ message: NotchShareMessage, to peers: [MCPeerID]? = nil) {
        let targets = peers ?? session.connectedPeers
        guard !targets.isEmpty, let data = try? message.encoded() else { return }
        try? session.send(data, toPeers: targets, with: .reliable)
    }

    private var knownPeers: [MCPeerID] = []
    private var invitedAt: [MCPeerID: Date] = [:]
    private var browserRef: MCNearbyServiceBrowser { browser }

    /// Mac only: if a peer drops or the invitation failed, invite again shortly.
    private func retryInvite(_ peerID: MCPeerID) {
        guard role == .mac, knownPeers.contains(peerID) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.invite(peerID)
        }
    }

    /// Invite at most once per 10 s per peer, and never while connected.
    /// Duplicate invitations tear down the connection being established.
    private func invite(_ peerID: MCPeerID) {
        guard !session.connectedPeers.contains(peerID) else { return }
        if let t = invitedAt[peerID], Date().timeIntervalSince(t) < 10 { return }
        invitedAt[peerID] = Date()
        log.notice("inviting \(peerID.displayName, privacy: .public)")
        browserRef.invitePeer(peerID, to: session, withContext: nil, timeout: 15)
    }

    private func update() {
        DispatchQueue.main.async { self.connectedPeers = self.session.connectedPeers }
    }
}

extension PeerSession: MCSessionDelegate {
    public func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        log.notice("state \(peerID.displayName, privacy: .public) -> \(state.rawValue)")
        update()
        switch state {
        case .connected: onPeerConnected?(peerID)
        case .notConnected:
            onPeerDisconnected?(peerID)
            retryInvite(peerID)
        default: break
        }
    }

    public func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard let msg = try? NotchShareMessage.decode(data) else { return }
        onMessage?(msg, peerID)
    }

    public func session(_ session: MCSession, didReceive stream: InputStream,
                        withName streamName: String, fromPeer peerID: MCPeerID) {}

    public func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String,
                        fromPeer peerID: MCPeerID, with progress: Progress) {
        onResourceStarted?(resourceName, peerID, progress)
    }

    public func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String,
                        fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {
        onResourceReceived?(resourceName, peerID, localURL, error)
    }
}

extension PeerSession: MCNearbyServiceAdvertiserDelegate {
    public func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        log.error("advertise failed: \(error.localizedDescription, privacy: .public)")
    }

    public func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                           didReceiveInvitationFromPeer peerID: MCPeerID,
                           withContext context: Data?,
                           invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        log.notice("invitation from \(peerID.displayName, privacy: .public)")
        // Decline duplicates: re-accepting while connected drops the live connection.
        if session.connectedPeers.contains(peerID) { invitationHandler(false, nil); return }
        invitationHandler(true, session)
    }
}

extension PeerSession: MCNearbyServiceBrowserDelegate {
    public func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID,
                        withDiscoveryInfo info: [String: String]?) {
        guard info?["role"] != role.rawValue else { return }
        // Only the Mac invites, so the two sides never send crossed invitations.
        log.notice("found \(peerID.displayName, privacy: .public) role=\(info?["role"] ?? "?", privacy: .public)")
        guard role == .mac else { return }
        if !knownPeers.contains(peerID) { knownPeers.append(peerID) }
        invite(peerID)
    }

    public func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        log.notice("lost \(peerID.displayName, privacy: .public)")
    }

    public func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        log.error("browse failed: \(error.localizedDescription, privacy: .public)")
    }
}
