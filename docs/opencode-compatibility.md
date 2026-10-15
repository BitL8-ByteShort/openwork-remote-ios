# OpenCode compatibility

The OpenCode migration is under development. No native-backend PocketWork build has been distributed yet. The released OpenWork beta is a separate, older connection path.

Scoped native contract checks have passed against **OpenCode 2.0.29** on macOS and Ubuntu Linux. This does not qualify the complete source candidate for release. Native pairing uses OpenCode’s built-in HTTPS remote access. The computer must keep OpenCode running. There is no PocketWork bridge, Tailscale requirement or general remote-shell API in this connection path.

## Feature matrix

“Host check” means an actual Mac/NUC native API check using disposable resources. It does not mean the complete app passed physical-device or App Store review.

| Feature | Native migration status | Limits |
| --- | --- | --- |
| Pair, re-pair and saved connection | Typed host checks; native default startup and storage/Keychain retry paths; Simulator Release startup | Final joined foreground/network-change and physical update qualification remain |
| Projects, chats and paged history | Both host checks; Simulator flows; exact-folder selection recovery regressions | Final joined restoration and complete physical-device matrix remain |
| Text, photos and PDF attachments | Native transfer/admission checks on both hosts | Provider execution and physical Photos/Files qualification remain |
| Results, project files and sharing | Both host checks; Simulator preview/export | Explicit selection; contained files; 20 MiB download cap; physical sharing remains |
| Models, variants and agents | Native per-chat controls and Simulator UI | Computer’s catalog; unavailable choices never silently substitute another model |
| Chat rules, approvals and forms | Native components and scoped host checks | Ordinary-host approval-request lifecycle still needs joined provider qualification; clean isolated approval proof is separate |
| Create, rename, fork and delete | Both host checks and Simulator UI | Lost create/fork acknowledgements stay uncertain; deletion covers the reviewed descendant tree and may include concurrent branches |
| Search older chats | Native paged title search | Titles only; message bodies are not searched |
| Groups | Protected device-local storage and Simulator UI | On this iPhone/iPad; no desktop synchronization; removing a group keeps chats |
| New-chat model/agent defaults | Protected local preferences; both host create checks; Simulator UI | Applies only to new PocketWork chats in that connection/project; existing and desktop-created chats are unaffected |
| Working-copy changes | Both host status/diff checks and Simulator UI | Read only; may include edits outside the chat; native rename representations and binary/no-text results are preserved |
| Registered skills | Both host catalog/materialization checks and Simulator UI | Read-only preview; explicit next-message selection; changed/removed selections require review |
| Edit host skills | Computer handoff | No supported typed host-editing API is exposed by PocketWork |
| Scheduled work | Computer handoff | No second scheduler or shell workaround is added |
| Project access restrictions | Native pairing scope is server-wide | Visible-project preferences only change this device’s list; they are not permissions |
| Sharing review and local data controls | Deliberate provider/configuration review; reset/recovery/failure state tests and native UI | Final joined active-upload/reset and physical recovery remain |
| Large replies | Cancellable worker preparation and bounded reader; normal/maximum-text SE3 and iPad Simulator journeys | Plain-text pages preserve all bytes; physical streaming/tap measurements remain |
| Individual token revocation | Not supplied by this native version | Forget removes the local credential. Server-password rotation on the computer invalidates all paired devices |

## Transfer and preview bounds

Up to four selected photos/PDFs, 20 MiB each and 40 MiB total. Native photos normalize to PNG with a 2,000-pixel longest edge. PDFs up to 5 MiB can use inline admission; larger PDFs use native temporary-file staging and require model tools. Transfer/admission qualification does not establish a model’s ability to ingest every document.

Results require native range/version checks and protected content validation before preview or sharing. Working diffs are ordinary bounded JSON with at most 1 MiB of patch text per file; previews page their lines and disclose shortening. Ordinary JSON responses remain capped at 8 MiB. Skill catalogs have a separate 16 MiB cap after an actual 8.5 MB Mac catalog exceeded the ordinary budget; individual skill content remains capped at 1 MiB. Decoding and content fingerprints run off the UI actor.

## Skills and changes

Previewing registered skill text does not invoke the skill. Selecting it saves an ID, name and version fingerprint for the next message. Before sending, PocketWork checks the registered version again. OpenCode resolves the selected skill at admission and can add related file names or plugin content; this is not a server-side lock on a previewed version. Skill-only messages and sent files have visible history labels. Materialized skill instruction bodies are not rendered as chat messages.

Working-copy review only calls the native VCS information, status and working-diff reads. It cannot initialize, stage, commit, revert or execute commands. OpenCode returns the working-copy diff as a batch, so opening one file may transfer diffs for other files in that location. A missing provider, oversized/unsupported diff or missing text gets a computer handoff.

## Qualification boundary

October 15 checks cover actual Mac and NUC 2.0.29 native HTTPS, isolated disposable Git/plain directories, Unicode paths, rename/binary status, working diff, selected model/agent creation and synthetic skill materialization with execution disabled. Disposable chats and hash-verified fixture files were removed; existing session records were unchanged. Temporary Git project records are left to OpenCode’s own missing-directory archival; the tests do not edit its database.

Native feature suites cover iPhone/iPad27, with additional SE3/iOS26.5 maximum-text, keyboard and reader checks. Default native startup and offline information, consent/reset and local recovery have their own state/UI checks. Some DEBUG fixture cases reduce animations after XCTest notification waits; these do not establish physical tap latency. Full accessibility/multitasking/hardware-keyboard coverage, joined provider execution, physical-device evidence and distribution remain separate gates. See [accessibility](accessibility-qualification.md) and [rendering measurements](rendering-and-responsiveness.md).

Native interfaces: [VCS](https://github.com/anomalyco/opencode/blob/v2.0.29/packages/protocol/src/groups/vcs.ts), [skills](https://github.com/anomalyco/opencode/blob/v2.0.29/packages/protocol/src/groups/skill.ts), [skill materialization](https://github.com/anomalyco/opencode/blob/v2.0.29/packages/core/src/session/prompt.ts), [skill preparation](https://github.com/anomalyco/opencode/blob/v2.0.29/packages/core/src/skill.ts).

## Legacy source separation

The iOS Release configuration has a native-only facade and screen adapters. The bridge client and its HTTP extensions are not compiled into iOS Release, and no legacy grant/capability UI is wired into that build. Mac/DEBUG historical regression coverage remains. A separate local recovery actor handles older metadata and file-copy removal without any bridge client. Static bundle checks and a no-flags Simulator Release launch/reset have passed; the joined real-host/physical release matrix is still pending.
