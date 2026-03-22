# Nucleus App Store Submission

Last updated: 2026-03-22

This checklist is for submitting the iOS app `Nucleus` to App Store Connect.

## Current build identity

- App name: `Nucleus`
- Bundle ID: `com.zhiwenwang.nucleus`
- Widget bundle ID: `com.zhiwenwang.nucleus.widgets`
- Marketing version: `0.1.0`
- Build number: `1`
- Privacy policy URL: `https://zish-rob-crur.com/nucleus/privacy/`
- Suggested support URL for first submission: `https://zish-rob-crur.com/nucleus/privacy/`

The support URL is required to lead to contact information. The current privacy page includes a support email, so it is acceptable as a first pass if you do not publish a separate support page yet.

## Engineering status

Already verified locally:

- `xcodebuild -project apps/ios/Nucleus/Nucleus.xcodeproj -scheme Nucleus -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build`
- `xcodebuild -project apps/ios/Nucleus/Nucleus.xcodeproj -scheme Nucleus -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO archive -archivePath /tmp/Nucleus.appstorecheck.xcarchive`

Known non-blocking issue:

- `apps/ios/Nucleus/Nucleus/HealthCollector.swift` still has one deprecated API warning for `totalEnergyBurned`.

## Submission checklist

### 1. App record

Create or confirm the App Store Connect record with:

- Name: `Nucleus`
- Platform: `iOS`
- Bundle ID: `com.zhiwenwang.nucleus`
- SKU: choose an internal stable value, for example `nucleus-ios-001`
- Primary language: `English (U.S.)`

### 2. App information

Fill these fields:

- Privacy Policy URL: `https://zish-rob-crur.com/nucleus/privacy/`
- Age Rating: complete in App Store Connect
- Primary Category: recommended `Health & Fitness`
- Secondary Category: recommended `Utilities`

### 3. iOS version information

Required fields:

- Screenshots
- Description
- Keywords
- Support URL
- Copyright

Optional but recommended:

- Subtitle
- Promotional Text
- Marketing URL

Recommended values:

- Subtitle: `Local-first health exports`
- Promotional Text:
  `Export Health data into private local files, with optional S3-compatible uploads and lightweight background refresh.`
- Keywords:
  `health,healthkit,export,sync,backup,s3,privacy,local`
- Copyright:
  `2026 Zhiwen Wang`

Suggested description:

`Nucleus is a local-first personal data exporter for Apple Health.`

`With your permission, it reads HealthKit data, builds stable daily exports, and keeps the default product path private. If you want off-device access, you can configure your own S3-compatible bucket for upload.`

`Nucleus is designed for people who want durable files, predictable export structure, and lightweight background refresh instead of an account-based sync service.`

### 4. App Review information

Fill these fields:

- Contact name
- Contact email
- Contact phone number
- Sign-in required: `No`
- Notes

Suggested review notes:

`Nucleus is a local-first Health export utility.`

`The app does not require account creation or login.`

`It requests read-only HealthKit access in order to export daily summaries and raw health files.`

`By default, exports remain in Nucleus private app storage.`

`Optional S3-compatible uploads are user-configured and can be ignored during review.`

`The app does not sync personal health information to iCloud. This product path was removed to comply with App Review Guideline 5.1.3(ii).`

`Home screen widgets and Live Activities reflect recent sync status only. Background refresh is best-effort and used to keep incremental sync current.`

### 5. App Privacy

Important Apple definition:

- Data processed only on device is not considered "collected".
- "Collect" means transmitting data off device in a way that allows you or your third-party partners to access it for longer than what is necessary to service the request in real time.

Recommended answer for the current shipping design:

- `No, we do not collect data from this app`

This recommendation is based on the current implementation and should be used only if the following remain true:

- No developer-operated server receives user data
- No analytics SDK is integrated
- No advertising SDK is integrated
- Optional uploads go directly to the user-configured S3-compatible bucket, not to infrastructure controlled by the app developer

If any of those assumptions change, re-answer App Privacy before submission.

### 6. Export compliance

Nucleus uses encryption-related APIs and standard cryptographic functionality:

- `CryptoKit`
- HTTPS networking
- SigV4 request signing for optional object-store uploads

The shipping app now sets `ITSAppUsesNonExemptEncryption = NO` in the app and widget `Info.plist` files because the current implementation relies on exempt encryption paths and Apple-provided cryptography.

Current recommendation:

- Treat this as a standard export-compliance review item, not a reason to block submission preparation
- If App Store Connect still asks follow-up questions, answer them consistently with the shipped behavior: no proprietary cryptography, no custom non-standard algorithms, and no developer-operated encryption service

## Product positioning to keep consistent

Use the same language everywhere:

- local-first
- private by default
- no account required
- HealthKit read-only export
- optional S3-compatible uploads

Do not describe the shipping app as:

- iCloud sync for health data
- cloud backup by default
- account-based sync

## Final pre-submit pass

Before clicking `Submit for Review`:

1. Upload a signed Release build to App Store Connect.
2. Install the TestFlight build on a real device.
3. Verify Health permission flow.
4. Verify first sync.
5. Verify widget rendering on device.
6. Verify Live Activity behavior on device.
7. Verify optional S3 upload still works in the signed build.
8. Re-read the App Privacy answers against the exact shipped behavior.

## Apple references

- App information:
  https://developer.apple.com/help/app-store-connect/reference/app-information/app-information
- Platform version information:
  https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information
- Manage app privacy:
  https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy
- App Privacy Details:
  https://developer.apple.com/app-store/app-privacy-details/
- Export compliance:
  https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance
- App Review Guidelines:
  https://developer.apple.com/app-store/review/guidelines/
