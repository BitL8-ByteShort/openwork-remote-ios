# Continue, fork and delete chats

Long-press a chat in **Your chats** and choose **Continue in a new chat** to copy
the whole conversation with its model/settings. At a message, **Fork before this
message** copies only the earlier messages; the selected message is excluded.
The original chat and its files remain intact. A confirmation precedes creation.

**Delete chat** names the target and requires a separate confirmation. It
permanently removes that chat/history from OpenWork on the computer. It is not
archive and has no qualified undo. Workspace files remain on the computer.
Running chats and chats with linked subchats require action on the computer.
Keep the target idle there until the phone operation finishes: native preflight
is not an atomic conditional write against concurrent desktop changes.

The computer must explicitly advertise qualified fork/delete support, and the
phone must have access to the project. These actions do not expand project access,
transfer files, run prompts or require the additional file/admin grants.
Cancel, Keep chat and dismissal respond locally even while checking the computer.

## Recovery and data

Before dispatch, a protected intent saves the host/workspace/chat, stable UUID,
captured revision, action and phase. It contains no transcript or credentials.
A confirmed operation clears only its intent; confirmed deletion clears only
that chat's local draft/selection. The original draft is preserved on a fork.

If the outcome is unknown, the app does not submit another request automatically.
**Check recent chats** reads the current scoped list. After review, **Keep current
chats** clears the local uncertainty without claiming the operation succeeded.
Revocation/backgrounding or changing context prevents late replies from updating
another chat. Reopening an unresolved intent never resends it. The host's durable
receipt is authorized before replay and remains bound to device/route/body.

## Qualification

Mac and actual Ubuntu NUC passed 213 bridge tests, typechecks and builds with 44
matching production files. Paired HTTPS Simulator flows on each host created a
whole copy and deleted only that copy. A separate scoped flow verified exclusive
boundary/model/provenance and receipt replay after deletion. Native file payloads
and source messages were retained. Temporary pairings/mappings were removed;
existing host state and pairing/ledger were preserved. Linked-subchat blocking
has targeted unit coverage; this does not claim a live subagent-cascade test.

The native provenance field is `fork.sessionID`. `parentID` belongs to linked
subchats, so an independent fork does not block its source's deletion. Deletion
is confirmed by the measured missing-session code and a readable scoped list;
forbidden reads and generic 404s never count as confirmation.

Core/state tests, six synthetic native flows, paired Mac/NUC flows and a Release
Simulator build passed. Public screenshots use synthetic content. Penpot CA-01
and CA-02 guide the implementation. Physical iPhone/iPad and full-candidate
qualification remain open. Internal TestFlight 0.1.0 (5) excludes this feature.

![Continue confirmation](screenshots/chat-continue.png)
![Delete confirmation](screenshots/chat-delete.png)
