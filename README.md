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

The backend address is fixed per build, as in the mobile app:
`--dart-define=API_BASE_URL=https://…`. The app doesn't call the backend
yet; Settings > About shows the address (or "Not set for this build").

To look at the sign-in screen before it's connected:

```sh
flutter run -d windows --dart-define=PREVIEW_LOGIN=true
```

Signing in there always ends with "Sign-in isn't connected to the backend
yet." This switch is temporary and goes once sign-in is wired up.

## Status

| Area | State |
|---|---|
| Theme | ✅ Indigo Aurora, identical to the mobile app; light, dark and follow-the-system |
| Font | ✅ Inter bundled (Regular, Medium, SemiBold, Bold) |
| Window | ✅ Opens maximised on Windows and macOS; minimum size 1280×720 |
| Sidebar shell | ✅ Collapsible left sidebar on the light gradient panel (D3), glass highlight on the selected item, state remembered between launches (can be turned off); every section is a placeholder |
| Settings | ✅ One column of frosted glass cards over soft gradient glows (S3), each with a gradient icon tile: Appearance (light/dark, remember sidebar state) and About (version, server). Account and Password cards come with sign-in |
| Sign-in screen | ✅ Light A1 design: curved gradient panel with shield, form with checks and states, version footer. Not connected to the backend yet; preview with `--dart-define=PREVIEW_LOGIN=true` |
| Sign-in and session | Not started: waits for the backend review |
| Lock after 10 minutes idle | Not started: needs sign-in |
| Dashboard and all business sections | Not started: requirements and backend contracts still open. The dashboard's layout is chosen (D3: one gradient headline card, metric cards, two sections), but what it shows isn't decided |

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
  an icon and a label, never colour alone; amounts are neutral, in GH₵ with 2
  decimals and fixed-width digits.
- **Gradients (desktop):** every primary button uses the button gradient
  (`GradientButton`, one per screen), and so do switches when on
  (`GradientSwitch`) and the icon tiles on cards; hero surfaces such as the sign-in panel
  use the lighter gradients in `lib/theme/app_gradients.dart`. The lighter
  tints were added to the shared palette on 2026-11-12, so the mobile app is
  to adopt them too. Text on every gradient meets 4.5:1
  (`test/theme/app_gradients_test.dart`).
- **Font:** Inter, bundled so Windows and macOS look the same. The files are
  static instances generated from the Google Fonts release of Inter (optical
  size 14). Licence: `assets/fonts/inter/OFL.txt` (SIL Open Font License 1.1).
- **Layout:** collapsible left sidebar, opening expanded. Restyled on
  2026-11-12 (option D3): the sidebar is the light gradient panel, the
  selected item a glass pill, with the "CC" tile beside the app name.
  (Replaces the earlier light-panel style A.)
- **Window:** opens maximised, and can't be made smaller than 1280×720.
  Restoring it on Windows gives 1280×720.
- **Backend address:** fixed at build time with `--dart-define`, never
  editable in the app.
- **Idle lock:** after 10 minutes without activity (to be built with sign-in).
- **Settings:** one column of section cards, in the order Account, Password,
  Appearance, About, styled as frosted glass cards over soft gradient glows
  (option S3) with gradient icon tiles. "Remember sidebar state" is on by default, following
  the usual desktop convention of reopening the layout as the user left it.
  About reads the version from the installed app (`package_info_plus`) and
  shows the build's backend address.
- **Sign-in screen:** option A1 in the lighter colours: a gradient panel on
  the left whose edge curves outward, a shield-and-lock illustration with
  "Staff only" and "Protected sign-in" labels, the form on the right, and
  "Version … · Powered by Bynex Labs" small in the bottom-right corner.
- **Designing screens:** before any screen or interface is built, design
  options are presented to the owner to choose from.

## Project layout

```
lib/
  main.dart            app start-up
  auth/                sign-in screen, its panel and illustration
  common/              shared widgets (gradient button, brand mark)
  config/              build-time settings (--dart-define)
  shell/               sidebar, its remembered state, sections, page layout
  settings/            settings screen, light/dark choice, app info
  theme/               colours, status colours, ThemeData
assets/fonts/inter/    bundled font and licence
test/                  mirrors lib/
```

## Progress log

- **2026-11-12** Theme, Inter font, maximised window, sidebar shell with
  placeholder sections, Settings with the light/dark choice. Linux runner
  removed. Tests written but not yet run (see below).
- **2026-11-12** Minimum window size 1280×720 on Windows and macOS.
- **2026-11-12** Sidebar style A confirmed. Settings rebuilt as option A:
  Appearance card with the remember-sidebar switch, About card with version
  and server. Added `package_info_plus`.
- **2026-11-12** Sign-in screen (light A1) built, not yet connected. Lighter
  gradient tints and the gradient primary button added. Temporary
  `PREVIEW_LOGIN` switch to view it.
- **2026-11-12** Sidebar moved onto the light gradient panel (D3); Settings
  restyled as glass cards on gradient glows (S3); gradient switch and icon
  tiles. Dashboard body waits for its contents to be decided.

## Known limitations

- The tests and `flutter analyze` haven't been run yet. The environment this
  was written in couldn't download the Flutter SDK or packages. Run
  `flutter pub get`, `flutter analyze` and `flutter test` locally;
  `pubspec.lock` will update to add `shared_preferences` and
  `package_info_plus`.
- Windows and macOS builds haven't been run.
- The macOS menu bar still shows the project name `cash_client_desktop`.
  Changing the product name affects the bundle identifier and is left for
  packaging.
