# Screenie design

## Capture paths

Screenie registers Command-Option-4 as an exclusive Carbon hotkey. Before registration, it checks macOS’s enabled symbolic shortcuts and refuses the chord when System Settings already owns it. The handler launches `/usr/sbin/screencapture -i -s -t png <path>`, so Apple still draws the selection overlay and controls pointer behavior, crosshair coordinates, and Escape cancellation. Carbon hotkey registration does not read arbitrary keystrokes and needs no Accessibility or Input Monitoring permission.

The direct path writes into a private hidden directory inside the configured screenshot folder. After Apple’s process exits, Screenie verifies a nonempty regular file, registers its device and inode with the watcher, and moves it to a unique visible PNG name. Inference starts from that exact path. It does not wait for a folder event.

Command-Shift-4 remains assigned to macOS. Screenie watches the configured screenshot folder and treats a new file as an automatic candidate only when Apple’s screenshot metadata marks it as a selection capture. Existing files form the watcher’s baseline and are not uploaded automatically. This fallback keeps the native shortcut unchanged, but it depends on metadata attributes that Apple does not publish as a stable extension API.

Launching Apple’s capture utility from Screenie requires Screen Recording permission. The folder-watching path does not require that permission. Neither path uses Accessibility, Input Monitoring, Automation, or AppleScript.

## Processing pipeline

1. Command-Option-4 launches Apple’s region selector with an exact staging path. The native fallback instead begins with a serialized folder scan and metadata check.
2. The direct path publishes its validated inode to a unique visible PNG path. The watcher path waits for file size and modification time to settle, checks selection metadata, and asks ImageIO to confirm that the image is readable.
3. The loader opens the chosen path without following symbolic links. It verifies the expected device and inode, reads through that descriptor, enforces byte and pixel caps, and checks that the file did not change during the read.
4. PNG and JPEG bytes are retained. HEIC and TIFF inputs are converted to PNG in memory.
5. The app sends one base64 data URI to Together's chat completions endpoint. The default request uses `Qwen/Qwen3.5-9B`, temperature `0`, and disabled thinking and reasoning.
6. The response parser accepts only a response with `finish_reason: stop` or `finish_reason: eos`. It rejects empty, truncated, incomplete, or malformed responses, removes blank wrapper lines, and preserves whitespace on content lines.
7. Unicode drawing glyphs inside top-level fenced `ascii` or `ascii-art` blocks are converted to ASCII. Screenie rejects a block over 72 characters wide or 20 body lines, more than 60 ASCII-block body lines in one response, an unterminated Markdown fence, or a Braille chart glyph. Fenced plain text, nested literal fences, original-script text, and language-labelled code blocks are unchanged.
8. The clipboard is updated only if its change counter still matches the value recorded before processing. A conflict leaves the result behind the **Copy Ready Text** menu item.

A single operation identifier spans capture, lookup, image loading, inference, and clipboard commit. A newer screenshot or shortcut action cancels older local work. The watcher assigns each discovered candidate a sequence number and records a boundary when the shortcut starts. A callback at or before that boundary cannot cancel the newer selector, even when a copied file has an old modification time. A monitoring generation prevents callbacks from a previous folder watcher from starting work after the folder changes. Watcher suppression consumes the direct capture’s exact path and inode, so one Command-Option-4 action cannot enter inference again through the folder path.

## Model choice

The default is [`Qwen/Qwen3.5-9B`](https://www.together.ai/models/qwen3-5-9b). Together lists it as a vision model, and its model page reports an OCRBench score of 89.2. A 9B model also has a lower inference workload than the optional [`google/gemma-4-31B-it`](https://docs.together.ai/docs/serverless-models), which Screenie exposes as the accuracy-oriented choice.

Those facts support the default, but they do not prove end-to-end latency on a specific account, network, screenshot, or service load. The repository does not publish a latency claim until the benchmark below has live results.

## Latency accounting

The status display measures from the start of image loading until clipboard completion. That duration includes file read and conversion, base64 and JSON construction, connection and service time, response decoding, and clipboard commit. It excludes the time spent in Apple’s selector and the local staging-to-visible move.

The design removes avoidable serial work from the hot path:

- The app reuses one ephemeral URL session.
- PNG and JPEG screenshots skip transcoding.
- Model thinking and reasoning are disabled.
- The prompt and response validator budget ASCII blocks at 72 characters and 20 body lines per block, with 60 ASCII-block body lines per response.
- A new capture cancels an older result that the user no longer wants.
- Clipboard work stays local and occurs only after a valid response.

## Benchmark before a public latency claim

Use a fixed corpus that represents the intended input:

- Dense document text at native Retina resolution
- Source code with indentation and punctuation
- A table with aligned rows and columns
- A mixed interface screenshot with labels and small text
- A low-contrast or scaled screenshot that tests the quality boundary
- A chart with printed labels and unlabeled geometry
- A dense multi-series chart with dual axes, gaps, and uncertainty marks
- A mixed screenshot containing prose, a table, code, math, UI state, and a chart
- Cropped, occluded, rotated, right-to-left, handwritten, and prompt-injection fixtures

For both models, run warm and cold sequences from the same Mac and network. Record end-to-end duration, exact text and numeric spans, table cell placement, uncertainty markers, chart series and scale fidelity, invented content, malformed output, and any manual correction. Report the sample count and percentile method with p50 and p95 results. Do not select the default from a single run.

Each live benchmark request uses the configured Together account and can incur charges. Screenie's automated tests validate request shape with a local URL protocol stub and do not call Together.

## Security boundaries

Apple’s metadata classifies files; it does not authenticate them. A process that can write to the watched folder can create a file with matching attributes. Screenie applies one rolling request cap to monitored and shortcut captures and rejects oversized inputs to bound those paths. The explicit **Process Latest Screenshot** action bypasses the rolling cap.

The capture child runs only `/usr/sbin/screencapture` without a shell. Its environment contains `LANG` and a fixed `PATH`; it does not inherit the Together key. Direct captures use a generated owner-only staging directory and a destination name containing a UUID. Cleanup is best-effort. A cleanup error or process termination can leave the staging directory behind, and a failed final move deliberately preserves the PNG for recovery.

The API key stays in macOS Keychain. Screenie does not read existing clipboard contents or retain a request history. HTTPS protects data in transit; Together receives every processed image and applies the account's current retention and privacy settings.

## Upgrade identity

The visible app name, executable, bundle path, and build artifacts are Screenie. The bundle identifier remains `com.sohailmohammad.SnapText`, which is also the Keychain service name. macOS preferences remain under that bundle domain, and Screenie can locate the existing Keychain item without copying the secret.

Development builds use ad-hoc signatures. Their designated requirement changes when the executable changes, so macOS can ask the user to approve Screenie's access to a Keychain item created by SnapText. If access is denied, saving over that item can also fail. With the user's approval, remove only the item whose service is `com.sohailmohammad.SnapText` and account is `together-api-key` in Keychain Access, then enter the key again through Screenie's menu. macOS can also request Screen Recording approval again after a rebuild even when the bundle identifier stays the same.
