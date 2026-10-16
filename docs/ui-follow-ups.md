# Current UI follow-up candidate

The delivered internal beta is1.0.0(9). The changes below are in the next source candidate and are not a new TestFlight release yet.

- **Files:** open the project/model title, then Files from this chat. The duplicate transcript row is removed.
- **Sharing:** the compact sheet shows the reported provider/model, shared data and routing caveat. Connection details expand separately. Allow sharing is reachable without reading the technical section.
- **Attachments:** + opens Photos or Files directly. A selected item appears in the draft and prepares. If sharing permission is needed, Allow sharing continues that file preparation. Larger documents may upload before Send. A chat message always requires Send. Tap a draft chip to remove it, see details or explicitly retry a failed preparation. An upload with an unknown outcome is never automatically repeated.
- **Projects:** swipe a project right to Archive on this device. Archived projects opens the existing visibility controls to restore it. The computer folder and chats remain, and native server access is unchanged.
- **Connection recovery:** Settings offers Pair again when a fresh code is needed after the host address changes. Cancel returns to the previous connection and keeps the chat draft; forgetting the computer is not required first. The cancel-and-kept-draft journey passes on both Simulators.
- **Replies:** follow new content until the reader scrolls away. Return to the bottom or choose New replies to resume. The multi-reply follow, scroll-away and resume journey passes on iPhone and iPad Simulators; the physical check remains.
- **Models:** confirmed phone changes update the header immediately, and published native model/agent events refresh open settings. Unfinished edits are kept with an explicit reload notice. OpenCode desktop2.0.30 still keeps an unsent picker choice in local client storage and publishes it when sending. PocketWork cannot read that draft through the native API, so full immediate two-way picker synchronization is not completed by this app-side change.

The requested photo-flow correction changes the exact policy/help instruction about continuing preparation after consent. Its candidate copy remains unpublished pending owner review. Existing contacts, routing disclosures and data controls remain.

The affected five native UI journeys pass on iPhone and iPad Simulators. A separate largest-text check confirms Allow sharing and Cancel remain reachable on both. Debug/Release package tests and the normal Release bundle checks pass. The direct system picker and this candidate's physical-device journeys still need qualification. These checks do not qualify an installed OpenCode desktop patch.

The owner separately confirmed build9 fresh chat/follow-up, rename, photo preparation and image sending with an image-capable model. That is physical evidence for build9, not for this follow-up candidate. Public App Store release remains separate.

The actual Apple Photos picker now also passes through the native component keeper: system selection, sharing consent, Ready in the draft, explicit file-only send and clearing the selection. That opt-in run uses the real system picker and synthetic server transport. It does not qualify a live host or physical phone.

The normal Release live-pairing check reaches explicit address review and Connect, then fails while the advertised native HTTPS route is unavailable. The local API remains healthy; TLS handshake failures were independently observed from Mac and Linux. The live Release system-photo check remains unrun. Neither an advertised URL nor the component pass is evidence of a healthy remote connection.

Maintainers can opt into the seeded-Simulator picker mode of `NativeAppTests.testNativePhotoSelectionAndFileOnlySend` using `POCKETWORK_USE_SYSTEM_PHOTO_PICKER=1` and the matching `POCKETWORK_PHOTO_SIMULATOR_ID`. The separate `NativeJoinedInputTests` Release cases require `POCKETWORK_NATIVE_PHOTO_UI_CONFIG`, containing a fresh one-time native pairing and explicitly owned project/chat. Keep that configuration private. Pairing attempts are checkpointed rather than silently replayed; these checks never inject a Keychain credential.
