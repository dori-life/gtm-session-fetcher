/* Copyright 2026 Google Inc. All rights reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

// Mori fork: tests for +[GTMSessionFetcher setGlobalSessionConfigurationPolicy:].

#import <TargetConditionals.h>

#if !TARGET_OS_WATCH

#if !defined(__has_feature) || !__has_feature(objc_arc)
#error "This file requires ARC support."
#endif

#import "GTMSessionFetcherFetchingTest.h"
#import "GTMSessionFetcherService+Internal.h"

static NSString *const kPolicyHeaderName = @"X-Mori-Policy";

@interface GTMSessionFetcher (SessionConfigurationPolicyTesting)
+ (NSMapTable *)sessionIdentifierToFetcherMap;
@end

@interface GTMSessionFetcherSessionConfigurationPolicyTest : GTMSessionFetcherBaseTest
@end

@implementation GTMSessionFetcherSessionConfigurationPolicyTest

- (void)setUp {
  [GTMSessionFetcher setGlobalSessionConfigurationPolicy:nil];
  [super setUp];
}

- (void)tearDown {
  [GTMSessionFetcher setGlobalSessionConfigurationPolicy:nil];
  [super tearDown];
}

#pragma mark - Helpers

// Begins the fetch, waits for its completion, then keeps the run loop going briefly so a second
// (erroneous) completion would be observed. Returns the error passed to the single completion.
- (nullable NSError *)fetchExpectingSingleCompletion:(GTMSessionFetcher *)fetcher
                                                data:(NSData *_Nullable *_Nullable)outData {
  __block NSUInteger completionCount = 0;
  __block NSError *completionError;
  __block NSData *completionData;
  XCTestExpectation *completed = [self expectationWithDescription:@"completion"];
  completed.assertForOverFulfill = YES;
  [fetcher beginFetchWithCompletionHandler:^(NSData *_Nullable data, NSError *_Nullable error) {
    completionCount++;
    completionData = data;
    completionError = error;
    [completed fulfill];
  }];
  [self waitForExpectations:@[ completed ] timeout:_timeoutInterval];
  [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.3]];
  XCTAssertEqual(completionCount, 1U);
  if (outData) *outData = completionData;
  return completionError;
}

- (void)assertRejectionError:(nullable NSError *)error {
  XCTAssertNotNil(error);
  XCTAssertEqualObjects(error.domain, kGTMSessionFetcherErrorDomain);
  XCTAssertEqual(error.code, GTMSessionFetcherErrorSessionConfigurationRejected);
}

#pragma mark - No policy

- (void)testNoPolicyUsesUpstreamPath {
  if (!_isServerRunning) return;

  GTMSessionFetcher *fetcher =
      [self fetcherWithURLString:[self localURLStringToTestFileName:kGTMGettysburgFileName]];
  NSData *data;
  NSError *error = [self fetchExpectingSingleCompletion:fetcher data:&data];
  XCTAssertNil(error);
  XCTAssertEqualObjects(data, [self gettysburgAddress]);
  XCTAssertNotNil([_fetcherService session]);
  XCTAssertNil([_fetcherService session].configuration.HTTPAdditionalHeaders[kPolicyHeaderName]);
}

#pragma mark - Policy returns YES

- (void)testAcceptingPolicyConfiguresSharedSessionAndIsNotReconsultedOnReuse {
  if (!_isServerRunning) return;

  __block NSUInteger policyCallCount = 0;
  __block NSTimeInterval requestTimeoutSeenByPolicy = 0;
  [GTMSessionFetcher setGlobalSessionConfigurationPolicy:^BOOL(
                         NSURLSessionConfiguration *configuration) {
    policyCallCount++;
    requestTimeoutSeenByPolicy = configuration.timeoutIntervalForRequest;
    configuration.HTTPAdditionalHeaders = @{kPolicyHeaderName : @"1"};
    configuration.timeoutIntervalForResource = 123;
    return YES;
  }];

  NSString *urlString = [self localURLStringToTestFileName:kGTMGettysburgFileName];
  GTMSessionFetcher *fetcher = [self fetcherWithURLString:urlString];
  // The policy runs after the configuration block.
  fetcher.configurationBlock = ^(GTMSessionFetcher *configFetcher,
                                 NSURLSessionConfiguration *configuration) {
    configuration.timeoutIntervalForRequest = 77;
  };
  NSData *data;
  NSError *error = [self fetchExpectingSingleCompletion:fetcher data:&data];
  XCTAssertNil(error);
  XCTAssertEqualObjects(data, [self gettysburgAddress]);
  XCTAssertEqual(policyCallCount, 1U);
  XCTAssertEqual(requestTimeoutSeenByPolicy, 77);

  NSURLSession *sharedSession = [_fetcherService session];
  XCTAssertNotNil(sharedSession);
  XCTAssertEqualObjects(sharedSession.configuration.HTTPAdditionalHeaders[kPolicyHeaderName], @"1");
  XCTAssertEqual(sharedSession.configuration.timeoutIntervalForResource, 123);
  XCTAssertEqual(sharedSession.configuration.timeoutIntervalForRequest, 77);

  // A second fetcher reuses the service's existing shared session; the policy is not consulted.
  GTMSessionFetcher *secondFetcher = [self fetcherWithURLString:urlString];
  error = [self fetchExpectingSingleCompletion:secondFetcher data:&data];
  XCTAssertNil(error);
  XCTAssertEqualObjects(data, [self gettysburgAddress]);
  XCTAssertEqual(policyCallCount, 1U);
  XCTAssertEqual([_fetcherService session], sharedSession);
}

- (void)testAcceptingPolicyConfiguresNonSharedSession {
  if (!_isServerRunning) return;
  _fetcherService = nil;

  __block NSURLSessionConfiguration *configurationSeenByPolicy;
  [GTMSessionFetcher setGlobalSessionConfigurationPolicy:^BOOL(
                         NSURLSessionConfiguration *configuration) {
    configurationSeenByPolicy = configuration;
    configuration.HTTPAdditionalHeaders = @{kPolicyHeaderName : @"1"};
    return YES;
  }];

  GTMSessionFetcher *fetcher =
      [self fetcherWithURLString:[self localURLStringToTestFileName:kGTMGettysburgFileName]];
  // A non-shared session is released before completion, so capture it while the task is live.
  __block NSURLSession *sessionDuringFetch;
  fetcher.didReceiveResponseBlock =
      ^(NSURLResponse *response,
        GTMSessionFetcherDidReceiveResponseDispositionBlock dispositionBlock) {
        sessionDuringFetch = fetcher.session;
        dispositionBlock(NSURLSessionResponseAllow);
      };
  NSData *data;
  NSError *error = [self fetchExpectingSingleCompletion:fetcher data:&data];
  XCTAssertNil(error);
  XCTAssertEqualObjects(data, [self gettysburgAddress]);
  XCTAssertNotNil(configurationSeenByPolicy);
  XCTAssertNotNil(sessionDuringFetch);
  XCTAssertEqualObjects(sessionDuringFetch.configuration.HTTPAdditionalHeaders[kPolicyHeaderName],
                        @"1");
}

#pragma mark - Policy returns NO

- (void)testRejectingPolicyFailsOrdinaryFetch {
  if (!_isServerRunning) return;
  _fetcherService = nil;

  __block NSUInteger policyCallCount = 0;
  [GTMSessionFetcher setGlobalSessionConfigurationPolicy:^BOOL(
                         NSURLSessionConfiguration *configuration) {
    policyCallCount++;
    return NO;
  }];

  GTMSessionFetcher *fetcher =
      [self fetcherWithURLString:[self localURLStringToTestFileName:kGTMGettysburgFileName]];
  NSError *error = [self fetchExpectingSingleCompletion:fetcher data:NULL];
  [self assertRejectionError:error];
  XCTAssertEqual(policyCallCount, 1U);
  XCTAssertNil(fetcher.session);
  XCTAssertFalse(fetcher.isFetching);
}

- (void)testRejectingPolicyFailsBackgroundFetchAndRemovesMapping {
  if (!_isServerRunning) return;
  _fetcherService = nil;

  __block NSString *backgroundIdentifier;
  [GTMSessionFetcher setGlobalSessionConfigurationPolicy:^BOOL(
                         NSURLSessionConfiguration *configuration) {
    backgroundIdentifier = configuration.identifier;
    // The mapping exists while the policy runs; it must be gone after the rejection.
    XCTAssertNotNil(
        [[GTMSessionFetcher sessionIdentifierToFetcherMap] objectForKey:configuration.identifier]);
    return NO;
  }];

  GTMSessionFetcher *fetcher =
      [self fetcherWithURLString:[self localURLStringToTestFileName:kGTMGettysburgFileName]];
  fetcher.useBackgroundSession = YES;
  NSError *error = [self fetchExpectingSingleCompletion:fetcher data:NULL];
  [self assertRejectionError:error];
  XCTAssertNotNil(backgroundIdentifier);
  XCTAssertNil([[GTMSessionFetcher sessionIdentifierToFetcherMap] objectForKey:backgroundIdentifier]);
  XCTAssertNil(fetcher.sessionIdentifier);
  XCTAssertNil(fetcher.session);
}

- (void)testRejectingPolicyFailsColdRestoredBackgroundFetch {
  if (!_isServerRunning) return;
  _fetcherService = nil;

  NSString *identifier =
      [NSString stringWithFormat:@"com.google.GTMSessionFetcher_%@", [NSUUID UUID].UUIDString];

  __block NSString *configurationIdentifier;
  [GTMSessionFetcher setGlobalSessionConfigurationPolicy:^BOOL(
                         NSURLSessionConfiguration *configuration) {
    configurationIdentifier = configuration.identifier;
    return NO;
  }];

  // Simulates a relaunch: the fetcher is re-created from a persisted session identifier.
  GTMSessionFetcher *fetcher = [GTMSessionFetcher fetcherWithSessionIdentifier:identifier];
  XCTAssertNotNil(fetcher);
  XCTAssertEqual([[GTMSessionFetcher sessionIdentifierToFetcherMap] objectForKey:identifier],
                 fetcher);

#if TARGET_OS_IPHONE
  __block NSUInteger systemCompletionCount = 0;
  XCTestExpectation *systemCompleted = [self expectationWithDescription:@"system completion"];
  systemCompleted.assertForOverFulfill = YES;
  fetcher.systemCompletionHandler = ^{
    XCTAssertTrue([NSThread isMainThread]);
    systemCompletionCount++;
    [systemCompleted fulfill];
  };
#endif

  NSError *error = [self fetchExpectingSingleCompletion:fetcher data:NULL];
  [self assertRejectionError:error];
  XCTAssertEqualObjects(configurationIdentifier, identifier);
  XCTAssertNil([[GTMSessionFetcher sessionIdentifierToFetcherMap] objectForKey:identifier]);
  XCTAssertNil(fetcher.sessionIdentifier);
  XCTAssertNil(fetcher.session);

#if TARGET_OS_IPHONE
  [self waitForExpectations:@[ systemCompleted ] timeout:_timeoutInterval];
  XCTAssertEqual(systemCompletionCount, 1U);
  XCTAssertNil([GTMSessionFetcher systemCompletionHandlerForSessionIdentifier:identifier]);
#endif
}

- (void)testRejectingPolicyFailsSharedServiceFirstSessionCreation {
  if (!_isServerRunning) return;

  __block BOOL accept = NO;
  __block NSUInteger policyCallCount = 0;
  [GTMSessionFetcher setGlobalSessionConfigurationPolicy:^BOOL(
                         NSURLSessionConfiguration *configuration) {
    policyCallCount++;
    return accept;
  }];

  NSString *urlString = [self localURLStringToTestFileName:kGTMGettysburgFileName];
  GTMSessionFetcher *fetcher = [self fetcherWithURLString:urlString];
  NSError *error = [self fetchExpectingSingleCompletion:fetcher data:NULL];
  [self assertRejectionError:error];
  XCTAssertEqual(policyCallCount, 1U);
  XCTAssertNil([_fetcherService session]);
  XCTAssertFalse(fetcher.isFetching);
  XCTAssertEqual(_fetcherService.runningFetchersByHost.count, 0U);

  // The refusal leaves no broken shared state: a later fetch creates the shared session normally.
  accept = YES;
  GTMSessionFetcher *secondFetcher = [self fetcherWithURLString:urlString];
  NSData *data;
  error = [self fetchExpectingSingleCompletion:secondFetcher data:&data];
  XCTAssertNil(error);
  XCTAssertEqualObjects(data, [self gettysburgAddress]);
  XCTAssertEqual(policyCallCount, 2U);
  XCTAssertNotNil([_fetcherService session]);
}

@end

#endif  // !TARGET_OS_WATCH
