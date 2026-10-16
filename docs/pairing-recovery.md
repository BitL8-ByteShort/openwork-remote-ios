# Pairing and reconnecting

Use compatible OpenCode v2's built-in **Remote access → Pair device**, then scan its QR code or paste its link in PocketWork. Review the selected HTTPS address. The inspected 2.0.29 code expires after five minutes and can be used once. Create a fresh code when it expires or has already been redeemed.

For a CLI-only host, run `opencode pair --remote` on the computer. This uses OpenCode's native remote address and asks before enabling Remote access when needed. Scan its QR or paste the HTTPS link. Localhost links refer to the device opening them; use the advertised HTTPS remote link on the phone. The app already handles a QR containing both local HTTP and remote HTTPS addresses.

The next source candidate also supports **Use server password** with the standard OpenCode HTTPS address and server password. Review the exact destination before Connect. This requests and redeems a fresh native code; PocketWork saves only the issued pair token and clears the transient password after the attempt, cancellation or backgrounding. Apple's separate Passwords save choice is optional. This is the OpenCode server password, not a provider API key or computer-login password. It requires no OpenCode fork, plugin or patch and is independent of QR/link pairing. It is not in delivered build9 yet; the candidate's narrow-iPad password/background crash remains a release hold.

In the candidate, **Settings → Pair again** starts fresh pairing while preserving the previous saved connection and draft until a replacement succeeds. A failed single-use redemption offers **Use a fresh pairing code**; it does not replay Connect with the consumed code.

A saved credential reconnects without redeeming that old code again. Check that the computer is awake, OpenCode is running and Remote access is enabled. A temporary network error is not a reason to rotate the server password. Unsupported native versions can be blocked from writes.

If OpenCode rejects the credential, choose **Pair again** and use a fresh native pairing. An obsolete request from a retired connection cannot replace the new connection. No connection recovery automatically resends an unconfirmed prompt.

Pairing grants server-wide access. Project visibility is a local list filter. **Forget** removes the saved credential on this device; it does not invalidate copies on the server or stop work. The tested version has no individual phone-revocation contract. Server-password rotation affects all paired credentials, so do it only deliberately on the computer.

Earlier OpenWork credentials cannot connect to OpenCode. Local text recovery and reset limits are in [migration](migrating-from-openwork.md). See [Security](../SECURITY.md) and [compatibility](opencode-compatibility.md). Native source checks and scoped host pairing evidence are not final physical network-transition acceptance.
