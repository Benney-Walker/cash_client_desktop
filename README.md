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
`--dart-define=API_BASE_URL=https://…` (for a local backend,
`http://localhost:8080`). Settings > About shows the address (or "Not set
for this build"). Without it, signing in says the build has no server
address.

Receipts print the credit union's name from
`--dart-define=CREDIT_UNION_NAME=…` (without it they say "Cash Client").

## Status

| Area | State |
|---|---|
| Theme | ✅ Indigo Aurora, identical to the mobile app; light, dark and follow-the-system |
| Font | ✅ Inter bundled (Regular, Medium, SemiBold, Bold) |
| Window | ✅ Opens maximised on Windows and macOS; minimum size 1280×720 |
| Sidebar shell | ✅ Collapsible left sidebar on the light gradient panel (D3), glass highlight on the selected item, state remembered between launches (can be turned off); every section is a placeholder |
| Settings | ✅ One column of frosted glass cards over soft gradient glows (S3), each with a gradient icon tile: Account (name, role, staff ID, Sign out), Appearance (light/dark, remember sidebar state) and About (version, server). No Password card (reset is on the sign-in screen) |
| Sign-in screen | ✅ Light A1 design: curved gradient panel with shield, form with checks and states, version footer. "Forgot password?" (R1) under the password field opens the backend's reset page (`/password-reset`, staff ID filled in) in the browser; new staff set their first password there |
| Sign-in and session | ✅ Signs in with `POST /api/auth/v1/staff-login` (collectors get 403 there); only Administrators and Agents get in (both roles = Administrator); tokens kept in memory only, so staff sign in each launch; expired access tokens are refreshed automatically (`POST /api/auth/v1/refresh-staff-token`, keeping the rotated refresh token) and the request retried; a refused refresh ends the session and the sign-in screen says so; Sign out in Settings ends the session on the backend (`POST /api/auth/v1/logout`); a locked account (5 wrong passwords) gets the backend's own message, and the lock screen signs it out with that message |
| Inactivity lock | ✅ After 20 minutes without mouse or keyboard activity, a card over the dimmed app (L1) asks for the password; it covers dialogs too, unlocking signs in again with the same staff ID, and "Not you? Sign out" returns to sign-in |
| Staff: Add staff | ✅ Four steps (F3): Personal, Contact, Role and branch, Review; Administrators only; posts to `/api/staff/v1/add-staff` without a password; success says the staff ID was sent by SMS. Waits on two backend changes (see Known limitations). Staff list not built |
| Members: Register member | ✅ Five steps (M1): Personal, Contact and work, Account (Savings or Current, branch), ID document (Ghana Card or Voter's ID, ID number, JPEG/PNG picture up to 5 MB, chosen or dragged in, with preview; can be skipped), Review. Administrators and Agents. Posts to `/api/member/v1/add-member` with an idempotency key, then uploads the ID to `/api/member/v1/kyc-document-upload`; if only the upload fails, just the ID is retried; View member opens the new member |
| Members: find and view (P2) | ✅ Search on the left (name, phone or account number; proposed `GET /api/member/v1/search`), details on the right: status, ID status, details, accounts, ID document with Upload ID document when the backend allows; limited view for another branch's member. The backend's search is now built at `/api/member/v1/search-members` with a different shape, so the desktop's search must be switched over; details still lack the ID status (CASH_CLIENT_DESKTOP.md §20) |
| Transactions (T3) | ✅ Find the account by number, name or phone; account card (member, status, available and current balance) and recent history on the left; withdrawal, deposit, share purchase and transfer on the right with a review step (fee shown once the backend offers its settings), one idempotency key per review, same-key retries, "outcome unknown" handling; result with "Print receipt" (A4, no balance) |
| Daily submissions (S3) | ✅ Waiting and Approved lists; a day's totals and payments; cash-count helper (cedi notes and 50p/20p coins) with a running total that turns green at the expected cash; Approve off while short, surplus approved directly; lost answers retried with the same count |
| Dashboard and all other business sections | Not started: requirements and backend contracts still open. The dashboard's layout is chosen (D3: one gradient headline card, metric cards, two sections), but what it shows isn't decided |

### Sidebar sections

Dashboard, Members, Transactions, Collectors, Daily submissions, Loans,
Staff, Settings. The grouping and order are a first proposal.
Transactions (renamed from Withdrawals on 2026-11-24) holds the counter's
withdrawals, deposits, share purchases and transfers; collector
withdrawal requests were removed from the system on 2026-11-15. Settings,
Members, Transactions, Daily submissions and Staff (Add staff) have
screens so far, and every section is shown to both roles until
each section's role rules are confirmed.

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
- **Sessions:** staff sign in each time the app opens; tokens live in
  memory only and are never written to disk. Staff who are neither
  Administrator nor Agent are refused; someone with both is treated as an
  Administrator. These checks only shape the app; the backend enforces
  permissions on every request.
- **Idle lock:** after 20 minutes without mouse or keyboard activity (changed
  from 10 on 2026-11-13), option L1: the app stays visible but dimmed and
  out of reach behind a lock card showing the staff member's name, role and
  staff ID, a password field, Unlock and "Not you? Sign out".
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
  members/             Members page, Register member steps, member API and models
  staff/               Staff page, Add staff steps, staff API and models
  branches/            branch list API, branch model and picker
  api/                 backend errors, the authenticated HTTP client, Apis bundle
  auth/                sign-in API, session, gate, sign-in screen
  common/              shared widgets (gradient button, step flow pieces), dates, UUIDs
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
  gradient tints and the gradient primary button added.
- **2026-11-12** Sidebar moved onto the light gradient panel (D3); Settings
  restyled as glass cards on gradient glows (S3); gradient switch and icon
  tiles. Dashboard body waits for its contents to be decided.
- **2026-11-13** Sign-in connected to the backend: login, role check,
  automatic token refresh with one retry, session ending, sign-in gate,
  Account card with Sign out. Same API layer as the collector app.
  "Forgot password?" removed. Added `http`.
- **2026-11-13** Inactivity lock (L1, 20 minutes).
- **2026-11-15** Sign-in follows the backend's renamed endpoints
  (`staff-login`, `refresh-staff-token`); a 403 from the office login
  explains that the app is for administrators and agents.
- **2026-11-15** Add staff (F3, four steps). API failure types for 404 and
  409, shared with the collector app.
- **2026-11-16** Register member (M1, five steps, ID step can be skipped).
  Step indicator, review section, notes and the branch picker moved to
  shared widgets; branch list moved to its own API (`{id, name}`); APIs
  passed down as one `Apis` bundle. macOS entitlements for outgoing network
  calls and the file dialog. Added `file_selector` and `http_parser`.
- **2026-11-16** Sessions follow the backend's rotating refresh tokens
  (the new refresh token is kept after every refresh; the old bare-token
  answer still works) and sign-out calls `POST /api/auth/v1/logout`.
  ID pictures can be dragged onto Register member. Added `desktop_drop`
  (0.8).
- **2026-11-16** Members page as P2: search and results beside the member's
  details; Upload ID document from the details; View member after
  registering. ID document fields shared between the two screens; danger
  and neutral status pills.
- **2026-11-24** Password reset (Phase 1, option R1): "Forgot password?" on
  the sign-in screen opens the backend's `/password-reset` page in the
  browser. Locked accounts get their own message instead of the
  collectors one, and the lock screen signs them out with it. Added
  `url_launcher`.
- **2026-11-24** Member search switched to the built
  `/api/member/v1/search-members` (Spring `PagedModel`, one shared parser).
- **2026-11-24** Transactions (Phase 2, T3): withdrawal, deposit, share
  purchase and transfer with review, idempotency and A4 receipts. Sidebar
  "Withdrawals" renamed "Transactions". Added `pdf` and `printing`; new
  build define `CREDIT_UNION_NAME` for the receipt heading.
- **2026-11-24** Daily submissions (Phase 3, S3): list, details, cash-count
  helper and approval against `/api/transaction/v1/collector-submissions`.

## Known limitations

- The counter can't show the withdrawal fee or the first-deposit rules
  before sending until the backend offers its settings
  (CASH_CLIENT_DESKTOP.md §21); the result shows the fee charged.

- The tests and `flutter analyze` haven't been run yet. The environment this
  was written in couldn't download the Flutter SDK or packages. Run
  `flutter pub get`, `flutter analyze` and `flutter test` locally;
  `pubspec.lock` will update to add `shared_preferences`,
  `package_info_plus`, `http`, `http_parser`, `file_selector`,
  `desktop_drop`, `url_launcher`, `pdf` and `printing`.
- Register member and Add staff need the backend's `claude/backend-progress`
  branch (branch list, add-staff without a password). Until
  the backend reads `idempotencyKey` on add-member, a retry after a lost
  answer gets 409 for the phone number (the app says the member was
  probably registered).
- Member search and the details' branch, ID status and limited view are
  proposed in CASH_CLIENT_DESKTOP.md §18 and not on the backend yet. Until
  then search says it isn't offered, and the details page shows what the
  backend sends without Upload ID document.
- The Account card can't show the branch: the login response doesn't
  include it and staff can't read their own profile.
- Windows and macOS builds haven't been run.
- The macOS menu bar still shows the project name `cash_client_desktop`.
  Changing the product name affects the bundle identifier and is left for
  packaging.
