# Pairing and reconnecting

Use compatible OpenCode v2's built-in **Remote access → Pair device**, then scan its QR code or paste its link in PocketWork. Review the selected HTTPS address. The inspected 2.0.29 code expires after five minutes and can be used once. Create a fresh code when it expires or has already been redeemed.

A saved credential reconnects without redeeming that old code again. Check that the computer is awake, OpenCode is running and Remote access is enabled. A temporary network error is not a reason to rotate the server password. Unsupported native versions can be blocked from writes.

If OpenCode rejects the credential, choose **Pair again** and use a fresh native pairing. An obsolete request from a retired connection cannot replace the new connection. No connection recovery automatically resends an unconfirmed prompt.

Pairing grants server-wide access. Project visibility is a local list filter. **Forget** removes the saved credential on this device; it does not invalidate copies on the server or stop work. The tested version has no individual phone-revocation contract. Server-password rotation affects all paired credentials, so do it only deliberately on the computer.

Earlier OpenWork credentials cannot connect to OpenCode. Local text recovery and reset limits are in [migration](migrating-from-openwork.md). See [Security](../SECURITY.md) and [compatibility](opencode-compatibility.md). Native source checks and scoped host pairing evidence are not final physical network-transition acceptance.
