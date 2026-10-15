# Photos and files

This guide describes the native OpenCode integration available in internal TestFlight1.0.0(9). Physical picker/share acceptance remains separate.

Choose the plus button in a selected chat, then **Choose photos** or **Browse files**. Native attachments support normalized PNG photos and PDF documents. Photos become PNGs up to 2,000 pixels on the longest edge; original location/camera metadata is not copied, and the original photo is unchanged. The system pickers control selection; the app does not request unrestricted photo-library access.

Choose up to four files, 20 MiB each and 40 MiB total raw selected data. The selected model must support the relevant image/PDF input. Larger supported documents may use OpenCode's temporary-file staging instead of inline data. File-backed preparation and native body limits are checked before admission; a prepared row alone is not proof the model read it.

## Sharing and removal

Before preparation, review the reported AI-sharing context. If the final provider route can't be verified, PocketWork says so and requires deliberate review. Approving the review does not upload or send automatically; retry the intended action yourself.

A prepared document may already exist on the computer before Send. Removing it from the composer or resetting the phone does not delete that host copy. Staging follows the official native mechanism under a fresh app-owned upload directory, not a destination typed into the phone.

An unconfirmed upload/send is not automatically repeated. Keep the selected chat/folder fixed while preparing. Connection or folder changes cannot silently move the selection into another chat. See [migration/recovery](migrating-from-openwork.md).

Native transfer/admission, including two 20 MiB PDFs, has scoped Mac/NUC evidence with execution disabled. Physical photo/file pickers, model execution and joined recovery remain release checks. [Results and sharing](ARTIFACTS.md) is a separate flow.
