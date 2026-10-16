# Photos and files

Delivered internal TestFlight 1.0.0 (9) uses the earlier attachment sheet: choose the plus button in a selected chat, then Choose photos or Browse files. If preparation stops for sharing review, allow it and retry the selected action. The direct flow below is in the next source candidate and is not delivered yet.

## Direct selection in the source candidate

1. In a selected chat, tap **+ → Photos** or **+ → Files**. This opens Apple's system picker directly.
2. Choose a supported photo or PDF. It is added to this chat's draft and prepared automatically; there is no additional Add to message step.
3. If sharing review is required, review it and choose Allow sharing. Only the file that paused for that review continues preparation. Cancel keeps it unprepared; uncertain uploads are not replayed.
4. Wait for the Ready chip, then explicitly choose Send when the message is ready. Selecting a photo or allowing preparation never sends the message by itself.

Tap a draft attachment to inspect its status, remove it or explicitly retry a failed preparation. A Ready chip means preparation completed, not that the model has read the file. The system pickers control selection; PocketWork does not request unrestricted photo-library access.

## Formats and limits

Photos become PNGs up to 2,000 pixels on the longest edge. Original location/camera metadata is not copied, and the original photo is unchanged. Files supports PDF and supported JPEG/HEIC/PNG photos. Choose up to four files, 20 MiB each and 40 MiB total raw selected data. Native encoded-body limits are checked before admission and can impose a lower limit.

The selected model must support the relevant image/PDF input. A text-only model cannot read an image merely because the upload succeeded. Larger supported documents may use OpenCode's temporary-file staging instead of inline data.

## Sharing and removal

Before preparation, review the reported AI-sharing context. If the final provider route cannot be verified, the concise review explains that uncertainty. In the candidate, allowing this review continues only the intended paused file; it does not authorize a message send or replay an unknown upload. Unchanged reviewed context does not require a new review for every selection.

A prepared document may already exist on the computer before Send. Removing it from the composer or resetting the phone does not delete that host copy. Staging follows the official native mechanism under a fresh app-owned upload directory, not a destination typed into the phone.

Keep the selected chat/folder fixed while preparing. Connection or folder changes cannot silently move the selection into another chat. An unconfirmed upload/send is never automatically repeated. See [migration/recovery](migrating-from-openwork.md).

Scoped Mac/NUC transfer/admission checks include two 20 MiB PDFs with execution disabled. Build9 physical iPhone evidence confirms photo preparation and actual image sending with an image-capable model. The candidate's actual Apple Photos picker/Ready draft passes on a normal Release iPad Simulator without sending; new candidate physical Files/share/network acceptance remains open. [Results and sharing](ARTIFACTS.md) is a separate flow.
