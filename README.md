<h1 align="center">Bouncer</h1>

<p align="center"><b>One notch, one app at a time.</b></p>

<p align="center">
  <a href="https://github.com/donpaco13/Bouncer/actions/workflows/ci.yml"><img src="https://github.com/donpaco13/Bouncer/actions/workflows/ci.yml/badge.svg?branch=main" alt="CI"></a>
  <a href="https://github.com/donpaco13/Bouncer/releases/latest"><img src="https://img.shields.io/github/v/release/donpaco13/Bouncer?label=download&color=brightgreen" alt="Download"></a>
  <img src="https://img.shields.io/badge/platform-macOS%2014%2B-lightgrey" alt="macOS 14+">
  <a href="LICENSE"><img src="https://img.shields.io/github/license/donpaco13/Bouncer" alt="License"></a>
</p>

<p align="center"><a href="README.fr.md">Lire en français</a></p>

Bouncer decides which notch app you see on your MacBook. Vibe Island, boringNotch and the
others stay installed and open; one shows at a time, and you change your mind with a
two-finger swipe on the notch, an arrow, a keyboard shortcut, or the menu bar.

It is for people with a notched MacBook who run more than one notch app and are tired of
quitting one to see the other.

<!-- TODO: demo GIF of a switch (swipe on the notch, app A gives way to app B) goes here. -->

## Why it exists

Each notch app draws its own pill under the notch. Open two and they land on the same
rectangle, one over the other. macOS coordinates nothing: there is no such thing as an
"active notch app" at the system level, and the only way out it gives you is to quit one
app and launch it again when you need it back.

## Install

### Homebrew

```bash
brew install --cask donpaco13/tap/bouncer
```

Bouncer lands in `/Applications` and opens normally. The cask strips the quarantine
attribute itself, so you never see the screen below.

### Download the archive

1. Grab the latest `Bouncer-x.x.x.zip` from the [releases page](https://github.com/donpaco13/Bouncer/releases).
2. Unzip it.
3. Drag `Bouncer.app` into `/Applications`.

### "macOS cannot verify that Bouncer is free of malware"

That is what the first launch shows if you took the archive route, and it is normal.
macOS does not know who wrote Bouncer: Apple charges developers €99 a year for an identity
it recognises on sight, and this project does not pay it. The binary is signed with a local
self-signed certificate (`Bouncer Local Signing`). The block is about the missing identity,
not about the contents of the app.

To open it anyway, once:

1. Double-click Bouncer and let macOS refuse.
2. Open **System Settings** > **Privacy & Security**.
3. Scroll to the message about Bouncer and click **Open Anyway**.
4. Confirm with your password.

Later launches go straight through.

### Build from source

Needs macOS 14+ and the Xcode Command Line Tools (Swift 5.9+).

```bash
git clone https://github.com/donpaco13/Bouncer.git
cd Bouncer
./build.sh
```

`build.sh` builds in release with SwiftPM, assembles `Bouncer.app`, creates a persistent
local signing identity in your keychain so the Accessibility permission survives from one
build to the next, installs the bundle in `/Applications` and launches it.

To see what Bouncer finds under your notch without opening the interface:

```bash
"/Applications/Bouncer.app/Contents/MacOS/Bouncer" --self-test
```

## What you need

- **macOS 14 Sonoma or later.** The lifecycle APIs and the interface are written for those versions.
- **A MacBook with a hardware notch** (`safeAreaInsets.top > 0`): 14 and 16-inch Apple Silicon MacBook Pro, 13 and 15-inch M2/M3/M4 MacBook Air. With an external display as your main one, Bouncer finds the built-in screen that carries the notch by itself.
- **The Accessibility permission** (`AXIsProcessTrusted`), asked for on first launch. It is what lets Bouncer read the window list and hide other apps' windows. Without it, Bouncer touches nothing.
- **At least one third-party notch app.** Bouncer is a stage manager, not a notch widget. With nothing installed it has nothing to arbitrate, and the welcome guide says so.

## Switching apps

Four ways, all doing the same thing: move one step through the cycle, which loops.

- **Swipe on the notch.** Put the pointer over the notch app's surface and swipe horizontally with two fingers. Left or right makes no difference, the gesture moves one step.
- **Arrows on hover.** Bring the cursor near the camera housing and two arrows (‹ and ›) appear on either side. Click one. Away from the notch, Bouncer draws nothing.
- **Global shortcut.** `⌃⌥⌘B` works from any app, full screen included. Without a trackpad it is the one command that makes you neither aim at the notch nor open a menu.
- **Menu bar.** `●` is the app holding the notch, `○` one waiting (click it to bring it back, open or closed), `◐` a switch in progress. Each entry says in a tooltip whether the switch will be instant or a relaunch.

Bouncer has no Dock icon and no window to manage (`LSUIElement = true`). On first launch it
opens a five-screen welcome guide that checks the Accessibility permission live and has you
try the gesture; you can reopen it from the menu.

## How a switch works

Two routes, picked automatically from what each app's binary accepts. Nothing to configure.

1. **Hide (about 31 ms).** For apps that leave their windows in the standard user Space, Bouncer sets the Accessibility attribute `kAXHiddenAttribute`. The app stays in memory, keeps its state, and comes back in 5 ms without restarting.
2. **Relaunch (about 1 s).** For apps that create their own private Space with the WindowServer (`CGSSpaceCreate` + `CGSAddWindowsToSpaces`) and ignore the hide order, Bouncer starts the target, waits for its window to show up under the notch, then closes the old one.

| App | Route | Measured |
|---|---|---|
| **Vibe Island** | Hide | 31.7 ms out, 5.1 ms back. Stays in memory. |
| **boringNotch** | Relaunch | About 1 s. The old instance closes once the new window is visible. |

The full survey of notch apps on the market, measurement and prediction kept apart, is in
[`docs/COMPATIBILITE.md`](docs/COMPATIBILITE.md).

Two guarantees hold across both routes:

- **On before off.** Bouncer hides or closes the app in place only once the new window has been counted on screen by `CGWindowList`, not inferred from an API return code. If the target will not start, or takes more than five seconds, the current app stays exactly where it is. You never end up with an empty notch, or with two processes killed.
- **A strict geometric filter.** So a tall browser or Discord window is never mistaken for a notch app, a window has to be floating (`layer > 0`), stuck to the top edge of the screen, and wide enough to cover the camera housing without spanning the display (under 80% of its width).

## Settings

`⌘,` opens three tabs. **General** holds launch at login and the window re-scan interval
(1 to 30 seconds, 2 by default). **Gesture** holds the activation mode, the global shortcut,
the sensitive area, and the geometry of the hover arrows. **Applications** lists everything
Bouncer recognises; unchecking an app takes it out of the swipe cycle while keeping it
clickable in the menu.

## Not in scope

- **No unstable private APIs.** No `CGSSetWindowAlpha`, no undocumented WindowServer injection that would break on a minor macOS update.
- **No split view.** Bouncer does not draw two apps side by side in the notch and does not capture their output.
- **No Mac App Store build.** The sandbox the store requires blocks the Accessibility API, which is the whole engine.

## Contributing

Issues and pull requests are welcome, in English or French. Note that the source is written
in French (types, methods, comments); match the surrounding file rather than translating it.

```bash
swift build
swift test
```

CI runs both on macOS with Xcode 16.4. A change to switching behaviour should come with the
measurement that backs it, the way [`docs/PERFORMANCE.md`](docs/PERFORMANCE.md) and
[`docs/COMPATIBILITE.md`](docs/COMPATIBILITE.md) do.

## Documentation

- [`docs/COMPATIBILITE.md`](docs/COMPATIBILITE.md): every notch app surveyed, and Bouncer's verdict on each.
- [`docs/DISTRIBUTION.md`](docs/DISTRIBUTION.md): Gatekeeper, Homebrew quarantine and signing.
- [`docs/PERFORMANCE.md`](docs/PERFORMANCE.md): CPU cost, the price of a `CGWindowList` scan, and what was optimised.
- [`docs/CONFIDENTIALITE.md`](docs/CONFIDENTIALITE.md): what Bouncer reads, what it stores, what it never sends.
- [`docs/archive/`](docs/archive/): the original validation spikes and architecture documents.

## License

[MIT](LICENSE).
