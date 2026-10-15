# Contributing

Keep PocketWork simple, keep permission choices explicit, and test the native OpenCode behavior you change.

Fork the repository and open a pull request against `main`. Describe the concrete problem and resulting behavior, then record what you actually tested. Include synthetic-data screenshots for visible changes. Separate source checks, Simulator checks, real Mac/Linux host results, physical-device results and distribution status.

The OpenCode candidate targets 2.0.29. Don't infer contracts from earlier OpenWork fixtures. Prefer a small typed native adapter over arbitrary path forwarding, and keep connection/project/chat/folder identity across asynchronous work. Never automatically replay an uncertain mutation or approve a tool request.

```sh
swift test
python3 scripts/generate-ios-project.py
xcodebuild -project OpenWorkRemote.xcodeproj -scheme OpenWorkRemote \
  -configuration Debug -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO build
```

Regenerate the checked-in project after adding app files and commit the source and generated change together. Use [testing instructions](docs/testing.md) for native fixtures and opt-in host checks. Keep test data synthetic. Real write tests own an explicitly disposable chat/folder and must preserve unrelated host settings and sessions.

Canonical offline information is in `OpenWorkRemote/Resources/Information/`. New policy text needs concrete owner review before publication. While approval is false, use a local draft directory:

```sh
python3 scripts/generate-information-site.py --allow-draft --output /tmp/pocketwork-policy-review
```

Do not generate an unapproved draft into the public `docs` site. After approval, normal generation must be deterministic and match the bundled text. Approval of an older policy doesn't authorize new data-handling claims.

Don't commit local signing changes, credentials, host data or chat transcripts. Don't weaken TLS or add automatic approvals. Use private reporting as described in [Security](SECURITY.md). Changes to the historical OpenWork fork are outside this migration unless explicitly scoped.

Contributions use this repository's MIT license. Sign off contributions with `git commit -s` to certify the [Developer Certificate of Origin](https://developercertificate.org/). The owner controls repository write access and integration; opening a public issue or pull request grants no push permission.
