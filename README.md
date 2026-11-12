# Cash Client (desktop)

Desktop app for the credit union's office staff. One app serves both
administrators and agents, with a shared layout and role-specific content. It
sits alongside the collector mobile app
([cash_client](https://github.com/Benney-Walker/cash_client)) and talks to the
[bankingbackend](https://github.com/Benney-Walker/bankingbackend) API.

Requirements live in the Penco project doc `CASH_CLIENT_DESKTOP.md`. The
backend is the authority on who can do what; anything this app hides or
disables is presentation only.

## Platforms

Windows and macOS. Linux is not a target, and its runner has been removed.

## Running

Requires Flutter (stable) with Windows or macOS desktop support enabled.

```sh
flutter pub get
flutter run -d windows   # or: -d macos
flutter test
```

The app doesn't call the backend yet. When sign-in is added, the backend
address will be fixed per build, as in the mobile app:
`--dart-define=API_BASE_URL=https://…`.

## Status

| Area | State |
|---|---|
| Theme | ✅ Indigo Aurora, identical to the mobile app; light, dark and follow-the-system |
| Font | ✅ Inter bundled (Regular, Medium, SemiBold, Bold) |
| Window | ✅ Opens maximised on Windows and macOS; minimum size 1280×720 |
| Sidebar shell | ✅ Collapsible left sidebar; every section is a placeholder |
| Settings | ✅ Light/dark choice, remembered on the computer |
| Sign-in and session | Not started: waits for the backend review |
| Lock after 10 minutes idle | Not started: needs sign-in |
| Dashboard and all business sections | Not started: requirements and backend contracts still open |

### Sidebar sections

Dashboard, Members, Withdrawals, Collectors, Daily submissions, Loans, Staff,
Settings. The grouping and order are a first proposal. No section except
Settings has screens yet, and every section is shown to everyone until
sign-in exists and the role rules are confirmed.

## Design decisions

- **Palette:** Indigo Aurora, the same colour values as the mobile app
  (`lib/theme/app_colors.dart`). Change both apps or neither.
  Every text pairing meets WCAG AA (4.5:1); `test/theme/app_theme_test.dart`
  checks it.
- **Rules carried over from mobile:** green only means success; statuses show
  an icon and a label, never colour alone; the gradient is only for hero
  surfaces; amounts are neutral, in GH₵ with 2 decimals and fixed-width digits.
- **Font:** Inter, bundled so Windows and macOS look the same. The files are
  static instances generated from the Google Fonts release of Inter (optical
  size 14). Licence: `assets/fonts/inter/OFL.txt` (SIL Open Font License 1.1).
- **Layout:** collapsible left sidebar, opening expanded.
- **Window:** opens maximised, and can't be made smaller than 1280×720.
  Restoring it on Windows gives 1280×720.
- **Backend address:** fixed at build time with `--dart-define`, never
  editable in the app.
- **Idle lock:** after 10 minutes without activity (to be built with sign-in).
- **Designing screens:** before any screen or interface is built, design
  options are presented to the owner to choose from.

## Project layout

```
lib/
  main.dart            app start-up, theme mode
  shell/               sidebar, sections, page layout
  settings/            settings screen, light/dark choice and its storage
  theme/               colours, status colours, ThemeData
assets/fonts/inter/    bundled font and licence
test/                  mirrors lib/
```

## Progress log

- **2026-11-12** Theme, Inter font, maximised window, sidebar shell with
  placeholder sections, Settings with the light/dark choice. Linux runner
  removed. Tests written but not yet run (see below).
- **2026-11-12** Minimum window size 1280×720 on Windows and macOS.

## Known limitations

- The tests and `flutter analyze` haven't been run yet. The environment this
  was written in couldn't download the Flutter SDK or packages. Run
  `flutter pub get`, `flutter analyze` and `flutter test` locally;
  `pubspec.lock` will update to add `shared_preferences`.
- Windows and macOS builds haven't been run.
- The macOS menu bar still shows the project name `cash_client_desktop`.
  Changing the product name affects the bundle identifier and is left for
  packaging.
