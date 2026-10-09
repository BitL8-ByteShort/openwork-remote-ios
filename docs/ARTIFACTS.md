# Generated files — source candidate

Generated-file previews and sharing are in development. They are not included
in internal TestFlight build 0.1.0 (5).

On a qualified host, open **Files from this chat** below the conversation or in
**Model & settings → This chat**. The list shows filenames, sizes and types.
Nothing downloads until you select a file. Your computer must explicitly allow
file transfer for this phone; availability alone does not grant access.

Text, PNG/JPEG images and PDF pages use native previews. RTF is share-only.
Choose **Share or save a copy** to open the iOS Share Sheet with the original
downloaded file. The app never sends that copy to another person automatically.
It rechecks access, the current file revision and the local checksum before
opening the sheet. Changed, damaged or revoked files cannot be shared from an
old preview; refresh the list or continue on your computer.

Archives, executables, HTML, SVG and external links are not downloadable through
this feature. Oversized files or result lists explicitly refer you to OpenWork
on the computer. A chat's file list is a bounded set of verified local outputs,
not an unrestricted project browser. Native session ownership and registered
Git worktree containment are checked independently of any model-provided link.

## Transfer and retention

Each file is at most 20 MiB. Downloads use bounded 1 MiB ranges and verify the
complete length and SHA-256 before a preview becomes ready. Failed or cancelled
downloads remove their partial copy. There is no background prefetch of results,
automatic retry or external URL fetch. Switching chats or pairing ignores old
responses and cancels the old scoped transfer.

Temporary originals and preview rasters stay in private phone storage with
complete file protection and backup exclusion. Storage is bounded to 100 MiB.
Copies expire after one hour; startup cleans expired copies and orphan partials.
Closing a preview removes its temporary copy after an open Share Sheet has
finished. Forgetting the computer cancels active result downloads and removes
their local cache. It does not delete host outputs or copies already exported
through the Share Sheet. A complete local-data reset remains publishing work.

| Data | Stored or transferred | Purpose |
| --- | --- | --- |
| Result metadata | Opaque handle, target chat ID, filename, MIME, size, revision and checksum | Scoped listing and stale-file protection; no phone-supplied host path |
| Original result bytes | Paired computer → protected temporary phone file | Explicit preview and original-file sharing |
| Native raster or bounded text | In-memory preview; large text is labelled as shortened | Readable display without an embedded web renderer |
| Exported copy | Destination explicitly selected in the native Share Sheet | Destination controls its own retention and sharing |

This inventory informs the pending policy and consent screens. It is not a
published privacy policy or a final App Store privacy-label declaration. Result
generation uses the computer's configured model provider; viewing a result does
not itself send its contents back to that provider.

## Qualification and limits

Core and state regressions cover opaque scope, invalid ranges/replies, cancelled
and late transfers, checksum failure, stale catalogs, revoked sharing access and
protected temporary cleanup. Native Simulator flows use real paired HTTPS to
actual Mac and Ubuntu NUC hosts. They verify text and PDF preview, damaged PNG
rejection, valid PNG preview and explicit sharing to an isolated test destination
with exact checksum readback. Model-generated PNG fixtures on both hosts were
damaged; valid PNG tests deliberately repaired only those disposable fixtures
and restored the original bytes afterwards. They do not qualify the model's PNG
generation. Existing host chats/settings/pairing and Serve rules were preserved.

Image and PDF rendering uses Apple's native frameworks with size/page/raster
limits, plus structural PNG validation. This is not proof against every hostile
parser input. Actual registered Git worktree containment has filesystem tests;
a live model result in a session worktree still needs separate qualification.
Physical phone/iPad selection of a Share Sheet destination, cellular recovery,
VoiceOver/large text and low-space device behavior remain acceptance gates.
Simulator test activities and fixture configuration are excluded from Release.
