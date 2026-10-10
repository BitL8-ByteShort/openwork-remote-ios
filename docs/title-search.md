# Search older chat titles

Open **Your chats → Search older chats**. Enter a title phrase to search the
selected workspace on the computer, independently of the visible group filter.
Typing waits 300 ms before reading. **Load more matches** or **Continue search**
checks the next batch. The checked-title count distinguishes unfinished coverage
from a completed search; an unfinished empty batch does not claim no matches.
Opening a result dismisses immediately while its messages load. Back and Done
remain local while a request is pending, and the original loaded list is retained.

The host performs case-insensitive, Unicode compatibility-normalized title
matching: 1–200 Unicode scalars, at most 500 titles/10 native pages scanned and 50
matches returned per request. It reads metadata, never every transcript. Native
concurrent renames/list changes may appear after starting a fresh search; this is
not a snapshot or message-content search. Very broad match sets require narrowing
the phone query. A scan has a 5-minute cursor lifetime and a 1,024-native-page
limit; restart/refine the query or use the computer after those limits.

Only explicitly qualified computers advertise search. Project access is checked
fresh; it does not require or expand file/admin/automation grants. Unsupported
computers retain a visible handoff. Stale queries, changed connections/workspaces,
backgrounding and revoked access cannot publish another context's results.

Queries, result titles/IDs and counts travel over paired HTTPS and stay in transient
phone memory. The computer holds bounded transient continuation metadata (up to
four cursors/device, 256 total), scoped to device/workspace/normalized query. No
transcript index, on-disk search history or AI prompt is created by searching.

Mac and actual Ubuntu NUC passed 227 bridge tests/typecheck/build with 46 matching
production files. Read-only paired HTTPS/native Simulator searches found and
opened older existing titles on both hosts; each live workspace had fewer than
50 chats, while synthetic tests cover matches beyond 50 and 500-row continuation.
All temporary credentials/mappings were removed with existing state preserved.
56 core/73 state tests, three synthetic UI flows, both paired native flows and a
Release Simulator/DEBUG-exclusion check passed. Existing UIKit toolbar warnings
remain. Penpot SR-01 guides the screen. Build5 excludes this feature; physical
iPhone/iPad and full-candidate qualification remain open.

![Synthetic older-title search](screenshots/title-search.png)
