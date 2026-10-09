# Question answering qualification

The native answer sheet supports explicit choice/custom-text replies, protected
drafts, Cancel/reopen, and a stale state when the computer has already answered.
It does not retry an uncertain reply or infer acceptance from disappearance.

On October 9, 2026, four live Simulator cases passed over ordinary tailnet HTTPS
against actual macOS and Ubuntu 24.04 x64 OpenWork runtimes: one submitted reply
and one computer-answer race per host. Scoped receipt readback confirmed one
accepted phone submission per host. The native test form had two single-choice
fields with a custom-text answer allowed for the second; this is not evidence
for a native text-only field. Computer answers used the host-local production
adapter while the phone sheet was open, rather than desktop mouse interaction.

The temporary pairings were revoked, and their temporary HTTPS mappings removed
without changing existing Serve configuration. Existing workspace defaults and
phone grants were not expanded. These are iPhone 17 Pro Simulator checks, not a
physical iPhone, TestFlight or App Store release qualification.

| Host | Reply acknowledged | Computer answer retains the phone draft |
| --- | --- | --- |
| macOS | [Screenshot](screenshots/questions-live-mac-roundtrip.png) | [Screenshot](screenshots/questions-live-mac-computer-race.png) |
| Ubuntu NUC | [Screenshot](screenshots/questions-live-nuc-roundtrip.png) | [Screenshot](screenshots/questions-live-nuc-computer-race.png) |

## Opt-in live tests

`LiveQuestionUITests` is skipped unless a private ephemeral configuration is
provided through `OPENWORK_QUESTION_UI_CONFIG`. The test preflights the scoped
bridge chat and requires the exact disposable title before any answer action.
The configuration contains a scoped temporary credential and must never be
committed. Host-local coordination for the race uses an owned temporary marker.

The launch fixture is compiled only for DEBUG Simulator builds. Both draft and
question stores use an isolated protected temporary directory; the real app's
Keychain pairing is never loaded or saved. Invalid configuration stays unpaired.
If the isolated store cannot be created, the qualification fails instead of
falling back to installed app storage. An unsigned Release Simulator build
passed, and the live launch flag, environment key and fixture failure marker
were absent from its binary, with positive controls in the Debug dylib.

Normal CI does not create pairings or send prompts to a live host. Core tests,
synthetic native UI checks and unsigned Simulator builds are separate evidence.
