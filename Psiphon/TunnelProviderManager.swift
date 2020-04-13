/*
 * Copyright (c) 2020, Psiphon Inc.
 * All rights reserved.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 */

import Foundation
import ReactiveSwift
import NetworkExtension


enum TunnelConnectedStatus {
    case connected
    case connecting
    case notConnected
}

/// Connection status of the tunnel provider.
typealias TunnelProviderVPNStatus = NEVPNStatus

extension TunnelProviderVPNStatus {
    
    /// `providerNotStopped` value represents whether the tunnel provider process is running, and
    /// is not stopped or in the process of getting stopped.
    /// - Note: A tunnel provider that is running can also be in a zombie state.
    var providerNotStopped: Bool {
        switch self {
        case .invalid, .disconnected, .disconnecting:
            return false
        case .connecting, .connected, .reasserting:
            return true
        @unknown default:
            fatalError("unknown NEVPNStatus value '\(self.rawValue)'")
        }
    }
    
    var tunneled: TunnelConnectedStatus {
        if Debugging.ignoreTunneledChecks {
            return .connected
        }
        switch self {
        case .invalid, .disconnected:
            return .notConnected
        case .connecting, .reasserting:
            return .connecting
        case .connected:
            return .connected
        case .disconnecting:
            return .notConnected
        @unknown default:
            return .notConnected
        }
    }
    
}

extension NEVPNError {
    
    var configurationReadWriteFailedPermissionDenied: Bool {
        return self.code == .configurationReadWriteFailed &&
            self.localizedDescription == "permission denied"
    }
    
}

enum TunnelProviderManagerUpdateType {
    case startVPN
    case stopVPN
}

struct ProviderResponseMessageError: HashableError {
    let message: String
}

enum ProviderMessageSendError: HashableError {
    case providerNotActive
    case other(Either<NEVPNError, ProviderResponseMessageError>)
}

class VPNConnectionObserver<T: TunnelProviderManager>:
StoreDelegate<VPNProviderManagerStateAction<T>>
{
    func setTunnelProviderManager(_ manager: T) {}
}

protocol TunnelProviderManager: class, Equatable {

    var connectionStatus: TunnelProviderVPNStatus { get }
    
    static func loadAll(completionHandler: @escaping ([Self]?, NEVPNError?) -> Void)
    
    static func make() -> Self
    
    func save(completionHandler: @escaping (NEVPNError?) -> Void)
    
    func load(completionHandler: @escaping (NEVPNError?) -> Void)
    
    func remove(completionHandler: @escaping (NEVPNError?) -> Void)
    
    func start(options: [String : Any]?) throws
    
    func stop()
    
    func sendProviderMessage(_ messageData: Data, responseHandler: @escaping (Data?) -> Void) throws
    
    func observeConnectionStatus(observer: VPNConnectionObserver<Self>)
    
    func updateConfig(for updateType: TunnelProviderManagerUpdateType)
    
}

/// Wrapper around `NETunnelProviderManager` that adheres to TunnelProviderManager protocol.
final class PsiphonTPM: TunnelProviderManager {
    
    var connectionStatus: TunnelProviderVPNStatus {
        wrappedManager.connection.status
    }

    fileprivate let wrappedManager: NETunnelProviderManager
    
    private init(_ manager: NETunnelProviderManager) {
        self.wrappedManager = manager
    }
    
    private static func VPNError(from maybeError: Error?) -> NEVPNError? {
        if let error = maybeError {
            return NEVPNError(_nsError: error as NSError)
        } else {
            return nil
        }
    }
    
    static func make() -> PsiphonTPM {
        let providerProtocol = NETunnelProviderProtocol()
        providerProtocol.providerBundleIdentifier = "ca.psiphon.Psiphon.PsiphonVPN"
        providerProtocol.serverAddress = "localhost"
        let instance = PsiphonTPM(NETunnelProviderManager())
        instance.wrappedManager.protocolConfiguration = providerProtocol
        return instance
    }
    
    static func loadAll(
        completionHandler: @escaping ([PsiphonTPM]?, NEVPNError?) -> Void
    ) {
        return NETunnelProviderManager.loadAllFromPreferences { (maybeManagers, maybeError) in
            completionHandler(maybeManagers?.map(PsiphonTPM.init), Self.VPNError(from: maybeError))
        }
    }
    
    func save(completionHandler: @escaping (NEVPNError?) -> Void) {
        self.wrappedManager.saveToPreferences { maybeError in
            completionHandler(Self.VPNError(from: maybeError))
        }
    }
    
    func load(completionHandler: @escaping (NEVPNError?) -> Void) {
        self.wrappedManager.loadFromPreferences { maybeError in
            completionHandler(Self.VPNError(from: maybeError))
        }
    }
    
    /// Ref:
    /// https://developer.apple.com/documentation/networkextension/nevpnmanager/1406202-removefrompreferences
    /// After the configuration is removed from the preferences the NEVPNManager object will still
    /// contain the configuration parameters. Calling `loadFromPreferences(completionHandler:):`
    /// will clear out the configuration parameters from the NEVPNManager object.
    func remove(completionHandler: @escaping (NEVPNError?) -> Void) {
        self.wrappedManager.removeFromPreferences { maybeError in
            completionHandler(Self.VPNError(from: maybeError))
        }
    }
    
    func start(options: [String : Any]?) throws {
        let session = self.wrappedManager.connection as! NETunnelProviderSession
        try session.startTunnel(options: options)
        // Enables Connect On Demand only after starting the tunnel.
        // Otherwise, a race condition is created in the network extension
        // between call to `startVPNTunnelWithOptions` and Connect On Demand.
        self.wrappedManager.isOnDemandEnabled = true
    }
    
    func stop() {
        self.wrappedManager.connection.stopVPNTunnel()
    }
    
    func sendProviderMessage(
        _ messageData: Data, responseHandler: @escaping (Data?) -> Void
    ) throws {
        let session = self.wrappedManager.connection as! NETunnelProviderSession
        try session.sendProviderMessage(messageData, responseHandler: responseHandler)
    }
    
    func observeConnectionStatus(observer: VPNConnectionObserver<PsiphonTPM>) {
        observer.setTunnelProviderManager(self)
    }
    
    func updateConfig(for updateType: TunnelProviderManagerUpdateType) {
        switch updateType {
        case .startVPN:
            // setEnabled becomes false if the user changes the
            // enabled VPN Configuration from the preferences.
            self.wrappedManager.isEnabled = true
            
            // Adds "always connect" Connect On Demand rule to the configuration.
            if self.wrappedManager.onDemandRules == nil ||
                self.wrappedManager.onDemandRules?.count == 0
            {
                let alwaysConnectRule: NEOnDemandRule = NEOnDemandRuleConnect()
                self.wrappedManager.onDemandRules = [ alwaysConnectRule ]
            }
            
            // Reset Connect On Demand state.
            // To enable Connect On Demand for all, it should be enabled
            // right before startPsiphonTunnel is called on the NETunnelProviderManager object.
            self.wrappedManager.isOnDemandEnabled = false
            
        case .stopVPN:
            self.wrappedManager.isOnDemandEnabled = false
        }
    }
    
    static func == (
        lhs: PsiphonTPM, rhs: PsiphonTPM
    ) -> Bool {
        lhs.wrappedManager === rhs.wrappedManager
    }
    
}

func loadFromPreferences<T: TunnelProviderManager>()
    -> Effect<Result<[T], ErrorEvent<NEVPNError>>>
{
    Effect { observer, _ in
        T.loadAll { (maybeManagers: [T]?, maybeError: Error?) in
                switch (maybeManagers, maybeError) {
                case (nil, nil):
                    observer.fulfill(value: .success([]))
                case (.some(let managers), nil):
                    observer.fulfill(value: .success(managers))
                case (_ , .some(let error)):
                    observer.fulfill(value:
                        .failure(ErrorEvent(NEVPNError(_nsError: error as NSError))))
                }
        }
    }
}

func updateConfig<T: TunnelProviderManager>(
    _ tpm: T, for updateType: TunnelProviderManagerUpdateType
) -> Effect<T> {
    Effect { () -> T in
        tpm.updateConfig(for: updateType)
        return tpm
    }
}

func startPsiphonTunnel<T: TunnelProviderManager>(_ tpm: T)
    -> Effect<Result<T, ErrorEvent<NEVPNError>>>
{
            Effect { () -> Result<T, ErrorEvent<NEVPNError>> in
                let options = [EXTENSION_OPTION_START_FROM_CONTAINER: EXTENSION_OPTION_TRUE]
                do {
                    try tpm.start(options: options)
                    return .success(tpm)
                } catch {
                    return .failure(ErrorEvent(NEVPNError(_nsError: error as NSError)))
                }
            }
}

func stopVPN<T: TunnelProviderManager>(_ tpm: T) -> Effect<()> {
    Effect { () -> Void in
        tpm.stop()
        return ()
    }
}

func saveAndLoadConfig<T: TunnelProviderManager>(_ tpm: T)
    -> Effect<Result<T, ErrorEvent<NEVPNError>>>
{
    Effect { observer, _ in
        tpm.save { maybeError in
            if let error = maybeError {
                observer.fulfill(value: .failure(ErrorEvent(error)))
            } else {
                tpm.load { maybeError in
                    if let error = maybeError {
                        observer.fulfill(value: .failure(ErrorEvent(error)))
                    } else {
                        observer.fulfill(value: .success(tpm))
                    }
                }
            }
        }
    }
}

func removeFromPreferences<T: TunnelProviderManager>(_ tpm: T)
    -> Effect<Result<(), ErrorEvent<NEVPNError>>>
{
    Effect { observer, _ in
        tpm.remove { maybeError in
            if let error = maybeError {
                observer.fulfill(value: .failure(ErrorEvent(error)))
            } else {
                observer.fulfill(value: .success(()))
            }
        }
    }

}

/// Updates `VPNConnectionObserver` to observe VPN status change.
func observeConnectionStatus<T: TunnelProviderManager>(
    for tpm: T, observer: VPNConnectionObserver<T>
) {
    observer.setTunnelProviderManager(tpm)
}

/// Sends message do the tunnel provider if it is active.
/// If not active, an error event with value `ProviderMessageError.providerNotActive` is sent.
func sendMessage<T: TunnelProviderManager>(
    toProvider tpm: T, data: Data
) -> Effect<(T, Result<Data, ErrorEvent<ProviderMessageSendError>>)> {
    Effect { observer, _ in
        guard tpm.connectionStatus.providerNotStopped else {
            observer.fulfill(value: (tpm, .failure(ErrorEvent(.providerNotActive))))
            return
        }
        
        do {
            try tpm.sendProviderMessage(data) { maybeResponseData in
                // A respose is always required from the tunenl provider.
                guard let responseData = maybeResponseData else {
                    let error: ProviderMessageSendError = .other(.right(
                        ProviderResponseMessageError(message: "nil response")))
                    
                    observer.fulfill(value: (tpm, .failure(ErrorEvent(error))))
                    return
                }
                observer.fulfill(value: (tpm, .success(responseData)))
            }
        } catch {
            let vpnError = NEVPNError(_nsError: error as NSError)
            observer.fulfill(value:
                (tpm, .failure(ErrorEvent(.other(.left(vpnError)))))
            )
        }
    }
}

// MARK: Connection status observer

final class PsiphonTPMConnectionObserver: VPNConnectionObserver<PsiphonTPM> {
    
    private weak var tunnelProviderManager: PsiphonTPM? = nil
    
    /// - Note: Removes previous `NEVPNStatusDidChange` NSNotification observer if any.
    override func setTunnelProviderManager(_ manager: PsiphonTPM) {
        if let current = self.tunnelProviderManager {
            NotificationCenter.default.removeObserver(self, name: .NEVPNStatusDidChange,
                                                      object: current.wrappedManager)
        }
        self.tunnelProviderManager = manager
        NotificationCenter.default.addObserver(self, selector: #selector(statusDidChange),
                                               name: .NEVPNStatusDidChange,
                                               object: manager.wrappedManager.connection)
        
        // Updates the tunnel with the current status before
        // notifications for status change kick in.
        statusDidChange()
    }
    
    @objc private func statusDidChange() {
        guard let manager = self.tunnelProviderManager else {
            fatalError()
        }
        sendOnMain(.vpnStatusChanged(manager.connectionStatus))
    }
    
}
