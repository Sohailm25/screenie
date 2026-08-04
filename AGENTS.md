# Screenie agent installation guide

## Scope

Use this runbook when a user asks you to install, configure, update, verify, roll back, or remove Screenie on their Mac. Reading this file does not authorize an installation, a cloud upload, or a paid Together API request.

Screenie runs on macOS 13 or newer. Building from source requires Swift 6 or newer. The project CI tests the source on macOS 15. The installed app lives in the menu bar and does not show a Dock icon.

## Request to give an agent

The user can send this request with a link to the repository:

```text
Install Screenie from https://github.com/Sohailm25/screenie by following its AGENTS.md.
Use the current-user install path ~/Applications/Screenie.app and do not use sudo.
Run the strict test suite, build from source, verify the app, and preserve any existing install as a recoverable backup.
Open the installed copy and pause when I need to approve macOS prompts or enter my Together API key.
Keep the API key out of chat, commands, files, logs, and clipboard inspection.
Do not send a screenshot to Together until I approve one small, non-sensitive test capture.
Report the installed commit, test result, signature result, Keychain-item presence, permissions, and whether a paid test ran.
```

Do not include the Together API key in that request. The user enters it into Screenie's masked field after installation.

Credential setup has two supported paths:

1. Preferred: the user types, pastes, or uses a password manager in Screenie's masked field while the agent waits.
2. A platform with a documented, non-logged secret-input channel can enter the key directly into that field.

Ordinary chat is not a secret-input channel. Revoke and replace any key pasted into chat before continuing.

## Rules for the agent

- Use `https://github.com/Sohailm25/screenie.git` as the source. Stop if an existing checkout points to another remote or contains local changes that an update would overwrite.
- Install for the current user at `${HOME}/Applications/Screenie.app`, without `sudo`.
- Build locally from source because the repository does not publish a signed and notarized release yet.
- Treat the key as an ephemeral secret. Keep it out of command arguments, environment variables, `.env` files, plists, temporary files, shell history, logs, Git, and agent messages.
- Leave the clipboard unread. `pbpaste`, clipboard-inspection tools, and computer-control arguments can expose a key or transcription in logs.
- Let Screenie create and read its own macOS Keychain item. `security add-generic-password` does not reproduce the app's credential flow.
- Reserve the cloud-upload disclosure and macOS Screen Recording prompt for the user. Scripted consent defaults and privacy pregrants are outside this runbook.
- Preserve Command-Shift-4, Gatekeeper, and quarantine settings. This runbook requires neither Homebrew nor a remote install script.
- Ask before any live capture test. Each completed capture uploads an image to Together and can incur charges.
- Use recoverable moves for an existing app or source checkout. Agent-written commands such as `rm -rf` and `git reset --hard` are outside this runbook. The repository's reviewed build script clears only its generated `dist` outputs.
- Leave screenshots and hidden `.screenie-capture-*` or legacy `.snaptext-capture-*` directories in place for the user to review.

## 1. Confirm the machine is ready

Before changing anything, explain that Screenie saves each selected region in the configured screenshot folder, sends it to `api.together.xyz`, and copies the returned transcription. While enabled, it also watches that folder for new Apple selection screenshots, including Command-Shift-4 captures.

Confirm that the user has:

- macOS 13 or newer
- network access to GitHub and `api.together.xyz`
- a writable screenshot folder
- an active Together account and API key

Run these read-only checks:

```sh
/usr/bin/sw_vers -productVersion
/usr/bin/xcode-select -p
/usr/bin/git --version
/usr/bin/env swift --version
```

Stop if macOS is older than 13 or Swift is older than 6. If Apple Command Line Tools are missing, ask the user to run `xcode-select --install`, wait for that installation to finish, and repeat the checks. Do not install another toolchain without the user's approval.

## 2. Get a clean source checkout

Use these defaults unless the user chooses another workspace:

```sh
set -euo pipefail
SCREENIE_SOURCE_DIR="${HOME}/Developer/screenie"
SCREENIE_APP_PATH="${HOME}/Applications/Screenie.app"

/bin/mkdir -p "${HOME}/Developer" "${HOME}/Applications"
/usr/bin/git clone --depth 1 --branch main \
  https://github.com/Sohailm25/screenie.git \
  "${SCREENIE_SOURCE_DIR}"
/usr/bin/git -C "${SCREENIE_SOURCE_DIR}" remote get-url origin
/usr/bin/git -C "${SCREENIE_SOURCE_DIR}" status --short
```

The reported remote must match the repository URL, and the status output must be empty. If `${SCREENIE_SOURCE_DIR}` already exists, do not clone over it. Verify and fast-forward that checkout with this block:

```sh
set -euo pipefail
SCREENIE_SOURCE_DIR="${HOME}/Developer/screenie"

/bin/test "$(/usr/bin/git -C "${SCREENIE_SOURCE_DIR}" remote get-url origin)" = \
  "https://github.com/Sohailm25/screenie.git"
/bin/test "$(/usr/bin/git -C "${SCREENIE_SOURCE_DIR}" branch --show-current)" = \
  "main"
/bin/test -z "$(/usr/bin/git -C "${SCREENIE_SOURCE_DIR}" status --porcelain)"
/usr/bin/git -C "${SCREENIE_SOURCE_DIR}" fetch --prune origin \
  refs/heads/main:refs/remotes/origin/main
/usr/bin/git -C "${SCREENIE_SOURCE_DIR}" merge --ff-only \
  refs/remotes/origin/main
/bin/test "$(/usr/bin/git -C "${SCREENIE_SOURCE_DIR}" rev-parse HEAD)" = \
  "$(/usr/bin/git -C "${SCREENIE_SOURCE_DIR}" rev-parse refs/remotes/origin/main)"
```

Continue to section 3 after either a fresh clone or a verified update. Inspect the bundle identifier of every existing `Screenie.app` or `SnapText.app` before choosing a path. Use section 4 when neither exists. Use **Update an existing install** only when one installed Screenie bundle has identifier `com.sohailmohammad.Screenie`. Use **Clean-reinstall Screenie and remove SnapText** when any bundle has identifier `com.sohailmohammad.SnapText` or multiple app bundles exist.

## 3. Test, build, and inspect the app

Run the same strict test command used by CI, then build the app:

```sh
set -euo pipefail
SCREENIE_SOURCE_DIR="${HOME}/Developer/screenie"

cd "${SCREENIE_SOURCE_DIR}"
./scripts/test.sh -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors
./scripts/build-app.sh

/usr/bin/plutil -lint dist/Screenie.app/Contents/Info.plist
/usr/bin/codesign --verify --deep --strict --verbose=2 dist/Screenie.app
/usr/bin/file dist/Screenie.app/Contents/MacOS/Screenie
/usr/libexec/PlistBuddy \
  -c 'Print :LSMinimumSystemVersion' \
  dist/Screenie.app/Contents/Info.plist
/usr/libexec/PlistBuddy \
  -c 'Print :CFBundleIdentifier' \
  dist/Screenie.app/Contents/Info.plist
```

Require all tests and verification commands to pass. The minimum system version must be `13.0`, the executable architecture must match the Mac, the display name and executable must be `Screenie`, and the bundle identifier must be `com.sohailmohammad.Screenie`. This identity is separate from SnapText's preferences, Keychain item, and TCC records. The build uses an ad-hoc signature because this repository has no Developer ID release. `codesign --verify` should pass; a Gatekeeper assessment can still reject an ad-hoc development build. Do not weaken Gatekeeper in response.

## 4. Install the built app

This block is for a first install. If the destination exists, stop and use the update procedure.

```sh
set -euo pipefail
SCREENIE_SOURCE_DIR="${HOME}/Developer/screenie"
SCREENIE_APP_PATH="${HOME}/Applications/Screenie.app"
SCREENIE_STAMP="$(/bin/date -u +%Y%m%dT%H%M%SZ)"
SCREENIE_INCOMING_PATH="${HOME}/Applications/Screenie.incoming-${SCREENIE_STAMP}.app"

/bin/test ! -e "${SCREENIE_APP_PATH}"
/bin/test ! -L "${SCREENIE_APP_PATH}"
/bin/test ! -e "${SCREENIE_INCOMING_PATH}"
/bin/test ! -L "${SCREENIE_INCOMING_PATH}"
/usr/bin/ditto \
  "${SCREENIE_SOURCE_DIR}/dist/Screenie.app" \
  "${SCREENIE_INCOMING_PATH}"
/usr/bin/codesign --verify --deep --strict --verbose=2 \
  "${SCREENIE_INCOMING_PATH}"
/bin/mv "${SCREENIE_INCOMING_PATH}" "${SCREENIE_APP_PATH}"
/usr/bin/codesign --verify --deep --strict --verbose=2 \
  "${SCREENIE_APP_PATH}"
/usr/bin/open "${SCREENIE_APP_PATH}"
```

Confirm that the Screenie icon appears in the macOS menu bar. Do not look for a Dock icon. If copying or pre-promotion verification fails, display the exact incoming path and move only that partial app to a unique Trash path before retrying. If promotion or post-promotion verification fails, move only the target created by this attempt to a unique Trash path.

## 5. Get consent and save the key

The user must review Screenie's cloud-upload disclosure. If the user chooses **Enable**, Screenie starts watching the configured folder and opens its key prompt. If the user first chooses another folder, Screenie remains paused; use the menu bar icon, choose **Enable Screenie**, approve the disclosure, and then choose **Set Together API Key…**.

The standard credential flow is:

1. Open the final installed copy at `${HOME}/Applications/Screenie.app`.
2. Pause for the user at Screenie's masked Together API key field.
3. Let the user type the key, use password-manager autofill, or paste it, then click **Save**.
4. Ask the user to copy harmless text afterward if the key passed through the macOS clipboard. This replaces the system clipboard value; it does not erase a clipboard manager's history. Ask them to clear that history if they use a clipboard manager.
5. Continue only after the user says the key was saved. Do not ask them to send it back.

An agent may enter the key only through a platform feature documented as a non-logged secret-input channel. Ordinary chat, terminal input, computer-control arguments, and tool-call arguments do not qualify.

Verify only that the Keychain item exists:

```sh
/usr/bin/security find-generic-password \
  -s com.sohailmohammad.Screenie \
  -a together-api-key \
  >/dev/null 2>&1
```

Report presence or absence. Presence proves that the Screenie item exists, not that a newly built app can read it without user approval. Never add `-w` or `-g`; those options can reveal the saved value.

If a key has already appeared in chat, tell the user to revoke it in the Together dashboard and create a replacement. The replacement goes directly into Screenie's masked field.

The Screenie Keychain service is `com.sohailmohammad.Screenie`; the account is `together-api-key`. Do not copy the legacy SnapText item. A migration starts with a fresh Screenie item entered through the masked field. Because development builds are ad-hoc signed, macOS can ask the user to approve a later Screenie build's access to an item created by an earlier build.

## 6. Approve Screen Recording and test

Command-Option-4 uses Apple's region selector and requires Screen Recording access. Accessibility, Input Monitoring, Automation, and Full Disk Access are not required.

Ask the user for permission before the first test. If approved:

1. Ask the user to display a small block of non-sensitive text.
2. Press Command-Option-4.
3. Let the user approve Screen Recording in **System Settings > Privacy & Security**. Reopen Screenie if macOS asks.
4. If the selector does not open, reopen Screenie if requested and press Command-Option-4 again.
5. Select only the agreed test region.
6. Wait for Screenie's success notice.
7. Ask the user to paste into a scratch document and confirm that the text is readable. Do not inspect their clipboard.
8. Confirm that the PNG was saved in the configured screenshot folder.

Command-Shift-4 remains a macOS shortcut. Screenie processes those selection screenshots through its folder watcher while the app is enabled.

If the user declines a paid test, report the installation as verified without an API smoke test. Do not create a capture to prove it works.

After a successful install, reclaim the build cache while keeping the small source checkout for updates:

```sh
SCREENIE_SOURCE_DIR="${HOME}/Developer/screenie"
/usr/bin/env swift package --package-path "${SCREENIE_SOURCE_DIR}" clean
```

Screenie does not add itself to Login Items. If the user wants it after every login, open **System Settings > General > Login Items** and let the user add `${HOME}/Applications/Screenie.app`. Do not create a LaunchAgent unless the user asks for one.

## 7. Report completion

Report these fields without exposing the key or clipboard contents:

```text
Source checkout: <absolute path>
Installed commit: <git commit SHA>
Installed app: <absolute path>
macOS and architecture: <values>
Swift: <version>
Strict tests: passed or failed
App signature: verified or failed
Cloud disclosure: approved, declined, or waiting for user
Keychain item: present, absent, or not checked
App Keychain access: approved, denied, waiting for user, or not tested
Screen Recording: granted, not granted, or not checked
Paid capture test: passed, failed, declined, or not run
Login Item: added, declined, or not requested
Backup retained: <absolute path or none>
```

## Update an existing install

1. Record the current commit, then run the existing-checkout block from section 2. It requires the `main` branch, a clean tree, the exact source remote, a fast-forward update, and a final SHA equal to `origin/main`.
2. Run the strict tests, build, and signature checks from section 3 before touching the installed app.
3. Copy the new bundle to a unique incoming path under `${HOME}/Applications` and verify that copy.
4. Ask the user to choose **Quit Screenie** from its menu.
5. Read `${HOME}/Applications/Screenie.app/Contents/Info.plist` and require `CFBundleIdentifier` to equal `com.sohailmohammad.Screenie`.
6. Move the installed bundle to a unique, timestamped backup under `${HOME}/Applications`.
7. Move the verified incoming bundle to `${HOME}/Applications/Screenie.app`, verify it again, and open it.
8. Keep the backup until the user confirms the new app starts. A rebuilt ad-hoc app can ask for Keychain and Screen Recording access again.
9. Ask before another paid capture test. After approval, move the old backup to the Trash.

Use an explicit UTC timestamp in incoming and backup names. Before each move, resolve and display every absolute source and destination. If a target already exists, stop instead of overwriting it.

If promotion, post-copy verification, or launch fails after the installed app moves to its backup, move the failed target to a unique Trash path. Restore the backup to `${HOME}/Applications/Screenie.app`, verify it, reopen it, and report the failed update.

## Clean-reinstall Screenie and remove SnapText

Use this path when permissions are mixed across SnapText, an early `Screenie.app` with the SnapText identifier, or more than one Screenie build. This procedure starts both app identities from clean state.

1. Finish the source update, strict tests, build, and bundle checks. Require the new bundle identifier to equal `com.sohailmohammad.Screenie`.
2. Copy the verified build to a unique incoming `.app` path under `${HOME}/Applications`, then verify its signature and identifier again. Do not open it.
3. Inventory every other `SnapText.app` and `Screenie.app`, including backups and build output. Read each Info.plist and classify it by `CFBundleIdentifier`: `com.sohailmohammad.SnapText` is legacy; `com.sohailmohammad.Screenie` is current. Stop on any other identifier.
4. Confirm that the user can retrieve their Together API key from its source without reading or printing it. Do not migrate either app Keychain item.
5. Quit every SnapText and Screenie process. Confirm that none remains before moving a bundle.
6. Register one exact legacy bundle, when present, and the verified incoming bundle with `lsregister -f`. Reset both permission identities before opening the new app, then unregister those exact paths. Do not reset the global LaunchServices database.

   ```sh
   /usr/bin/tccutil reset All com.sohailmohammad.SnapText
   /usr/bin/tccutil reset All com.sohailmohammad.Screenie
   ```

   If no legacy bundle exists and `tccutil` reports that the old identifier is unknown, leave the TCC database untouched and report that result. Never run `tccutil reset All` without a bundle identifier.
7. Move every inventoried app bundle and backup except the verified incoming bundle to unique paths in `${HOME}/.Trash`. Preserve ordinary screenshots and source checkouts.
8. With the user's approval, delete both exact preference domains: `com.sohailmohammad.SnapText` and `com.sohailmohammad.Screenie`.
9. With the user's approval, delete both exact Keychain items. Use account `together-api-key` once with service `com.sohailmohammad.SnapText` and once with service `com.sohailmohammad.Screenie`. Treat an item-not-found result as already clean. Do not delete the source from which the user will retrieve the key.
10. Move the incoming bundle to `${HOME}/Applications/Screenie.app`, verify it again, register only that path, and open it. After launch succeeds, remove the quarantined app bundles and generated build output so no second runnable bundle remains.
11. The user must approve the cloud-upload notice, enter the key through Screenie's masked field, and grant Screen Recording permission. Ask before a paid capture test. An ad-hoc rebuild can request Keychain or Screen Recording approval again.

If Screenie fails to launch, move it to a unique Trash path and report the failure. Restoring a removed build also restores its old permission identity, so do not do that during a requested clean reset without the user's direction.

## Roll back

1. Ask the user to quit Screenie.
2. Identify the exact timestamped backup selected by the user.
3. Require the backup's `CFBundleIdentifier` to equal either `com.sohailmohammad.Screenie` or the legacy `com.sohailmohammad.SnapText`.
4. Move the current `${HOME}/Applications/Screenie.app` to a unique path in `${HOME}/.Trash`.
5. Read the backup's executable and identifier. Restore any `Screenie` executable as `${HOME}/Applications/Screenie.app`; its identifier can be the current Screenie value or the legacy SnapText value. Restore a `SnapText` executable with the legacy identifier as `${HOME}/Applications/SnapText.app`. Stop on any other pair.
6. Verify the restored bundle's signature and open that exact path.

Screenie and SnapText use separate Keychain, preference, and TCC identities. Restoring one app does not restore state deleted from the other identity. macOS can request permission again after switching ad-hoc builds. Do not reset the source checkout as part of an app rollback.

## Uninstall

1. From the Screenie menu, choose **Remove API Key…** and confirm.
2. Choose **Quit Screenie**.
3. Read the installed app's Info.plist and require `CFBundleIdentifier` to equal `com.sohailmohammad.Screenie`.
4. Move the exact installed app and any confirmed backups to unique paths in `${HOME}/.Trash`.
5. Inventory hidden `.screenie-capture-*` and legacy `.snaptext-capture-*` directories in the configured screenshot folder. Explain that a leftover can contain an unpublished capture. Move only user-approved, exact paths to the Trash.
6. Leave ordinary screenshots untouched.
7. Preserve a source checkout with local changes. A clean checkout with the expected remote can be moved to the Trash after the user approves.

With separate user approval, remove preferences and reset the app's Screen Recording entry:

```sh
/usr/bin/defaults delete com.sohailmohammad.Screenie
/usr/bin/tccutil reset All com.sohailmohammad.Screenie
```

If the app is already gone and the user asks to remove its saved key, delete only this exact Keychain item:

```sh
/usr/bin/security delete-generic-password \
  -s com.sohailmohammad.Screenie \
  -a together-api-key
```

## Common failures

| Symptom | Action |
| --- | --- |
| `xcode-select` or Swift is missing | Install Apple Command Line Tools with user approval, then repeat preflight. |
| Swift is older than 6 | Stop and ask before installing another toolchain. |
| Source directory already exists | Verify its remote and clean status; use the update flow. |
| App has no Dock icon | Check the menu bar. Screenie is a menu-bar app. |
| Key prompt did not appear | Choose **Set Together API Key…** from the Screenie menu. |
| Command-Option-4 does nothing | Enable Screenie, check Screen Recording access, and check for a shortcut conflict. |
| Command-Shift-4 is not processed | Confirm Screenie is enabled and watching the folder where macOS saves screenshots. |
| Clipboard did not change | Open Screenie's menu and check **Copy Ready Text**; Screenie preserves a result when the clipboard changes during processing. |
| Gatekeeper rejects the development app | Rebuild from the local checkout. Do not disable Gatekeeper or strip quarantine recursively. |
| Together rejects the request | Let the user replace the key through **Set Together API Key…**. Do not print or inspect the saved key. |
