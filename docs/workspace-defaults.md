# Workspace default model

In Settings, open **Workspace settings → Defaults**. Choose a model and available reasoning level, then tap **Save for new chats**. Existing chats keep their model. Provider accounts and tool approvals are unchanged.

The paired computer must advertise `workspaceDefaults`, permit this workspace, and grant this phone **Workspace administration** in Remote access. Unsupported or denied access explains what to change on the computer; it never silently saves. A workspace without an assigned default shows that explicitly and requires choosing a model.

The new native conditional-write API rejects a stale selection atomically. Refresh shows the computer’s current default without discarding your unsaved selection; use **Use current default** to accept a newer baseline. Model-picker navigation and local dismissal do not wait for network requests.

Each explicit save persists one UUID, workspace, selection and native revision in protected `workspace-defaults.json`. A lost response or revocation after dispatch stays unconfirmed. Refresh and **Keep current default** accept the latest computer state without claiming that the earlier phone request succeeded or automatically retrying it.

Mac and Ubuntu NUC source previews passed native paired HTTPS Simulator saving, stale rejection, receipt replay, new-chat inheritance and existing-chat model preservation. Disposable chats/workspaces and temporary pairings/mappings were removed; original settings and active workspace were restored. Fresh untitled chats also have a guarded delete regression. Physical-device acceptance and the full candidate remain separate. **TestFlight build 5 excludes this feature.**

![Synthetic native default screen](images/workspace-defaults.png)
