# Registered skills

Use the composer plus button to browse, search and preview skills already registered in the selected native OpenCode location. Previewing text does not execute it. Select skills to include them as instructions when you deliberately send, including a skill-only message where supported.

PocketWork saves the selected ID/name/version fingerprint with the draft. Before sending, it checks that the registered version still matches. OpenCode resolves the skill at admission and may add related file names or plugin content; this is not an atomic server lock on the previewed version. A changed/unavailable choice needs review.

The normal JSON budget is 8 MiB. Native skill catalogs have a separate 16 MiB budget after an actual 8.5 MB Mac catalog exceeded the normal budget; individual skill content is limited to 1 MiB. Large previews use bounded display. Sent history labels show selected skills without rendering their full materialized instructions as ordinary chat messages.

Host skill creation/editing and scheduled work stay in OpenCode. Local selection is not a tool grant, and existing chat rules/approvals still apply. Reset removes local selections, not host skill files.

Scoped Mac/NUC materialization checks used synthetic instructions and disabled provider execution. Simulator selection/preview/file-only flows are separate from pending physical and final execution evidence. See [compatibility](opencode-compatibility.md).
