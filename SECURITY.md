# Security policy

## Supported code

Security fixes are made on the default branch. Builds from earlier commits are not maintained.

| Code | Security fixes |
| --- | --- |
| Default branch | Yes |
| Earlier commits and third-party builds | No |

## Reporting a vulnerability

Use GitHub's private vulnerability reporting when it is enabled for this repository. Include the affected commit or version, macOS version, reproduction steps, expected behavior, observed behavior, and the security impact.

Do not put API keys, screenshots, clipboard contents, access tokens, or exploit details in a public issue. If private vulnerability reporting is unavailable, contact the maintainer through the [Sohailm25 GitHub profile](https://github.com/Sohailm25) and ask for a private reporting channel.

Public issues are appropriate for bugs that do not expose private data, credentials, or a working exploit.

## Sensitive components

SnapText handles three sensitive values:

- Screenshot files can contain credentials, customer data, private messages, or source code.
- The Together API key authorizes paid inference requests.
- Model responses can contain text copied from the screenshot.

The app stores the API key in the macOS Keychain. Screenshot data and the API key travel to Together over HTTPS for inference and authentication. SnapText does not persist a response history or a second copy of the screenshot.

Command-Option-4 launches the fixed executable `/usr/sbin/screencapture` with a fixed argument shape and an exact generated output path. SnapText does not invoke a shell, search `PATH`, run AppleScript, or pass its own environment to the child. The child environment contains only `LANG` and `PATH`, so it does not inherit `TOGETHER_API_KEY` or other shell secrets.

Direct captures start in a generated hidden directory with owner-only permissions. SnapText verifies that the output is a nonempty regular file, records its device and inode, and moves it to a unique visible PNG path without overwriting an existing file. The image loader opens the published path without following symbolic links and checks that the identity still matches before upload.

SnapText checks the clipboard change counter before writing, which avoids the common case where a completed request replaces text that you copied while waiting. AppKit exposes comparison and writing as separate operations, so another process can still change the clipboard between SnapText's final check and write. The check also does not prevent another process with clipboard access from reading the final transcription.

## Distribution

The repository build script applies an ad-hoc signature and labels the zip with the build Mac’s architecture. That signature lets macOS validate the bundle's internal code, but it does not identify the publisher and it does not notarize the app. GitHub CI artifacts are development builds.

Release maintainers should sign the app with a stable Developer ID certificate, enable hardened runtime settings appropriate for the final bundle, notarize the archive with Apple, and publish checksums with each release. Screen Recording approval is tied to code identity, so rebuilding an ad-hoc signed app can make macOS ask for permission again. Users of an unnotarized build should inspect the source and build it locally.

Rotate the Together API key if it appears in logs, screenshots, shell history, a public issue, or a committed file.
