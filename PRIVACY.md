# Privacy

Command-Option-4 opens Apple’s region selector. Finishing a selection saves a PNG in your configured screenshot folder and sends it to Together AI without another confirmation. SnapText uses a cloud vision model, so accepted images leave your Mac.

While SnapText is enabled, it also processes new files carrying Apple’s selection screenshot metadata. This includes captures made with the native Command-Shift-4 shortcut. Those attributes are a detection heuristic and can be copied or created by another process.

The **Process Latest Screenshot** action is explicit. It sends the newest supported image in the chosen folder even when that file lacks Apple screenshot metadata.

## Data sent to Together AI

For each processed image, SnapText sends the following data to `https://api.together.xyz/v1/chat/completions`:

- The screenshot as a base64-encoded image
- A transcription prompt
- The selected model name and inference settings
- Your Together API key in the HTTPS authorization header

Together returns the transcription as text. Together's handling of requests is governed by its [privacy and security documentation](https://docs.together.ai/docs/privacy-and-security), [privacy policy](https://www.together.ai/privacy), and the settings on your Together account.

Do not capture data that you are not authorized to send to Together. This includes customer information, credentials, private keys, health records, financial records, and confidential source code when your policy prohibits cloud processing.

## macOS permissions

The Command-Option-4 path requires Screen Recording permission because SnapText launches Apple’s capture utility. SnapText checks for access before each direct capture and requests it when access is absent. Folder monitoring does not require Screen Recording access.

SnapText registers one fixed global shortcut. It does not request Accessibility, Input Monitoring, Automation, Full Disk Access, or microphone permission.

## Data kept on the Mac

SnapText stores:

- The Together API key in the macOS Keychain with device-only access while the device is unlocked
- The selected model, monitoring state, upload-consent version, and screenshot folder preference in macOS app preferences
- A folder security bookmark when macOS requires one

For a screenshot detected by folder monitoring, macOS saves the original in the configured folder. SnapText does not delete, move, rename, or edit that file.

For Command-Option-4, SnapText creates a hidden staging directory with owner-only permissions inside the screenshot folder. It asks Apple’s capture tool to write one PNG there, then moves the PNG to a unique visible filename. Cleanup is best-effort. A cleanup error, force-quit, Mac shutdown, or quit during an active selector can leave the hidden directory and PNG behind. If the move to a visible name fails, SnapText keeps the staged PNG and reports its path.

SnapText keeps an in-flight response in memory when clipboard conflict protection blocks an automatic copy. The value is removed when you replace it with a newer result or the app exits.

## Data SnapText does not keep

SnapText does not create a request history, transcription database, screenshot cache, analytics profile, or telemetry log. The app makes no analytics or advertising requests.

Build tools, macOS, Together AI, or a distributor can have separate logging and retention behavior. Their policies apply outside SnapText's process.

## Clipboard access

SnapText reads the clipboard change counter before inference. It writes the transcription only if the clipboard has not changed during the request. The app does not send existing clipboard contents to Together.

Apple’s interactive selector sends a screenshot to the clipboard when Control is held during selection. In that case no output file is created, SnapText makes no Together request, and the Apple-produced image remains on the clipboard. SnapText reports that the clipboard changed.

Other applications on the Mac can read clipboard contents according to macOS permissions and behavior. Copying a transcription can expose it to clipboard managers or synchronization services installed on the system.

Command-Option-4 and automatic monitoring share a cap of 12 processing attempts in a rolling 60-second window. Manual **Process Latest Screenshot** requests remain available after that cap. SnapText also rejects image payloads over 16 MiB before base64 encoding, images over 64 megapixels, and images with a side longer than 16,384 pixels. These are limits chosen by the SnapText project.

## Controls

Pause SnapText or quit the app before taking a screenshot that should remain local. Pausing unregisters Command-Option-4 and stops folder monitoring. You can remove the Together API key from the menu, choose a different screenshot folder, or delete saved screenshots and abandoned hidden staging directories through Finder.

Pausing or quitting cancels local processing. It cannot retract an image that Together already accepted, and that request can still incur a charge.

Together account privacy settings and data requests are managed through Together. See the linked Together policies for current controls and contact details.
