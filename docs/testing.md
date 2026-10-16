# Testing PocketWork with OpenCode

Keep source checks, Simulator journeys, actual host checks, physical-device acceptance and distribution evidence separate. Passing one layer doesn't establish the others.

## Local checks

Run `swift test` from the repository root. It includes the core and Foundation-only app-state suites. Ten native live cases are opt-in and normally skip; a green ordinary run is not a live-host result. Run `python3 scripts/generate-ios-project.py` after adding app files and check the generated diff.

Build the **OpenWorkRemote** scheme with Xcode. The universal target declares device families 1/2. A compilation-only Simulator build can use `CODE_SIGNING_ALLOWED=NO`; Keychain runtime checks may need a local ad-hoc Simulator signature. Device and distribution signing are separate and stay out of source.

Use the current Xcode Simulator IDs, not another developer's machine-local UUID. Native UI suites include `NativeAppTests`, `NativeAccessibilityTests`, `NativeIPadLayoutTests` and `NativeStartupTests`. The DEBUG native fixture uses `-ui-testing-native-app` and an in-process synthetic transport. The no-pairing startup fixture uses `-ui-testing-native-startup`. They are not real server connections. Animation-reduced cases must be identified as such.

`NativeOnboardingTests` uses the production pairing views with an in-process rejection transport. It proves explicit origin review, cancellation, invalid-input handling and fresh-code recovery without redeeming a real code. After an unsuccessful redemption, the primary action discards the old payload and returns to scanning/pasting; it must not offer Connect again for a potentially consumed code. The existing QR/link cases and new password rejection/background-clearing cases pass on the iPhone17Pro/iOS27 Simulator. Password layout and remaining device checks are recorded separately. Live HTTPS pairing remains a separate check.

Set TEST_RUNNER_POCKETWORK_UI_NARROW_WINDOW=1 when invoking xcodebuild for the native iPad UI cohort to resize the actual iPadOS app window below 600 points after launch. The test helper checks the resulting window width. This changes Simulator window geometry, rather than the browser preview scale. Use element/window-scoped gestures in a resized window; an application-wide swipe can miss its content. The normal cohort keeps its ordinary launch behavior when this opt-in is absent.

## Real native checks

Inspect the `OpenCodeLive*Tests.swift` suites before opting in. They read owner-controlled private fixture files through `POCKETWORK_NATIVE_PAIRING_FIXTURE`, `POCKETWORK_NATIVE_HISTORY_FIXTURE`, `POCKETWORK_NATIVE_CONTROLS_FIXTURE`, `POCKETWORK_NATIVE_FORMS_FIXTURE`, `POCKETWORK_NATIVE_FILES_FIXTURE`, `POCKETWORK_NATIVE_MAX_FILES_FIXTURE`, `POCKETWORK_NATIVE_RESULTS_FIXTURE`, `POCKETWORK_NATIVE_CHAT_ACTIONS_FIXTURE`, `POCKETWORK_NATIVE_WORKSPACE_FIXTURE` and `POCKETWORK_NATIVE_NEWCHAT_FIXTURE`.

Each suite declares its own file schema. Pairing codes expire and are single-use; do not reuse a fixture after redemption. Keep fixture files outside Git with private permissions. Never put their contents in CI logs, issues or PRs. Run only against resources you own and explicitly designated disposable chats/folders. Some cases create, rename, fork or delete chat trees, stage files or change saved rules. A personal conversation is not a fixture.

Some admission checks deliberately use `resume:false` so no model executes. Label those results accurately. They do not prove provider execution, real streaming, a complete approval lifecycle or a physical Photos/Files/share journey. Mac and Linux require their own actual results.

## Shipping configuration

`NativeJoinedInputTests` is opt-in and launches the normal app without fixture flags. With `POCKETWORK_NATIVE_INPUT_PROJECT` set to the already selected, owned qualification project, it types text, checks Send eligibility, relaunches, verifies restoration and clears the text. It does not send a message. Never enable it against a personal chat. The driver must verify native history, local pending state and inbox before retrying any separate live send after an interrupted run.

`testNormalReleaseIsolatedReviewerReply` is a separate opt-in live journey. `POCKETWORK_NATIVE_REVIEW_UI_CONFIG` points to a private file identifying the dedicated synthetic PocketWork Review project, ownership nonce and local-model starter chat. Preflight must verify the matching server marker/session, inactive execution, empty inbox and known history before creating that file. The normal app must already be paired through its reviewed native UI. This case deliberately sends one synthetic prompt to the permitted local model after sharing consent. It records a one-attempt marker before Send and refuses to replay it. Inspect authoritative history/inbox after any interruption; do not remove the marker to make the case run again. It uses no fixture launch flags, credential injection or private developer path in the app. A Simulator pass does not establish fresh mobile Safari sign-in, touch copying, an outside network, physical acceptance or complete App Review access.

`testNativeSafariReviewerPasswordSignIn` is an opt-in Simulator check of OpenCode’s own mobile web sign-in, separate from PocketWork authentication. `POCKETWORK_NATIVE_REVIEW_SAFARI_CONFIG` points to a private, permission-restricted JSON file containing `disposable`, a 32-hex `ownerNonce`, the dedicated HTTPS `origin` and its existing reviewer `password`. Preflight must verify ownership and the exact native destination. Start in an empty Safari Private Browsing tab on the owned reviewer Simulator; the test navigates through Safari’s visible address field, verifies the complete address, selects Use password, checks the form’s exact origin before typing into its secure field, and requires authenticated synthetic history. It declines password saving and does not send a model request. Close only the owned private tab afterward. Keep credentials and result attachments private. A passing fresh Safari sign-in does not prove touch copying, the full same-phone pairing journey, an outside network or physical acceptance.

The October15 normal Release iPadOS27 check passes fresh native HTTPS pairing to the owned Mac2.0.29 service, then selects a synthetic image through the actual Apple Photos picker. It explicitly allows scoped sharing and requires a Ready chip in the draft with Send enabled and no extra Add screen. That case leaves the message unsent; it does not prove a provider reply or physical-device behavior. The history helper scrolls the virtualized Recent Chats list before requiring an offscreen row to exist. An earlier failed check and the corrected pass are retained in the private qualification record.

The iOS Release app uses `NativeReleaseAppModel` and native-only screen adapters. Legacy bridge screens/client code are excluded from iOS Release. Their Mac/DEBUG regression coverage remains available; fourteen historical facade cases run in Debug, where their original facade exists. Local migration only reads/clears older records and byte copies through `LegacyLocalRecovery`, with no bridge client.

Run the Release facade/reset checks as well as the ordinary package suite:

```sh
swift test -c release --filter 'NativeAppLaunchTests|NativeAppCoordinatorTests|NativeAppModelFacadeTests|OpenCodeResetTests|LegacyLocalRecoveryTests'
```

CI builds both Debug and Release without signing. After a Release build, `python3 scripts/verify-ios-release.py --app <built-app-path>` scans every bundled Mach-O image for retired wire/DEBUG markers and checks the universal orientation declarations. A Debug app may have its implementation in a separate `.debug.dylib`, so checking only its launcher is insufficient. This static check does not establish runtime behavior, signing, physical acceptance or distribution.

## Information and release

The bundled information directory is canonical. An unapproved policy can be rendered only for private review with `--allow-draft`; normal publication generation intentionally refuses it. After approval, generate the site twice and verify no changes on the second run.

Native1.0.0(9), archived from codeb7414b8, is available to the existing internal TestFlight group. Keep remaining physical host/device, accessibility, reviewer-access and App Store gates open until they have actual evidence. See [rendering measurements](rendering-and-responsiveness.md), [accessibility](accessibility-qualification.md) and [compatibility](opencode-compatibility.md).

## October15 final UI checkpoint

The iPadOS27 native cohort has 35 passing case dispositions across its main run and focused repairs, including an actual narrow iPadOS app window, landscape, largest text, models/rules/questions, attachment/result controls, chat actions, groups, defaults, changes and skills. The iPhoneSE3/iOS26.5 cohort has 33 passing dispositions: its final full run passed 32 and one test attempted typing before chat selection finished; that case passes after using the existing complete-selection helper. Original failures and repair results are retained privately. These are synthetic DEBUG UI checks; they do not replace normal Release live-host, physical or distribution evidence.

The build8 normal ad-hoc iPad Simulator Release launched without fixture flags, restored the real Mac connection and passed the all-code-image/universal shipping check. Build9 adds native-ID/send regressions: full Debug168core/231state and Release168core/217state suites pass, with ten opt-in skips per mode. Its affected phone2/iPad2 UI cases and corrected full-device iPad capture follow-up2 cases pass. Apple distribution signing and shipping checks pass; physical acceptance remains separate.

The iPad window regression uses a coordinate tap at the history button's visible center. A semantic element tap can choose an uncovered point and overlook system-window-control overlap. Keep that coordinate assertion and the whole-device screenshot when qualifying toolbar changes.

The new-chat live case consumes a fresh native pairing fixture, creates a disposable chat through the production default-ID generator, requires a real configured free-model reply, verifies unchanged tool rules and deletes only its reviewed single-chat tree. It passed separately on Mac and NUC. Its private fixture and saved intent must remain outside Git; interrupted runs require inspecting that owned intent before cleanup or retry.

### Optional native password and stock-install checks

`OpenCodePasswordPairingTests` and `OpenCodeConnectionTests` cover reviewed-origin-only requests, the native info → pair → JSON redemption sequence, transient password handling, ordinary paired-token persistence, rejection without replacing an existing connection, unsupported versions and cancellation fences. `NativeOnboardingTests` also checks password review, rejection, background clearing and largest-text cancellation. iOS may offer its own Passwords save sheet; qualification chooses **Not Now** and must not disable system settings or mislabel the field as a one-time code.

`OpenCodeStockInstallTests` is opt-in through `POCKETWORK_STOCK_NATIVE_FIXTURE`, a permission-restricted private JSON fixture containing `disposable:true`, `expectedVersion:"2.0.30"`, `loopback` (HTTP127.0.0.1 with an explicit port), `directory` (an owned synthetic Git project) and its generated test-server `password`. Use an unmodified official platform binary and isolated XDG roots. The test-only transport rewrites requests to that loopback endpoint; no TLS trust setting or production transport is changed. This is native API qualification, not mobile HTTPS proof. The test writes an owned create intent beside the fixture before mutation and refuses an existing intent. Inspect any interrupted result before another run. It admits a resume:false prompt, requires no active execution and deletes only its created one-chat tree. Keep fixtures, credentials, intent/result files and private request evidence out of Git. A passing run does not qualify every feature or physical device.

`NativeJoinedInputTests.testNormalReleasePasswordPairingThroughReview` uses the normal Release app with no fixture flags or Keychain injection. `POCKETWORK_NATIVE_PASSWORD_UI_CONFIG` points to a private JSON file with `disposable:true`, a 32-hex `ownerNonce`, the preflight-verified dedicated HTTPS `origin` and its existing `password`. It enters the optional route from welcome or Settings → Pair again, verifies the displayed exact origin before Connect, declines any iOS Passwords save choice, performs one explicitly recorded attempt and requires successful paired-credential reload after relaunch. It does not send a model request. Its adjacent attempt/result files and screenshots stay private; never remove an attempt marker to force another issuance. Before reusing a target, inspect its ownership/history/inbox and existing saved connection. Normal Release native HTTPS pairing/reload passes on iPhone17Pro/iOS27 (existing connection replaced) and iPhoneSE3/iOS26.5; those are Simulator results, not physical or App Store acceptance.

### October16 native information qualification

The native startup/legal suite now uses the actual unpaired native route and approved policy2026-10-16.1. About/help tests scope Back to the visible document's navigation bar; the underlying welcome has a separate navigation stack. Support controls are SwiftUI Links, whose accessibility type varies by device/OS, so tests identify them independently of Button/Link type. On iPad, document and List gestures target their centered sheet content rather than the welcome behind it. Retain the original failed results alongside corrected passes. This is test-driver maintenance; no production UI change is involved.

All five iPad information/window cases have passing dispositions across the main four-pass/one-failure run and the focused support-link/scroll repair, including landscape, a real narrow app window, pre-pairing legal access and largest text. The existing broader native baseline, affected compact-chat/photo/archive/follow tests and password checks remain separately scoped; no single all-green whole-suite or physical acceptance is implied.

The final small-phone information cohort passes3/3 on iPhoneSE3/iOS26.5 after these test-only corrections, including all bundled legal documents, reachable support controls and largest-text help/privacy before pairing.
