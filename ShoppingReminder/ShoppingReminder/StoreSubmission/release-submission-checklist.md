# Release Submission Checklist

Last updated: 2026-06-22

## Local Readiness

- [x] Email/password account flow removed from app UI.
- [x] Anonymous app-specific account flow implemented.
- [x] Legacy email-auth accounts and related app data deleted from Supabase.
- [x] App display name changed to `買い物リマインダー`.
- [x] Privacy manifests added for the app and widget UserDefaults usage.
- [x] Build number incremented from `2` to `3`.
- [x] Static GitHub Pages files prepared under `StoreSubmission/github-pages/`.
- [x] Static GitHub Pages files copied to repository-root `docs/`.
- [x] App Store metadata text files prepared under `StoreSubmission/fastlane/metadata/ja-JP/`.
- [x] Supabase FK performance indexes added and applied to production.
- [x] Supabase Edge Functions deployed with `SUPABASE_SECRET_KEYS` support and `SUPABASE_SERVICE_ROLE_KEY` fallback.
- [x] Live anonymous sign-up to account deletion smoke test completed; test data removed.
- [ ] Rebuild archive for App Store distribution.
- [ ] Run a clean install smoke test on a physical device or TestFlight.
- [ ] Confirm account deletion works in the submitted build.
- [ ] Confirm push notification registration still works after anonymous account creation.
- [ ] Confirm item image upload/delete works.

## App Store Connect Updates

- [ ] Update app name to `買い物リマインダー リスト共有`.
- [ ] Update subtitle to `家族で買い忘れを防ぐ`.
- [ ] Update keywords using `fastlane/metadata/ja-JP/keywords.txt`.
- [ ] Update description using `fastlane/metadata/ja-JP/description.txt`.
- [ ] Update promotional text using `fastlane/metadata/ja-JP/promotional_text.txt`.
- [ ] Update `What's New` using `fastlane/metadata/ja-JP/release_notes.txt`.
- [ ] Upload screenshots in the recommended order.
- [ ] Confirm support URL still works:
  `https://kazumaru731.github.io/Shopping-Reminder/support`
- [ ] Publish `StoreSubmission/github-pages/` and confirm privacy policy URL:
  `https://kazumaru731.github.io/Shopping-Reminder/privacy`
- [ ] Confirm terms URL:
  `https://kazumaru731.github.io/Shopping-Reminder/terms`
- [ ] Confirm support URL:
  `https://kazumaru731.github.io/Shopping-Reminder/support`
- [ ] Update App Privacy answers using `app-privacy-ja.md`.

## App Review Note

Copy this into App Review notes:

```text
This update removes email/password account management. Users now start with an app-specific anonymous account and a display name only. The app no longer collects email addresses for account registration, sign-in, or password reset.

Existing legacy email-auth accounts and their related app data were removed from the backend before this update. Account deletion is available in Settings and deletes the app account and related app data through a backend deletion function.

No advertising SDK, third-party analytics SDK, IDFA access, or cross-app tracking is included in this version.
```

Japanese reference:

```text
本アップデートでは、メールアドレス/パスワードによるアカウント管理を廃止し、表示名のみで開始できるアプリ専用匿名アカウントへ変更しました。メールアドレスは登録、ログイン、パスワードリセットのいずれにも使用していません。

旧メール認証アカウントと関連データは、アップデート前にバックエンドから削除済みです。設定画面のアカウント削除から、アプリ専用アカウントと関連データを削除できます。

このバージョンには広告 SDK、第三者分析 SDK、IDFA 使用、クロスアプリトラッキングは含まれていません。
```

## Versioning

Recommended next build:

- Marketing version: keep `1.0` if this is pre-release / unreleased.
- Build number: `3`.

If version `1.0` is already live, use:

- Marketing version: `1.1`
- Build number: next available build number.

## Manual Work Required From Account Owner

These cannot be completed from the local repository without App Store Connect / Apple Developer account access:

- Update App Privacy answers in App Store Connect.
- Update app name, subtitle, keywords, description, promotional text, and screenshots in App Store Connect.
- Upload the archive or select the CI/TestFlight build.
- Answer export compliance, content rights, age rating, and review contact fields.
- Submit the version for App Review.
- Publish the privacy policy to the public GitHub Pages URL.
- In Supabase Dashboard, confirm no clients use legacy `anon` / `service_role` keys, then deactivate them if safe.
- In Supabase Dashboard, migrate JWT signing keys away from the legacy JWT secret if not already done.
- Rotate any remaining Supabase service/JWT keys from the Supabase Dashboard if not already done.

## Future Premium / Ads Gate

Do not add premium, subscriptions, or ads to App Store Connect until the corresponding app implementation exists.

Before a premium release:

- Add StoreKit implementation.
- Add restore purchases.
- Add entitlement validation.
- Update privacy policy and App Privacy `Purchases`.
- Add in-app purchase metadata.

Before an ads release:

- Choose contextual vs tracking ads.
- Review the ad SDK privacy manifest and data collection list.
- Add ATT only if tracking is present.
- Update App Privacy and privacy policy before submitting.
