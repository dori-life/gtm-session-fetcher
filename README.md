# Mori fork

This is a fork of upstream gtm-session-fetcher **v4.5.0**
(`c756a29784521063b6a1202907e2cc47f41b667c`). The only difference is one process-wide hook for
the `NSURLSessionConfiguration` of every session the fetcher creates:

```objc
typedef BOOL (^GTMSessionFetcherSessionConfigurationPolicy)(NSURLSessionConfiguration *configuration);
+ [GTMSessionFetcher setGlobalSessionConfigurationPolicy:(nullable GTMSessionFetcherSessionConfigurationPolicy)policy];
```

- **When it runs:** for every `NSURLSession` GTMSessionFetcher creates after the call (ordinary,
  fetcher-service shared, background, and cold-restored background sessions), after the
  fetcher's/service's `configurationBlock` and right before the session is created. Sessions that
  already exist (including a service's shared session, which is reused without consulting the
  policy) are not reconfigured, so install it once before any fetcher or service is used.
- **Returning NO:** no session is created; the fetch completes exactly once with
  `kGTMSessionFetcherErrorDomain` / `GTMSessionFetcherErrorSessionConfigurationRejected` (-8). For
  a background session, its identifier mapping and persisted entry are removed and any registered
  system completion handler is called once on the main queue.
- **Threading:** the block is copied, read under its own lock and invoked outside it; other GTM
  locks may be held, so the block must not call back into GTMSessionFetcher.
- **No policy installed (default):** behavior is identical to upstream v4.5.0.

Tests: `UnitTests/GTMSessionFetcherSessionConfigurationPolicyTest.m`.

---

# Google Toolbox for Mac - Session Fetcher

**Project site** <https://github.com/google/gtm-session-fetcher><br>
**Discussion group** <http://groups.google.com/group/google-toolbox-for-mac>

[![SwiftPM](https://github.com/google/gtm-session-fetcher/actions/workflows/swiftpm.yml/badge.svg?branch=main)](https://github.com/google/gtm-session-fetcher/actions/workflows/swiftpm.yml)
[![CocoaPods](https://github.com/google/gtm-session-fetcher/actions/workflows/cocoapods.yml/badge.svg?branch=main)](https://github.com/google/gtm-session-fetcher/actions/workflows/cocoapods.yml)

`GTMSessionFetcher` makes it easy for Cocoa applications to perform http
operations. The fetcher is implemented as a wrapper on `NSURLSession`, so its
behavior is asynchronous and uses operating-system settings.

Features include:
- Simple to build; only one source/header file pair is required
- Simple to use: takes just two lines of code to fetch a request
- Supports upload and download sessions
- Flexible cookie storage
- Automatic retry on errors, with exponential backoff
- Support for generating multipart MIME upload streams
- Easy, convenient logging of http requests and responses
- Supports plug-in authentication such as with GTMAppAuth
- Easily testable; self-mocking
- Automatic rate limiting when created by the `GTMSessionFetcherService` factory class
- Fully independent of other projects

**To get started** please read
[USING.md](USING.md)
for detailed information.
