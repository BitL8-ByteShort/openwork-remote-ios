# Reply rendering and responsiveness

The OpenCode migration is a source candidate. These checks don't establish physical-device latency or an App Store release.

Short replies keep inline formatting and code blocks in the chat. Unusually large or dense replies show **Read reply**. The reader has one page of plain text at a time, fixed Previous/Next controls, Done, and **Copy entire reply**. No text is truncated. Required approvals and questions stay outside compact Activity.

## Rendering limits

Formatting runs in a cancellable worker, outside the UI actor. A view keeps its last completed render while a replacement is prepared. Navigating away or receiving a newer version cancels obsolete preparation. There is no global transcript-render cache or additional saved copy.

Inline formatting is bounded to 128 KiB of source, 256 blocks and 4,000 Unicode scalars per individual block. A reply exceeding any bound uses plain-text pages of at most4,000 Unicode scalars. The pages retain the original UTF-8 bytes when joined. Copying the entire reply includes its Markdown and code fences. Code blocks that remain inline scroll both horizontally and vertically.

## Measured evidence

On October 15, optimized Mac parsing of a synthetic 2 MiB reply took 375–383ms with the previous synchronous algorithm. The worker/page preparation took 3.3–4.2ms in the recorded follow-up. These are Foundation-only preparation measurements, excluding SwiftUI layout, network transfer and physical taps. The bounds also avoid creating tens of thousands of formatted views for that reply.

Six preparation checks cover code/Unicode preservation, byte-sensitive update identity, dense blocks, individual oversized blocks, full paged content and cancellation. The full package run passed 165 core checks and 220 reported state checks, with nine live opt-in checks skipped (211 state checks executed).

Small-iPhone (iOS 26.5) and iPad (iPadOS 27) Simulator checks cover normal and maximum text sizes, page navigation, local reader dismissal and Settings dismissal while the model catalog request is delayed 30 seconds. Immediate tap-plus-element-query timing was about 1.16 seconds, including XCTest automation and animation. An earlier 2.23 second result included the test framework's roughly one-second existence poll after dismissal; that poll was removed from the measurement, without increasing the two-second test budget. Neither result is a physical tap-to-pixel measurement.

An initial inline pager failed the maximum-text small-phone check because the required-input cards left too little room to reach its controls. The separate reader replaces that implementation. A separate code-block journey scrolls to a visible final-line marker.

## Remaining qualification

Physical VoiceOver, real streaming, reconnect/offline transitions and uploads still need the joined release-candidate matrix. The earlier intermittent button delay isn't declared fixed by these synthetic checks. See [accessibility qualification](accessibility-qualification.md) and [OpenCode compatibility](opencode-compatibility.md) for the other evidence boundaries.
