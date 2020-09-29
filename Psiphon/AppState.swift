/*
 * Copyright (c) 2019, Psiphon Inc.
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
import PsiApi
import AppStoreIAP
import PsiCashClient

var Style = AppStyle()

/// Represents UIViewController's that can be dismissed.
@objc enum DismissibleScreen: Int {
    case psiCash
}

struct AppState: Equatable {
    var vpnState = VPNState<PsiphonTPM>(.init())
    var psiCashBalance = PsiCashBalance()
    var psiCash = PsiCashState()
    var appReceipt = ReceiptState()
    var subscription = SubscriptionState()
    var subscriptionAuthState = SubscriptionAuthState()
    var iapState = IAPState()
    var products = PsiCashAppStoreProductsState()
    var pendingLandingPageOpening: Bool = false
    var internetReachability = ReachabilityState()
    var appDelegateState = AppDelegateState()
}

struct BalanceState: Equatable {
    let pendingPsiCashRefresh: PendingPsiCashRefresh
    let psiCashBalance: PsiCashBalance
}
 
// MARK: AppAction

enum AppAction {
    case vpnStateAction(VPNStateAction<PsiphonTPM>)
    case appDelegateAction(AppDelegateAction)
    case psiCash(PsiCashAction)
    case landingPage(LandingPageAction)
    case iap(IAPAction)
    case appReceipt(ReceiptStateAction)
    case subscription(SubscriptionAction)
    case subscriptionAuthStateAction(SubscriptionAuthStateAction)
    case productRequest(ProductRequestAction)
    case reachabilityAction(ReachabilityAction)
}

// MARK: Environment

typealias AppEnvironment = (
    appBundle: PsiphonBundle,
    feedbackLogger: FeedbackLogger,
    httpClient: HTTPClient,
    psiCashEffects: PsiCashEffects,
    psiCashFileStoreRoot: String?,
    clientMetaData: () -> ClientMetaData,
    sharedDB: PsiphonDataSharedDB,
    userConfigs: UserDefaultsConfig,
    notifier: PsiApi.Notifier,
    tunnelStatusSignal: SignalProducer<TunnelProviderVPNStatus, Never>,
    psiCashAccountTypeSignal: SignalProducer<PsiCashAccountType?, Never>,
    tunnelConnectionRefSignal: SignalProducer<TunnelConnection?, Never>,
    urlHandler: URLHandler,
    paymentQueue: PaymentQueue,
    supportedAppStoreProducts: SupportedAppStoreProducts,
    objcBridgeDelegate: ObjCBridgeDelegate,
    receiptRefreshRequestDelegate: ReceiptRefreshRequestDelegate,
    paymentTransactionDelegate: PaymentTransactionDelegate,
    rewardedVideoAdBridgeDelegate: RewardedVideoAdBridgeDelegate,
    productRequestDelegate: ProductRequestDelegate,
    internetReachability: InternetReachability,
    internetReachabilityDelegate: StoreDelegate<ReachabilityAction>,
    vpnConnectionObserver: VPNConnectionObserver<PsiphonTPM>,
    vpnActionStore: (VPNPublicAction) -> Effect<Never>,
    psiCashStore: (PsiCashAction) -> Effect<Never>,
    appReceiptStore: (ReceiptStateAction) -> Effect<Never>,
    iapStore: (IAPAction) -> Effect<Never>,
    subscriptionStore: (SubscriptionAction) -> Effect<Never>,
    subscriptionAuthStateStore: (SubscriptionAuthStateAction) -> Effect<Never>,
    /// `vpnStartCondition` returns true whenever the app is in such a state as to to allow
    /// the VPN to be started. If false is returned the VPN should not be started.
    vpnStartCondition: () -> Bool,
    dateCompare: DateCompare,
    mainDispatcher: MainDispatcher,
    globalDispatcher: GlobalDispatcher
)

/// Creates required environment for store `Store<AppState, AppAction>`.
/// - Returns: Tuple (environment, cleanup). `cleanup` should be called
/// in `applicationWillTerminate(:_)` delegate callback.
func makeEnvironment(
    store: Store<AppState, AppAction>,
    feedbackLogger: FeedbackLogger,
    sharedDB: PsiphonDataSharedDB,
    psiCashClient: PsiCash,
    psiCashFileStoreRoot: String?,
    supportedAppStoreProducts: SupportedAppStoreProducts,
    userDefaultsConfig: UserDefaultsConfig,
    objcBridgeDelegate: ObjCBridgeDelegate,
    rewardedVideoAdBridgeDelegate: RewardedVideoAdBridgeDelegate,
    dateCompare: DateCompare,
    mainDispatcher: MainDispatcher,
    globalDispatcher: GlobalDispatcher
) -> (environment: AppEnvironment, cleanup: () -> Void) {
    
    let urlSessionConfig = URLSessionConfiguration.default
    urlSessionConfig.timeoutIntervalForRequest = UrlRequestParameters.timeoutInterval
    urlSessionConfig.requestCachePolicy = UrlRequestParameters.cachePolicy
    if #available(iOS 11.0, *) {
        // waitsForConnectivity determines whether the session should wait for connectivity
        // to become available, or fail immediately.
        urlSessionConfig.waitsForConnectivity = false
    }
    let urlSession = URLSession(configuration: urlSessionConfig)
    
    let paymentTransactionDelegate = PaymentTransactionDelegate(store:
        store.projection(
            value: erase,
            action: { .iap(.transactionUpdate($0)) })
    )
    SKPaymentQueue.default().add(paymentTransactionDelegate)
    
    let reachabilityForInternetConnection = Reachability.forInternetConnection()!
    
    let httpClient = HTTPClient.default(urlSession: urlSession)
    
    let environment = AppEnvironment(
        appBundle: PsiphonBundle.from(bundle: Bundle.main),
        feedbackLogger: feedbackLogger,
        httpClient: httpClient,
        psiCashEffects: PsiCashEffects.default(psiCash: psiCashClient,
                                               httpClient: httpClient,
                                               globalDispatcher: globalDispatcher,
                                               getCurrentTime: dateCompare.getCurrentTime,
                                               feedbackLogger: feedbackLogger),
        psiCashFileStoreRoot: psiCashFileStoreRoot,
        clientMetaData: { ClientMetaData(AppInfoObjC()) },
        sharedDB: sharedDB,
        userConfigs: userDefaultsConfig,
        notifier: NotifierObjC(notifier:Notifier.sharedInstance()),
        tunnelStatusSignal: store.$value.signalProducer
            .map(\.vpnState.value.providerVPNStatus),
        psiCashAccountTypeSignal: store.$value.signalProducer.map(\.psiCash.libData.accountType),
        tunnelConnectionRefSignal: store.$value.signalProducer.map(\.tunnelConnection),
        urlHandler: .default(),
        paymentQueue: .default,
        supportedAppStoreProducts: supportedAppStoreProducts,
        objcBridgeDelegate: objcBridgeDelegate,
        receiptRefreshRequestDelegate: ReceiptRefreshRequestDelegate(store:
            store.projection(
                value: erase,
                action: { .appReceipt($0) })
        ),
        paymentTransactionDelegate: paymentTransactionDelegate,
        rewardedVideoAdBridgeDelegate: rewardedVideoAdBridgeDelegate,
        productRequestDelegate: ProductRequestDelegate(store:
            store.projection(
                value: erase,
                action: { .productRequest($0) })
        ),
        internetReachability: reachabilityForInternetConnection,
        internetReachabilityDelegate: InternetReachabilityDelegate(
            reachability: reachabilityForInternetConnection,
            store: store.projection(
                value: erase,
                action: { .reachabilityAction($0) })
        ),
        vpnConnectionObserver: PsiphonTPMConnectionObserver(store:
            store.projection(value: erase,
                             action: { .vpnStateAction(.action(._vpnStatusDidChange($0))) })
        ),
        vpnActionStore: { [unowned store] (action: VPNPublicAction) -> Effect<Never> in
            .fireAndForget {
                store.send(vpnAction: action)
            }
        },
        psiCashStore: { [unowned store] (action: PsiCashAction) -> Effect<Never> in
            .fireAndForget {
                store.send(.psiCash(action))
            }
        },
        appReceiptStore: { [unowned store] (action: ReceiptStateAction) -> Effect<Never> in
            .fireAndForget {
                store.send(.appReceipt(action))
            }
        },
        iapStore: { [unowned store] (action: IAPAction) -> Effect<Never> in
            .fireAndForget {
                store.send(.iap(action))
            }
        },
        subscriptionStore: { [unowned store] (action: SubscriptionAction) -> Effect<Never> in
            .fireAndForget {
                store.send(.subscription(action))
            }
        },
        subscriptionAuthStateStore: { [unowned store] (action: SubscriptionAuthStateAction)
            -> Effect<Never> in
            .fireAndForget {
                store.send(.subscriptionAuthStateAction(action))
            }
        },
        vpnStartCondition: { [unowned store] () -> Bool in
            return !store.value.appDelegateState.adPresentationState
        },
        dateCompare: dateCompare,
        mainDispatcher: mainDispatcher,
        globalDispatcher: globalDispatcher
    )
    
    let cleanup = { [paymentTransactionDelegate] in
        SKPaymentQueue.default().remove(paymentTransactionDelegate)
    }
    
    return (environment: environment, cleanup: cleanup)
}

fileprivate func toPsiCashEnvironment(env: AppEnvironment) -> PsiCashEnvironment {
    return PsiCashEnvironment(
        feedbackLogger: env.feedbackLogger,
        psiCashFileStoreRoot: env.psiCashFileStoreRoot,
        psiCashEffects: env.psiCashEffects,
        sharedDB: env.sharedDB,
        psiCashPersistedValues: env.userConfigs,
        notifier: env.notifier,
        vpnActionStore: env.vpnActionStore,
        objcBridgeDelegate: env.objcBridgeDelegate,
        rewardedVideoAdBridgeDelegate: env.rewardedVideoAdBridgeDelegate,
        metadata: env.clientMetaData
    )
}

fileprivate func toLandingPageEnvironment(env: AppEnvironment) -> LandingPageEnvironment {
    LandingPageEnvironment(
        feedbackLogger: env.feedbackLogger,
        sharedDB: env.sharedDB,
        urlHandler: env.urlHandler,
        psiCashEffects: env.psiCashEffects,
        psiCashAccountTypeSignal: env.psiCashAccountTypeSignal,
        mainDispatcher: env.mainDispatcher
    )
}

fileprivate func toIAPReducerEnvironment(env: AppEnvironment) -> IAPEnvironment {
    IAPEnvironment(
        feedbackLogger: env.feedbackLogger,
        tunnelStatusSignal: env.tunnelStatusSignal,
        tunnelConnectionRefSignal: env.tunnelConnectionRefSignal,
        psiCashEffects: env.psiCashEffects,
        clientMetaData: env.clientMetaData,
        paymentQueue: env.paymentQueue,
        psiCashPersistedValues: env.userConfigs,
        isSupportedProduct: env.supportedAppStoreProducts.isSupportedProduct(_:),
        psiCashStore: env.psiCashStore,
        appReceiptStore: env.appReceiptStore,
        httpClient: env.httpClient,
        getCurrentTime: env.dateCompare.getCurrentTime
    )
}

fileprivate func toReceiptReducerEnvironment(env: AppEnvironment) -> ReceiptReducerEnvironment {
    ReceiptReducerEnvironment(
        feedbackLogger: env.feedbackLogger,
        appBundle: env.appBundle,
        iapStore: env.iapStore,
        subscriptionStore: env.subscriptionStore,
        subscriptionAuthStateStore: env.subscriptionAuthStateStore,
        receiptRefreshRequestDelegate: env.receiptRefreshRequestDelegate,
        isSupportedProduct: env.supportedAppStoreProducts.isSupportedProduct(_:),
        dateCompare: env.dateCompare
    )
}

fileprivate func toSubscriptionReducerEnvironment(
    env: AppEnvironment
) -> SubscriptionReducerEnvironment {
    SubscriptionReducerEnvironment(
        feedbackLogger: env.feedbackLogger,
        appReceiptStore: env.appReceiptStore,
        dateCompare: env.dateCompare,
        singleFireTimer: singleFireTimer
    )
}

/// - Note: This function delivers its events on the main dispatch queue.
/// - Important: Sub-millisecond precision is lost in the current implementation.
fileprivate func singleFireTimer(interval: TimeInterval,
                                 leeway: DispatchTimeInterval) -> Effect<()> {
    SignalProducer.timer(interval: DispatchTimeInterval.milliseconds(Int(interval * 1000)),
                         on: QueueScheduler.main,
                         leeway: leeway)
        .map(value: ())
        .take(first: 1)
}

fileprivate func toSubscriptionAuthStateReducerEnvironment(
    env: AppEnvironment
) -> SubscriptionAuthStateReducerEnvironment {
    SubscriptionAuthStateReducerEnvironment(
        feedbackLogger: env.feedbackLogger,
        httpClient: env.httpClient,
        httpRequestRetryCount: 5,
        httpRequestRetryInterval: DispatchTimeInterval.seconds(1),
        notifier: env.notifier,
        notifierUpdatedSubscriptionAuthsMessage: NotifierUpdatedSubscriptionAuths,
        sharedDB: SharedDBContainerObjC(sharedDB:env.sharedDB),
        tunnelStatusSignal: env.tunnelStatusSignal,
        tunnelConnectionRefSignal: env.tunnelConnectionRefSignal,
        clientMetaData: env.clientMetaData,
        dateCompare: env.dateCompare
    )
}

fileprivate func toRequestDelegateReducerEnvironment(
    env: AppEnvironment
) -> ProductRequestEnvironment {
    ProductRequestEnvironment(
        feedbackLogger: env.feedbackLogger,
        productRequestDelegate: env.productRequestDelegate,
        supportedAppStoreProducts: env.supportedAppStoreProducts
    )
}

fileprivate func toAppDelegateReducerEnvironment(env: AppEnvironment) -> AppDelegateEnvironment {
    AppDelegateEnvironment(
        feedbackLogger: env.feedbackLogger,
        sharedDB: env.sharedDB,
        psiCashEffects: env.psiCashEffects,
        paymentQueue: env.paymentQueue,
        appReceiptStore: env.appReceiptStore,
        paymentTransactionDelegate: env.paymentTransactionDelegate,
        mainDispatcher: env.mainDispatcher
    )
}

fileprivate func toVPNReducerEnvironment(env: AppEnvironment) -> VPNReducerEnvironment<PsiphonTPM> {
    VPNReducerEnvironment(
        feedbackLogger: env.feedbackLogger,
        sharedDB: env.sharedDB,
        vpnStartCondition: env.vpnStartCondition,
        vpnConnectionObserver: env.vpnConnectionObserver,
        internetReachability: env.internetReachability
    )
}

func makeAppReducer(
    feedbackLogger: FeedbackLogger
) -> Reducer<AppState, AppAction, AppEnvironment> {
    Reducer.combine(
        vpnStateReducer(feedbackLogger: feedbackLogger).pullback(
                 value: \.vpnReducerState,
                 action: \.vpnStateAction,
                 environment: toVPNReducerEnvironment(env:)),
        internetReachabilityReducer.pullback(
                 value: \.internetReachability,
                 action: \.reachabilityAction,
                 environment: erase),
        psiCashReducer.pullback(
                 value: \.psiCashReducerState,
                 action: \.psiCash,
                 environment: toPsiCashEnvironment(env:)),
        landingPageReducer.pullback(
                 value: \.landingPageReducerState,
                 action: \.landingPage,
                 environment: toLandingPageEnvironment(env:)),
        iapReducer.pullback(
                 value: \.iapReducerState,
                 action: \.inAppPurchase,
                 environment: toIAPReducerEnvironment(env:)),
        receiptReducer.pullback(
                 value: \.appReceipt,
                 action: \.appReceipt,
                 environment: toReceiptReducerEnvironment(env:)),
        subscriptionReducer.pullback(
                 value: \.subscription,
                 action: \.subscription,
                 environment: toSubscriptionReducerEnvironment(env:)),
        subscriptionAuthStateReducer.pullback(
                 value: \.subscriptionAuthReducerState,
                 action: \.subscriptionAuthStateAction,
                 environment: toSubscriptionAuthStateReducerEnvironment(env:)),
        productRequestReducer.pullback(
                 value: \.products,
                 action: \.productRequest,
                 environment: toRequestDelegateReducerEnvironment(env:)),
        appDelegateReducer.pullback(
                 value: \.appDelegateState,
                 action: \.appDelegateAction,
                 environment: toAppDelegateReducerEnvironment(env:))
    )
}

// MARK: Store

extension Store where Value == AppState, Action == AppAction {
    
    /// Convenience send function that wraps given `VPNPublicAction` into `AppAction`.
    func send(vpnAction: VPNPublicAction) {
        self.send(.vpnStateAction(.action(.public(vpnAction))))
    }
    
}

// MARK: AppInfoProvider

struct AppInfoObjC: AppInfoProvider {
    var clientPlatform: String {
        AppInfo.clientPlatform()
    }
    var clientRegion: String {
        AppInfo.clientRegion() ?? ""
    }
    var clientVersion: String {
        AppInfo.appVersion()
    }
    var propagationChannelId: String {
        AppInfo.propagationChannelId() ?? ""
    }
    var sponsorId: String {
        AppInfo.sponsorId() ?? ""
    }
}
