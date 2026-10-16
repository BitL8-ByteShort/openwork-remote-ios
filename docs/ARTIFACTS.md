# Results, previews and sharing

In the source candidate, tap the top project/model area and choose **Files from this chat**. The duplicate entry is removed from the conversation. This list shows supported results from structured OpenCode metadata. It does not treat an arbitrary path mentioned in assistant prose as a downloadable file. You can also browse supported files in the selected project.

Choose a file, download its bounded local copy, then preview or explicitly share it through the system share sheet. Nothing is automatically exported. iPad sharing uses an anchored native presentation. Active HTML/scripts are not executed by the preview.

Reads stay within the selected native project location and a validated relative path. Traversal, external URLs and outside-project symlink targets are rejected. Downloads are capped at 20 MiB and version-checked; changed bytes are not assembled into one mixed-version file. Unsupported/oversized results hand off to the computer.

**Clear downloads** removes app-owned local copies and reports failures. Reset does not remove files already shared elsewhere, host originals or staged uploads. Native pairing still grants server-wide access; these app read checks and project display filters are not a per-phone server sandbox.

Mac and NUC scoped download/containment checks and Simulator preview/export journeys exist. Real physical sharing, the final joined native candidate and App Store release remain pending. See [compatibility](opencode-compatibility.md) and [privacy copy](../OpenWorkRemote/Resources/Information/privacy.txt).
