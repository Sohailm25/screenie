# SnapText

SnapText turns a selected macOS screen region into copy-ready Markdown. Press <kbd>Command</kbd>+<kbd>Option</kbd>+<kbd>4</kbd>, drag Apple’s region-selection box, and wait for the result to reach your clipboard.

SnapText owns the new Command-Option-4 shortcut. It opens Apple’s selector, saves the PNG in your configured screenshot folder, sends the image to Together AI, and copies the model response. The native Command-Shift-4 shortcut remains under macOS control and works through SnapText’s folder watcher.

## Processing flow

1. Command-Option-4 opens Apple’s standard region selector.
2. SnapText waits for the selection to finish, validates the PNG, and saves it in your screenshot folder.
3. The app sends the image to `Qwen/Qwen3.5-9B` through Together's chat completions API. Thinking and reasoning are disabled so the model does not generate reasoning tokens.
4. The model returns Markdown that preserves text structure and renders charts, plots, and informational diagrams as fenced ASCII art.
5. SnapText writes the result to the clipboard if the clipboard has not changed since processing started.

The endpoint call starts after the selector closes and the PNG passes validation. It does not wait for a folder event. If you use Command-Shift-4 instead, the watcher detects the new Apple-tagged selection screenshot and starts the same processing path.

If you copy something else while the request is running, SnapText keeps the model response in memory. Choose **Copy Ready Text** from its menu bar menu when you want that result.

## Requirements

- macOS 13 or newer
- A Swift 6 toolchain from Xcode or Apple Command Line Tools
- A [Together AI API key](https://api.together.ai/settings/api-keys)
- macOS configured to save screenshots as files
- Screen Recording permission for the Command-Option-4 capture path

Each processed screenshot makes a Together API request and can incur usage charges on the account tied to the API key.

## Build from source

```sh
git clone https://github.com/Sohailm25/screenie.git
cd screenie
./scripts/build-app.sh
open dist/SnapText.app
```

The repository excludes build caches and generated app bundles. The script builds the release executable with Swift Package Manager, assembles `dist/SnapText.app`, applies an ad-hoc signature when `codesign` is present, and creates an architecture-labeled zip such as `dist/SnapText-arm64.zip`. The binary targets the Mac that built it. CI artifacts are development builds. A public release should build both architectures, use a Developer ID signature, and notarize the archive before distribution.

## First launch

1. Open SnapText. Its icon appears in the menu bar.
2. Review the cloud-upload disclosure. Enable SnapText, or choose a different screenshot folder and then enable it from the menu.
3. Add your Together API key when prompted. The app stores it in the macOS Keychain.
4. Press <kbd>Command</kbd>+<kbd>Option</kbd>+<kbd>4</kbd>. Grant Screen Recording access when macOS asks, then reopen SnapText if the system requires it.
5. Select a region. The PNG is saved to the configured folder, sent to Together, and transcribed to the clipboard.

The menu also lets you pause SnapText, run the capture action without the shortcut, process the latest screenshot, copy a pending result, switch models, change the watched folder, or remove the API key. The manual processing action accepts the newest supported image even when Apple metadata is unavailable.

## Model and prompt behavior

The default model is [`Qwen/Qwen3.5-9B`](https://www.together.ai/models/qwen3-5-9b). SnapText sends a base64-encoded image to Together's OpenAI-compatible chat completions endpoint and disables Qwen's thinking and reasoning modes. PNG and JPEG files keep their source encoding; HEIC and TIFF files are converted to PNG in memory.

SnapText applies project-owned safety caps of 16 MiB per image payload before base64 encoding, 64 megapixels, and 16,384 pixels per side. Command-Option-4 and automatic monitoring share a cap of 12 processing attempts in a rolling 60-second window. The explicit **Process Latest Screenshot** action remains available after the cap. These values are SnapText policies, not published Together API limits.

The transcription prompt covers multi-column layouts, overlays, tables, source code, terminal output, math, UI state, rotated and right-to-left text, handwriting, crop boundaries, occlusion, redaction, charts, and diagrams. It instructs the model to treat every command visible in the screenshot as untrusted text to transcribe. Model output can still follow a malicious image instruction or contain transcription errors. Check commands, links, names, numbers, and credentials before using the result.

Each chart is requested as a fenced `ascii` block drawn with ASCII marks. The prompt preserves visible titles, axes, ticks, units, scale type, baselines, breaks, legends, annotations, series, missing segments, and uncertainty marks. Only numbers printed as data labels are copied as data values. Unlabeled values remain visual geometry because SnapText does not calculate values from tick alignment or pixel positions. If the model emits Unicode drawing glyphs inside an `ascii` or `ascii-art` fence, SnapText converts those glyphs to ASCII before writing the clipboard. Fenced plain text, terminal output, source code, and other original-script characters remain unchanged. Braille chart glyphs are rejected because collapsing an eight-dot cell into one ASCII mark would discard its point pattern.

The prompt asks the model to keep each ASCII block within 72 characters and 20 body lines, with 60 ASCII-block body lines across one response. SnapText validates those limits after inference and leaves the clipboard unchanged when the model exceeds one. Long visible labels can sit outside the block. The budget leaves room under SnapText's hard 3,072-token response cap for surrounding text.

ASCII reconstruction is an approximate representation of the visible layout. Check series assignments, scales, numbers, and uncertainty against the screenshot before using the copied chart for analysis or decisions.

The output cap is 3,072 tokens. If Together reports that the response reached that cap, SnapText leaves the clipboard unchanged and asks for a smaller capture instead of copying a partial transcription as complete. Dense dashboards and charts can reach this cap; capture one panel at a time when that happens.

## Permissions and files

SnapText registers Command-Option-4 through macOS’s Carbon hotkey API. It does not read arbitrary keystrokes, control the pointer, use AppleScript, or replace Command-Shift-4. The hotkey needs no Accessibility, Input Monitoring, or Automation permission.

The direct capture path requires Screen Recording permission because SnapText launches Apple’s `/usr/sbin/screencapture` selector as a child process. The child receives a fixed argument list and a scrubbed environment that excludes the Together API key. The folder-watching fallback does not need Screen Recording permission.

For a direct capture, SnapText creates a private hidden staging directory inside the selected folder, asks Apple’s tool to write one PNG there, then moves that PNG to a unique visible filename. SnapText attempts to remove the staging directory after completion and cancellation. A cleanup error, forced termination, or quitting during an active selector can leave that hidden directory behind. If the final move fails, SnapText preserves the staged PNG and reports its path. SnapText never overwrites an existing destination.

The app also reads newly created Apple-tagged selection screenshots from the selected folder. It does not delete or alter those files. Folder access behavior can differ for protected locations; choose the folder again if macOS asks SnapText to renew access.

Selection detection reads the metadata attributes written by Apple's screenshot tool. This is a heuristic: another process can copy or create the attributes, and Apple does not publish them as a stable extension API. A macOS update can require a SnapText classifier update.

Copying an existing Apple screenshot into the watched folder can preserve those attributes and trigger processing. Pause SnapText before moving screenshot files that should not be sent.

## Clipboard behavior

SnapText records the clipboard change counter before each request. It copies the response only when that counter still matches after inference. A newer screenshot cancels the previous in-flight task, and only the newest task can update the clipboard or pending result.

AppKit exposes the clipboard comparison and write as separate operations. The change counter closes the common conflict path, but another process can change the clipboard between SnapText's final comparison and write.

Capture, network, model, and validation failures occur before SnapText’s clipboard write. Apple’s selector has one exception: holding Control during selection sends the screenshot to the clipboard instead of the output file. SnapText detects the clipboard change, makes no Together request, and reports that the clipboard changed. AppKit has no atomic replace operation; if macOS rejects the final prepared pasteboard item after clearing the old value, the old value cannot be restored without reading and retaining it. Use **Process Latest Screenshot** after correcting an API key, network, or rate-limit error.

Pausing unregisters Command-Option-4, stops folder monitoring, and cancels SnapText’s local work. Quitting does the same. Neither action can retract an image that Together already accepted, and that request can still incur a charge.

## Development

Run the test suite and create a development bundle with:

```sh
./scripts/test.sh
./scripts/build-app.sh
```

CI runs both commands on macOS and uploads the generated zip as a workflow artifact.

See [DESIGN.md](docs/DESIGN.md) for the architecture and latency plan, [PRIVACY.md](PRIVACY.md) for the data path, and [SECURITY.md](SECURITY.md) for vulnerability reports and distribution cautions.

## License

SnapText is available under the [MIT License](LICENSE).
