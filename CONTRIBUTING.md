# Contributing

Keep the app simple, keep permission choices explicit, and test changes against the host protocol.

For a change, fork the repository and open a pull request against `main`. Explain the problem, what changed, and what you actually tested. Include Simulator screenshots for visible changes. Clearly label Simulator results, physical-device results, and host compatibility checks.

Before submitting:

```sh
swift test
xcodebuild -project OpenWorkRemote.xcodeproj -scheme OpenWorkRemote \
  -configuration Debug -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO build
```

If you add app files, regenerate the checked-in Xcode project with `python3 scripts/generate-ios-project.py`. Keep both the generated project and source changes in the same PR. The core test fixtures must stay synthetic.

Don't commit local signing changes, credentials, host data, or chat transcripts. Don't weaken TLS, add arbitrary upstream forwarding, or make approvals automatic. Use private reporting for vulnerabilities, as described in [SECURITY.md](SECURITY.md).

By contributing, you agree to license your contribution under this repository's MIT license. Sign off commits with `git commit -s` to certify the [Developer Certificate of Origin](https://developercertificate.org/). The owner reviews changes and controls repository write access.
