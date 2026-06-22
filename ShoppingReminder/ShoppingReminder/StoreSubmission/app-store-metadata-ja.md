# App Store Metadata / ASO Plan

Last updated: 2026-06-22

Apple notes that app name, subtitle, screenshots, description, keywords, categories, ratings/reviews, localization, product page optimization, and custom product pages affect discovery and conversion. Source: https://developer.apple.com/app-store/product-page/

## Current Issue

The current public-facing name `ShoppingReminder` is easy to miss for Japanese users searching in Japanese. The app is a shopping-list reminder and collaboration tool, so Japanese metadata should use direct task words:

- 買い物
- リマインダー
- 買い物リスト
- 共有
- 家族
- 買い忘れ
- 通知
- チェックリスト

## Recommended Japanese Metadata

### App Name

Recommended:

`買い物リマインダー リスト共有`

Rationale:

- Stays under Apple's 30-character app-name limit.
- Includes the strongest search phrase `買い物リマインダー`.
- Adds the clear differentiator `リスト共有`.

Fallback if App Store Connect rejects the name as too generic or unavailable:

`買い物リマインダー 共有メモ`

The iOS home screen display name has already been changed in the Xcode project to:

`買い物リマインダー`

### Subtitle

Recommended:

`家族で買い忘れを防ぐ`

Rationale:

- Under Apple's 30-character subtitle limit.
- Adds `家族` and `買い忘れ`, which are not both in the app name.
- Communicates the benefit rather than repeating the name.

Alternative:

`共有できる買い物リスト`

### Promotional Text

Recommended:

`メールアドレス不要で始められる、家族や同居人向けの買い物リスト。通知と共有で買い忘れを防げます。`

Notes:

- Promotional text does not affect search ranking, but it can be updated without a new app version.
- Use it to explain the privacy/account change and the practical benefit.

### Keywords

Recommended 100-character field:

`チェックリスト,買い忘れ,通知,日用品,食材,スーパー,メモ,共有リスト,家族共有,共同編集,買うもの,在庫,期限,買物`

Notes:

- Separate terms with commas and no spaces.
- Avoid competitor names and trademarked terms.
- Avoid duplicating obvious words already used in the app name/subtitle unless testing shows a benefit.

### Category

Recommended:

- Primary: `Productivity`
- Secondary: `Lifestyle` or `Utilities`

Rationale:

- The app is a recurring task/list utility, not an e-commerce app.
- `Productivity` is more aligned with reminders, lists, collaboration, and widgets.

### Description

Recommended:

```text
買い物リマインダーは、家族や同居人と買い物リストを共有し、買い忘れを防ぐためのアプリです。

メールアドレス不要で表示名だけですぐに始められます。グループごとにリストを作り、買うもの、メモ、リンク、写真、期限、通知をまとめて管理できます。

主な機能
・買い物リストをグループで共有
・アイテムごとのメモ、写真、商品リンク
・期限や曜日に合わせたリマインダー
・購入予定者や購入済み状態の共有
・ホーム画面ウィジェットでリストを確認
・アカウント削除によるデータ削除

買い物前の確認、日用品の補充、家族の買い出し分担に使いやすい、シンプルな共有リストです。
```

### What's New

Recommended for the next update:

```text
メールアドレスでのログインを廃止し、表示名だけで始められるアプリ専用アカウントに変更しました。
プライバシーとセキュリティを見直し、アカウント削除時の関連データ削除を強化しました。
```

### Review Note

Use the copy in `release-submission-checklist.md`.

### Screenshot Order

Use screenshots that show real workflows, not only empty screens.

Recommended first 3 screenshots:

1. Group / shared shopping lists: emphasize `家族で共有`
2. Item list with reminders: emphasize `買い忘れ防止`
3. Item detail with photo/link/notes: emphasize `写真・メモ・リンク`

Current local screenshots:

- `AppStoreScreenshots/01-group-list.png`
- `AppStoreScreenshots/02-group-home.png`
- `AppStoreScreenshots/03-item-list.png`

Add captions in App Store Connect rather than baking long text into screenshots unless the screenshot set is redesigned.

## Optional English Localization

Only add this after the Japanese metadata is stable.

### App Name

`Shopping Reminder Shared List`

### Subtitle

`Never forget groceries`

### Keywords

`grocery,shopping,list,reminder,shared,family,checklist,household,items,notify,todo,pantry`

### Description Opening

```text
Shopping Reminder is a shared shopping list app for families, couples, and housemates who want to prevent forgotten groceries and household items.
```

## ASO Test Plan After Release

Track App Analytics weekly:

- App Store search impressions
- Product page views
- Conversion rate
- Search terms if available
- Screenshot tap-through / install behavior
- Reviews mentioning confusing wording

Iteration plan:

1. Release with Japanese metadata above.
2. After 2-4 weeks, compare search impressions and conversion.
3. Test subtitle variant: `共有できる買い物リスト`.
4. Test screenshot order if conversion is low.
5. Add custom product pages later for `家族共有`, `買い忘れ防止`, and `ウィジェット` angles.
