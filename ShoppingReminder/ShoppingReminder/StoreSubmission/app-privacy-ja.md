# App Privacy Update Notes

Last updated: 2026-06-22

## Basis

Apple requires App Privacy information for new apps and app updates. The product page disclosure must cover the app and third-party code included in the app. Source: https://developer.apple.com/app-store/user-privacy-and-data-use/

This app currently uses:

- Supabase Auth, Database, Storage, Realtime, and Edge Functions.
- Apple Push Notification service through `UNUserNotificationCenter` / APNs.
- PhotosPicker for user-selected item images.
- No email/password authentication.
- No advertising SDK.
- No third-party analytics SDK.
- No AppTrackingTransparency / IDFA usage.
- No in-app purchase implementation yet.

## Supabase Operational Status

Checked on 2026-06-22:

- The iOS app uses the modern `sb_publishable_...` key.
- Supabase still reports an enabled legacy `anon` key. This is public/low-privilege, but should be deactivated from Dashboard after confirming no old clients depend on it.
- Edge Functions now prefer `SUPABASE_SECRET_KEYS.default` and fall back to `SUPABASE_SERVICE_ROLE_KEY`.
- Legacy email-auth users and their related app data have been deleted.
- A live anonymous account creation and account deletion smoke test passed, and the test account/data were removed.

## Recommended App Store Connect Answers

Use these as the baseline for the current app version.

### Tracking

- Does this app use data to track the user across apps and websites owned by other companies?
  - Recommended answer: `No`
- Is AppTrackingTransparency required in this version?
  - Recommended answer: `No`

Reason: the current code does not use IDFA, an ad attribution SDK, or a third-party analytics/ad SDK that combines app data with other companies' data.

### Data Collection

Recommended answer: `Yes, this app collects data`.

Do not claim `Data Not Collected`, because the app stores server-side account and list data for sync, sharing, push notifications, and deletion support.

### Data Types

#### Contact Info

- `Name`
  - What it means here: user-entered display name / nickname.
  - Linked to user: `Yes`
  - Used for tracking: `No`
  - Purpose: `App Functionality`
  - Notes: The app does not require a legal name. The UI should continue to call this `表示名`.

- `Email Address`
  - Recommended answer: `Not collected`
  - Reason: email sign-up/sign-in has been removed and legacy email users/data were deleted.

#### User Content

- `Photos or Videos`
  - What it means here: optional item photos selected by the user.
  - Linked to user: `Yes`
  - Used for tracking: `No`
  - Purpose: `App Functionality`

- `Other User Content`
  - What it means here: group names, list names, item names, item notes, reminder settings, product URLs, purchase/reservation state, and collaboration data.
  - Linked to user: `Yes`
  - Used for tracking: `No`
  - Purpose: `App Functionality`

#### Identifiers

- `User ID`
  - What it means here: app-specific anonymous Supabase user ID.
  - Linked to user: `Yes`
  - Used for tracking: `No`
  - Purpose: `App Functionality`

- `Device ID`
  - What it means here: APNs device token and app/device identifier used to deliver push notifications.
  - Linked to user: `Yes`
  - Used for tracking: `No`
  - Purpose: `App Functionality`

#### Diagnostics

- Recommended answer for this version: `Not collected by the app`
  - Reason: no crash reporting or diagnostics SDK is integrated in the current app code.

#### Usage Data

- Recommended answer for this version: `Not collected by the app`
  - Reason: no analytics SDK or product interaction tracking is integrated in the current app code.

#### Purchases

- Recommended answer for this version: `Not collected`
  - Reason: no StoreKit in-app purchase implementation exists yet.

When premium / in-app purchase is implemented, update this to include purchase data used for app functionality. If purchase status is synced to Supabase, treat it as linked to the app account.

## Future Ads / Premium Decision Rules

Before adding ads:

- Contextual ads without cross-app tracking may avoid ATT, but the ad SDK's own data collection still must be disclosed.
- Targeted ads, retargeting, ad attribution, IDFA access, or SDKs that combine app data with third-party data require ATT and App Privacy tracking disclosures.
- Re-check each SDK's privacy manifest and data collection documentation before release.

Before adding premium / IAP:

- Add StoreKit purchase data to the privacy policy.
- Update App Privacy `Purchases` if purchase history or entitlement state is collected or linked.
- Explain restore purchases and premium entitlement behavior in App Review notes.

## Privacy Policy Changes To Publish

Publish `privacy-policy-ja.md` to the current app link:

`https://kazumaru731.github.io/Shopping-Reminder/privacy`

Required changes from the old email-auth version:

- Remove statements saying email address is collected for account registration or password reset.
- State that the app uses an app-specific anonymous account.
- State that the app collects a display name, app content, item images, notification tokens, and technical server logs for app functionality.
- State that account deletion deletes the app account and related app data.
- State that the app does not use data for tracking in the current version.
- Add future-change language for paid plans, in-app purchases, and ads only when those features are implemented.
