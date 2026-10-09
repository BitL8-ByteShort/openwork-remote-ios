# Selected attachments — source candidate

This implementation is not in the recorded TestFlight build 0.1.0 (4).
Physical Photos/Files selection and cellular/recovery acceptance remain open.

On a qualified host with computer-approved file access, the composer opens
“Add to your message.” Choose photos or browse supported files, review each
filename and upload state, then return to the composer. Sending is a separate
action after every selected file is ready. Four files, 20 MiB per file and
40 MiB per prompt are the product limits; a lower host limit takes precedence.
Unsupported models and hosts keep the entry visible with an explanation.

JPEG, HEIC and PNG photos become a fresh, correctly oriented PNG with a maximum
edge of 2,048 pixels. The original stays unchanged. Source location, camera
comments and contact metadata are not copied. PDF bytes are preserved. Only
PNG and PDF have qualified native model inputs in this candidate; selecting
another type does not authorize sending it to an unsupported model.

## Storage and sharing inventory

This is the implementation inventory for the pending privacy policy and consent
work, not a published privacy policy or an App Store privacy-label decision.

| Data | Location and lifetime | Sharing |
| --- | --- | --- |
| Selected PDF or converted photo | Private, protected phone files excluded from backup; 100 MiB staging cap. Removed after accepted sending or explicit removal. An uncertain transfer retains recovery state and bytes. | Uploaded only to the paired computer with its explicit file grant. |
| Attachment draft | Protected phone JSON: local opaque ID, filename, MIME, byte count, checksum, target IDs, progress, stable operation UUIDs and outcome. No file bytes or host path. | Metadata accompanies the scoped upload; local file IDs do not become host paths. |
| Uncommitted host staging | Private, device/workspace/chat-bound storage; 24-hour expiry with periodic cleanup. Cancel affects staging only. | Not forwarded for inference until the upload is committed and a prompt is deliberately sent. |
| Committed inbox file and chat history | Existing OpenWork workspace/history. Phone cancellation and staging expiry do not delete committed host files or undo a prompt. | The computer may send the selected contents to its configured model provider when processing the prompt. |
| History attachment label | Safe filename label in the phone response. Native file URIs and embedded bytes are removed from ordinary message history. | No automatic download or external URL fetch. |

“Forget computer” is not a delete-all-data control. Full local reset, orphan-file
cleanup and final retention/consent screens remain part of the publishing plan.
The picker discloses photo conversion and possible model-provider sharing.
No broad photo-library permission is requested by this feature.

File metadata reads and the observable low-space refusal are inventoried in
`PrivacyInfo.xcprivacy`. Apple documents these API categories separately from
collection declarations in its [required-reason API documentation](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype).
The empty collection array does not settle the final App Store questionnaire.

## Recovery behavior

The phone persists allocation, commit, cancellation and prompt UUIDs before
network work. A lost chunk acknowledgement resumes from confirmed host
progress. An uncertain commit offers a read-only status check, not automatic
commit retry. An uncertain prompt cannot be sent again with a new UUID after
relaunch. Changing chats or pairing invalidates presentation updates from the
old operation while retaining its scoped recovery record.

## Verified candidate evidence — October 9, 2026

- Core and app-state tests: 36 + 34 passed. State cases cover lost allocation,
  chunk and commit replies, relaunch, late responses, persistence failure,
  cancellation, duplicate selection, invalid progress and uncertain prompts.
- Photo tests cover JPEG/HEIC/PNG orientation, unchanged originals, private
  metadata removal, 2,048-pixel resizing and quota rejection. The JPEG/HEIC
  fixtures are checked to contain GPS and camera-comment metadata first.
- Four native Simulator attachment UI cases passed: unsupported host, denied
  grant, staged photo/PDF send and uncertain-commit status/removal.
- A paired HTTPS native Simulator round trip passed independently through
  actual macOS and Ubuntu NUC hosts. One prompt per host contained both files;
  its model read the image color and a PDF verification code. Selected files
  were injected into the production importers; this does not qualify physical
  picker selection. Temporary credentials and mappings were removed, and
  existing host state/pairing/Serve rules were preserved.
- Debug and Release Simulator builds passed. Release binary inspection excludes
  the opt-in test configuration and fixture controls. No distribution claim is
  inferred from those builds.

Still required: physical selected photo/PDF on both hosts, foreground recovery,
network interruption, device low-storage behavior and the same signed candidate
in internal TestFlight. Other models and host profiles require qualification.
