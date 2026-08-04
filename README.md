# Screenie

Screenie turns any selected Mac screen region into clean, copy-ready Markdown. It preserves text, tables, code, terminal output, math, and interface structure. Charts and diagrams become ASCII art.

Press <kbd>Command</kbd>+<kbd>Option</kbd>+<kbd>4</kbd>, draw Apple’s normal selection box, and wait for the result on your clipboard.

## Install

You need macOS 13 or newer, Swift 6, and a [Together AI API key](https://api.together.ai/settings/api-keys).

These commands are for a fresh install. If Screenie or SnapText is already in `~/Applications`, quit it and follow the cleanup or update steps in [AGENTS.md](AGENTS.md) first.

```sh
git clone https://github.com/Sohailm25/screenie.git
cd screenie
if test -e "$HOME/Applications/Screenie.app" || test -e "$HOME/Applications/SnapText.app"; then
  echo "Move the existing app out of ~/Applications before continuing."
else
  ./scripts/build-app.sh
  mkdir -p "$HOME/Applications"
  ditto dist/Screenie.app "$HOME/Applications/Screenie.app"
  open "$HOME/Applications/Screenie.app"
fi
```

If `swift` is unavailable, run `xcode-select --install` and try again.

Using an agent? Send it the repository link and ask it to follow [AGENTS.md](AGENTS.md). Enter your API key in Screenie’s masked field, never in agent chat.

Screenie has its own macOS permission, preference, and Keychain identity. A SnapText upgrade therefore starts with fresh cloud consent, a fresh API-key entry, and a new Screen Recording approval. The [clean-reinstall steps](AGENTS.md#clean-reinstall-screenie-and-remove-snaptext) remove both app identities without deleting screenshots.

## First use

1. Click Screenie in the menu bar. It has no Dock window.
2. Read the cloud-upload notice and enable the app.
3. Enter your Together API key. It is stored in macOS Keychain.
4. Press <kbd>Command</kbd>+<kbd>Option</kbd>+<kbd>4</kbd> and grant Screen Recording permission when macOS asks.
5. Select a region. Screenie copies the result when processing finishes.

## Shortcuts

| Shortcut | Result |
| --- | --- |
| <kbd>Command</kbd>+<kbd>Option</kbd>+<kbd>4</kbd> | Opens Apple’s selector, then processes the selected region |
| <kbd>Command</kbd>+<kbd>Shift</kbd>+<kbd>4</kbd> | Keeps the native macOS shortcut; Screenie processes the saved selection screenshot |

The direct shortcut starts the Together request as soon as the selected PNG is ready. It does not wait for a folder event.

## Output

Screenie uses `Qwen/Qwen3.5-9B` by default and offers `google/gemma-4-31B-it` for dense captures. It returns reading-order Markdown, Markdown tables, fenced code or terminal blocks, preserved math, and fenced ASCII charts.

ASCII charts keep visible labels, axes, legends, series, and relative geometry. Check scales and numbers against the screenshot before using them for analysis. For dense dashboards, capture one panel at a time.

If you copy something while Screenie is processing, it leaves the newer clipboard content alone. Choose **Copy Ready Text** from the menu to copy the finished result.

## Privacy and cost

Each processed screenshot is sent to `api.together.xyz` and can incur Together API charges. While Screenie is enabled, it also processes new Apple-tagged selection screenshots in the watched folder. Pause or quit Screenie before taking a screenshot that must remain local.

The API key stays in macOS Keychain. Screenie keeps no request history, sends no analytics, and never sends your existing clipboard contents to Together. Read [PRIVACY.md](PRIVACY.md) for the full data path.

## Development

```sh
./scripts/test.sh
./scripts/build-app.sh
```

Tests use a local request stub and make no Together API calls. See [DESIGN.md](docs/DESIGN.md), [SECURITY.md](SECURITY.md), and the [agent guide](AGENTS.md).

MIT licensed. See [LICENSE](LICENSE).
