# App Store Update Package

Last updated: 2026-06-22

This folder contains copy-ready material for the next App Store update after removing email/password account management.

## Files

- `app-privacy-ja.md`: App Store Connect App Privacy answers and privacy-policy update notes.
- `app-store-metadata-ja.md`: Japanese App Store metadata, ASO keyword plan, and optional English localization.
- `release-submission-checklist.md`: End-to-end update submission checklist and reviewer note.
- `privacy-policy-ja.md`: Draft privacy policy text to publish at the existing in-app URL.
- `github-pages/`: Static HTML pages ready to publish to GitHub Pages.
- `fastlane/metadata/ja-JP/`: Copy-ready App Store metadata files compatible with a fastlane-style metadata layout.
- `../docs/`: GitHub Pages-ready copy placed at the repository root.

## Implementation Already Applied

- The app no longer collects email addresses for account creation or sign-in.
- The app starts with an anonymous app-specific Supabase account and a user-entered display name.
- The old password recovery and email sign-in UI have been removed.
- The iOS home screen display name and primary in-app brand text now use `買い物リマインダー`.
- Supabase FK performance indexes were applied to production.
- Supabase Edge Functions now support `SUPABASE_SECRET_KEYS.default` with legacy service-role fallback.

## Manual Publishing Targets

- Publish `privacy-policy-ja.md` to the URL used in the app:
  `https://kazumaru731.github.io/Shopping-Reminder/privacy`
- Or publish the static files under `github-pages/` to the GitHub Pages root so these paths work:
  - `https://kazumaru731.github.io/Shopping-Reminder/privacy`
  - `https://kazumaru731.github.io/Shopping-Reminder/terms`
  - `https://kazumaru731.github.io/Shopping-Reminder/support`
- The same static pages have also been copied to the repository-level `docs/` folder for GitHub Pages branch publishing.
- Update App Store Connect metadata using `app-store-metadata-ja.md`.
- Update App Store Connect App Privacy using `app-privacy-ja.md`.
- Add the reviewer note from `release-submission-checklist.md` when submitting the build.

## Suggested GitHub Pages Publish Layout

If the repository uses a `docs/` folder for GitHub Pages, copy:

- `github-pages/privacy/` to `docs/privacy/`
- `github-pages/terms/` to `docs/terms/`
- `github-pages/support/` to `docs/support/`

If the repository publishes from the root, copy the same three folders to the repository root.
