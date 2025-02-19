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
import Promises
import PsiApi
import AppStoreIAP
import PsiCashClient

extension AppAction {
    
    var appDelegateAction: AppDelegateAction? {
        get {
            guard case let .appDelegateAction(value) = self else { return nil }
            return value
        }
        set {
            guard case .appDelegateAction = self, let newValue = newValue else { return }
            self = .appDelegateAction(newValue)
        }
    }
    
    var psiCash: PsiCashAction? {
        get {
            guard case let .psiCash(value) = self else { return nil }
            return value
        }
        set {
            guard case .psiCash = self, let newValue = newValue else { return }
            self = .psiCash(newValue)
        }
    }
    
    var landingPage: LandingPageAction? {
        get {
            guard case let .landingPage(value) = self else { return nil }
            return value
        }
        set {
            guard case .landingPage = self, let newValue = newValue else { return }
            self = .landingPage(newValue)
        }
    }
    
    var inAppPurchase: IAPAction? {
        get {
            guard case let .iap(value) = self else { return nil }
            return value
        }
        set {
            guard case .iap = self, let newValue = newValue else { return }
            self = .iap(newValue)
        }
    }
    
    var appReceipt: ReceiptStateAction? {
        get {
            guard case let .appReceipt(value) = self else { return nil }
            return value
        }
        set {
            guard case .appReceipt = self, let newValue = newValue else { return }
            self = .appReceipt(newValue)
        }
    }
    
    var subscription: SubscriptionAction? {
        get {
            guard case let .subscription(value) = self else { return nil }
            return value
        }
        set {
            guard case .subscription = self, let newValue = newValue else { return }
            self = .subscription(newValue)
        }
    }
    
    var subscriptionAuthStateAction: SubscriptionAuthStateAction? {
        get {
            guard case let .subscriptionAuthStateAction(value) = self else { return nil }
            return value
        }
        set {
            guard case .subscriptionAuthStateAction = self, let newValue = newValue else { return }
            self = .subscriptionAuthStateAction(newValue)
        }
    }
    
    var productRequest: ProductRequestAction? {
        get {
            guard case let .productRequest(value) = self else { return nil }
            return value
        }
        set {
            guard case .productRequest = self, let newValue = newValue else { return }
            self = .productRequest(newValue)
        }
    }
    
    var reachabilityAction: ReachabilityAction? {
        get {
            guard case let .reachabilityAction(value) = self else { return nil }
            return value
        }
        set {
            guard case .reachabilityAction = self, let newValue = newValue else { return }
            self = .reachabilityAction(newValue)
        }
    }
    
    var vpnStateAction: VPNStateAction<PsiphonTPM>? {
        get {
            guard case let .vpnStateAction(value) = self else { return nil }
            return value
        }
        set {
            guard case .vpnStateAction = self, let newValue = newValue else { return }
            self = .vpnStateAction(newValue)
        }
    }
    
    var feedbackAction: FeedbackAction? {
        get {
            guard case let .feedbackAction(value) = self else { return nil }
            return value
        }
        set {
            guard case .feedbackAction = self, let newValue = newValue else { return }
            self = .feedbackAction(newValue)
        }
    }
    
    var mainViewAction: MainViewAction? {
        get {
            guard case let .mainViewAction(value) = self else { return nil }
            return value
        }
        set {
            guard case .mainViewAction = self, let newValue = newValue else { return }
            self = .mainViewAction(newValue)
        }
    }
    
    var serverRegionAction: ServerRegionAction? {
        get {
            guard case let .serverRegionAction(value) = self else { return nil }
            return value
        }
        set {
            guard case .serverRegionAction = self, let newValue = newValue else { return }
            self = .serverRegionAction(newValue)
        }
    }
    
}


extension AppState {
    
    /// `tunnelConnection` returns a TunnelConnection object holding a weak reference to the underlying
    ///  TunnelProviderManager reference if it exists.
    var tunnelConnection: TunnelConnection? {
        get {
            // Workaround, since VPN config cannot be installed on a simulator.
            #if targetEnvironment(simulator)
            return TunnelConnection { () -> TunnelConnection.ConnectionResourceStatus in
                return .connection(.connected)
            }
            #else
            guard case let .loaded(tpm) = self.vpnState.value.loadState.value else {
                return nil
            }
            return tpm.connection
            #endif
        }
    }
    
    var vpnReducerState: VPNReducerState<PsiphonTPM> {
        get {
            VPNReducerState(
                pendingActionQueue: self.vpnState.pendingActionQueue,
                pendingEffectActionQueue: self.vpnState.pendingEffectActionQueue,
                pendingEffectCompletion: self.vpnState.pendingEffectCompletion,
                value: VPNProviderManagerReducerState (
                    vpnState: self.vpnState.value,
                    anySubscriptionTxPendingAuthorization:
                        self.subscriptionAuthState.anyPendingAuthRequests
                )
            )
        }
        set {
            self.vpnState.pendingActionQueue = newValue.pendingActionQueue
            self.vpnState.pendingEffectActionQueue = newValue.pendingEffectActionQueue
            self.vpnState.pendingEffectCompletion = newValue.pendingEffectCompletion
            self.vpnState.value = newValue.value.vpnState
        }
    }
    
    var iapReducerState: IAPReducerState {
        get {
            IAPReducerState(
                iap: self.iapState,
                receiptData: self.appReceipt.receiptData,
                psiCashBalance: self.psiCashBalance,
                psiCashAccountType: self.psiCashState.libData?.successToOptional()?.accountType
            )
        }
        set {
            self.iapState = newValue.iap
            self.psiCashBalance = newValue.psiCashBalance
        }
    }
    
    var psiCashReducerState: PsiCashReducerState {
        get {
            PsiCashReducerState(
                psiCashBalance: self.psiCashBalance,
                psiCash: self.psiCashState,
                subscription: self.subscription,
                tunnelConnection: self.tunnelConnection
            )
        }
        set {
            self.psiCashBalance = newValue.psiCashBalance
            self.psiCashState = newValue.psiCash
        }
    }
    
    var appDelegateReducerState: AppDelegateReducerState {
        get {
            AppDelegateReducerState(
                appDelegateState: self.appDelegateState,
                subscriptionState: self.subscription,
                psiCashState: self.psiCashState,
                tunnelConnectedStatus: self.vpnState.value.providerVPNStatus.tunneled
            )
        }
        set {
            self.appDelegateState = newValue.appDelegateState
        }
    }
    
    var landingPageReducerState: LandingPageReducerState {
        get {
            LandingPageReducerState(
                pendingLandingPageOpening: self.pendingLandingPageOpening,
                tunnelConnection: self.tunnelConnection,
                applicationParameters: self.appDelegateState.applicationParameters
            )
        }
        set {
            self.pendingLandingPageOpening = newValue.pendingLandingPageOpening
        }
    }
    
    var psiCashStoreViewControllerReaderState: PsiCashStoreViewController.ReaderState {
        PsiCashStoreViewController.ReaderState(
            mainViewState: self.mainView,
            psiCashBalanceViewModel: self.psiCashBalanceViewModel,
            psiCash: self.psiCashState,
            iap: self.iapState,
            subscription: self.subscription,
            appStorePsiCashProducts: self.products.psiCashProducts,
            isRefreshingAppStoreReceipt: self.appReceipt.isRefreshingReceipt
        )
    }
    
    var psiCashBalanceViewModel: PsiCashBalanceViewModel {
        PsiCashBalanceViewModel(
            psiCashLibLoaded: self.psiCashState.libData != nil,
            balanceState: self.balanceState
        )
    }
    
    var balanceState: BalanceState {
        BalanceState(
            pendingPsiCashRefresh: self.psiCashState.pendingPsiCashRefresh,
            psiCashBalance: self.psiCashBalance
        )
    }
    
    var feedbackReducerState: FeedbackReducerState {
        get {
            FeedbackReducerState(
                queuedFeedbacks: self.queuedFeedbacks
            )
        }
        set {
            self.queuedFeedbacks = newValue.queuedFeedbacks
        }
    }
    
    var mainViewReducerState: MainViewReducerState {
        get {
            MainViewReducerState(
                mainView: self.mainView,
                subscriptionState: self.subscription,
                psiCashState: self.psiCashState,
                psiCashAccountType: self.psiCashState.libData?.successToOptional()?.accountType,
                appLifecycle: self.appDelegateState.appLifecycle,
                tunnelConnectedStatus: self.vpnState.value.providerVPNStatus.tunneled,
                applicationParameters: self.appDelegateState.applicationParameters
            )
        }
        set {
            self.mainView = newValue.mainView
        }
    }
    
}
