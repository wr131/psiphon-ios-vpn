/*
 * Copyright (c) 2018, Psiphon Inc.
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

#import <Foundation/Foundation.h>
#import <notify.h>

#if !(TARGET_IS_EXTENSION)
@class RACSignal<__covariant ValueType>;
#endif

NS_ASSUME_NONNULL_BEGIN

typedef NSString * NotifierMessage;

// Messages sent by the extension.
extern NotifierMessage const NotifierTunnelConnected;
extern NotifierMessage const NotifierAvailableEgressRegions;
extern NotifierMessage const NotifierNetworkConnectivityFailed;
/** Emitted only if network connectivity failed was previously posted. */
extern NotifierMessage const NotifierNetworkConnectivityResolved;
extern NotifierMessage const NotifierDisallowedTrafficAlert;
extern NotifierMessage const NotifierIsHostAppProcessRunning;
extern NotifierMessage const NotifierApplicationParametersUpdated;

// Messages sent by the container.
extern NotifierMessage const NotifierStartVPN;
extern NotifierMessage const NotifierAppEnteredBackground;
extern NotifierMessage const NotifierUpdatedAuthorizations;
extern NotifierMessage const NotifierHostAppProcessRunning;

// Messages allowed only in debug build.
#if DEBUG || DEV_RELEASE
extern NotifierMessage const NotifierDebugCustomFunction;
extern NotifierMessage const NotifierDebugForceJetsam;
extern NotifierMessage const NotifierDebugGoProfile;
extern NotifierMessage const NotifierDebugMemoryProfiler;
extern NotifierMessage const NotifierDebugPsiphonTunnelState;
#endif

#pragma mark - NotifierObserver

@protocol NotifierObserver <NSObject>

@required

- (void)onMessageReceived:(NotifierMessage)message;

@end

#pragma mark - Notifier

@interface Notifier : NSObject

+ (Notifier *)sharedInstance;

/**
 * If called from the container, posts the message to the network extension.
 * If called from the extension, posts the message to the container.
 *
 * @param message NotifierMessage of the message.
 *
 * @note This function is thread-safe.
 */
- (void)post:(NotifierMessage)message;

/**
 * Adds an observer to the Notifier.
 * Nothing happens, if the observer has already been registered.
 *
 * @param observer The observer to add to the observers' queue.
 * @param queue The dispatch queue tha the observer is called on.
 */
- (void)registerObserver:(id <NotifierObserver>)observer callbackQueue:(dispatch_queue_t)queue;

// Methods not available in the extension due to memory pressure.
#if !(TARGET_IS_EXTENSION)

/**
 * The returned signal delivers messages received by the Notifier if it matches
 * one of the `messages` provided.
 *
 * @scheduler listenForMessages: delivers its events on a background scheduler.
 */
- (RACSignal<NotifierMessage> *)listenForMessages:(NSArray<NotifierMessage> *)messages;

#endif

@end

NS_ASSUME_NONNULL_END
