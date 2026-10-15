# Testing PocketWork with OpenCode

Keep source checks, Simulator journeys, actual host checks, physical-device acceptance and distribution evidence separate. Passing one layer doesn't establish the others.

## Local checks

Run `swift test` from the repository root. It includes the core and Foundation-only app-state suites. Nine native live cases are opt-in and normally skip; a green ordinary run is not a live-host result. Run `python3 scripts/generate-ios-project.py` after adding app files and check the generated diff.

Build the **OpenWorkRemote** scheme with Xcode. The universal target declares device families 1/2. A compilation-only Simulator build can use `CODE_SIGNING_ALLOWED=NO`; Keychain runtime checks may need a local ad-hoc Simulator signature. Device and distribution signing are separate and stay out of source.

Use the current Xcode Simulator IDs, not another developer's machine-local UUID. Native UI suites include `NativeAppTests`, `NativeAccessibilityTests`, `NativeIPadLayoutTests` and `NativeStartupTests`. The DEBUG native fixture uses `-ui-testing-native-app` and an in-process synthetic transport. The no-pairing startup fixture uses `-ui-testing-native-startup`. They are not real server connections. Animation-reduced cases must be identified as such.

## Real native checks

Inspect the `OpenCodeLive*Tests.swift` suites before opting in. They read owner-controlled private fixture files through `POCKETWORK_NATIVE_PAIRING_FIXTURE`, `POCKETWORK_NATIVE_HISTORY_FIXTURE`, `POCKETWORK_NATIVE_CONTROLS_FIXTURE`, `POCKETWORK_NATIVE_FORMS_FIXTURE`, `POCKETWORK_NATIVE_FILES_FIXTURE`, `POCKETWORK_NATIVE_MAX_FILES_FIXTURE`, `POCKETWORK_NATIVE_RESULTS_FIXTURE`, `POCKETWORK_NATIVE_CHAT_ACTIONS_FIXTURE` and `POCKETWORK_NATIVE_WORKSPACE_FIXTURE`.

Each suite declares its own file schema. Pairing codes expire and are single-use; do not reuse a fixture after redemption. Keep fixture files outside Git with private permissions. Never put their contents in CI logs, issues or PRs. Run only against resources you own and explicitly designated disposable chats/folders. Some cases create, rename, fork or delete chat trees, stage files or change saved rules. A personal conversation is not a fixture.

Some admission checks deliberately use `resume:false` so no model executes. Label those results accurately. They do not prove provider execution, real streaming, a complete approval lifecycle or a physical Photos/Files/share journey. Mac and Linux require their own actual results.

## Information and release

The bundled information directory is canonical. An unapproved policy can be rendered only for private review with `--allow-draft`; normal publication generation intentionally refuses it. After approval, generate the site twice and verify no changes on the second run.

No native candidate is distributed yet. Keep final joined host/device, accessibility, reviewer-access and App Store gates open until they have actual evidence. See [rendering measurements](rendering-and-responsiveness.md), [accessibility](accessibility-qualification.md) and [compatibility](opencode-compatibility.md).
