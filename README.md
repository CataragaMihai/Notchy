# Notchy

Ask Claude about whatever is on your screen, from the notch on your MacBook.

I kept taking screenshots, dragging them into a chat window and typing the same kind of question. Notchy cuts that down to one shortcut. Press ⌥⇧Space and the notch drops open with a picture of the window you're looking at. Type a question, or don't, and the answer streams in right there. Move the pointer away and it tucks back into the notch.

<!-- A GIF of the notch opening goes here. -->

## What you need

- A MacBook with a notch: a 14" or 16" MacBook Pro from 2021 or later, or a MacBook Air with M2 or later. Notchy won't run on a Mac without one.
- macOS 26 or later.
- An Anthropic API key, or Claude Code with a Claude subscription. The modes below explain which needs what.

## Install

1. Download `Notchy-1.0.0.dmg` from the [latest release](../../releases/latest).
2. Open it and drag Notchy into Applications.
3. Open Notchy. macOS will block it, because I haven't paid Apple for a developer certificate. Click Done.
4. Open System Settings › Privacy & Security, scroll down to the message about Notchy and click Open Anyway. Confirm with your password or Touch ID.

You only have to do that once. Next time Notchy opens normally, says hello from the notch and walks you through setup: Screen Recording permission, your API key, the shortcut and a mode. It takes about a minute.

One catch with an unsigned app: after you install a new version, macOS may ask for Screen Recording permission again, and the first question you ask may bring up a keychain prompt for your API key. Enter your Mac password and click Always Allow.

## Modes

### Quick

The default. Press the shortcut, ask your question, get an explained answer in a few seconds. It uses your API key.

### Lightning Fast

Sends the screenshot the moment you press the shortcut and shows nothing. Hover over the notch a second later and the answer is waiting, with no explanation attached. I use it to double check answers I already have. It also uses your API key.

### Claude Code

Puts the real Claude Code terminal in the notch, running on your Claude subscription instead of an API key. The shortcut pastes a screenshot into the session, and you can drop files onto the notch. You'll need Claude Code installed first:

```
curl -fsSL https://claude.ai/install.sh | bash
```

To switch modes, right-click the notch, use the menu bar icon, or go to Settings.

## Using it

- Press the shortcut or click the notch to capture the window in front.
- Type a question and press Enter. An empty Enter gets you an explanation of what's on screen.
- Move away, click somewhere else or press Esc, and it folds back into the notch. (In Claude Code mode, Esc goes to Claude Code.) Hover to see the answer again. Notchy forgets it after 10 minutes.
- Press New screenshot to swap in a fresh capture.

## Privacy

Notchy only captures when you press the shortcut or click the notch, and only the window in front. Nothing leaves your Mac until you press Enter. At that point the screenshot and your question go to Anthropic's API, or to Claude Code in Claude Code mode.

In Quick and Lightning Fast the screenshot never touches the disk. Claude Code reads images from files, so in that mode screenshots go to a private temporary folder that Notchy empties when it starts and when it quits.

Your API key lives in the macOS Keychain. Notchy has no analytics and no server of its own. The Usage tab estimates what you've spent from list prices; the real bill is in the Claude Console.

## Build from source

You need Xcode 26 and XcodeGen (`brew install xcodegen`).

```
cp Local.xcconfig.example Local.xcconfig   # then set your DEVELOPMENT_TEAM
xcodegen generate
xcodebuild -project Notchy.xcodeproj -scheme Notchy -configuration Debug \
  -derivedDataPath ~/Library/Developer/Notchy/DerivedData -skipPackagePluginValidation build
open ~/Library/Developer/Notchy/DerivedData/Build/Products/Debug/Notchy.app
```

`--mock` runs it with no capture and no network, which is handy for working on the UI. The tests are in the `NotchyCore` package: `swift test --package-path NotchyCore`.

`scripts/release.sh` builds the release disk image into `dist/`. It signs ad hoc, so it doesn't need a team ID.

## Known limits

I've only tested Notchy on my own MacBook Air M2, on the built-in display. External monitors and clamshell mode are untested. Notchy also uses a private macOS API to keep its windows still when you switch desktops. If a future macOS breaks that, they'll slide along with the desktop instead.

## License

MIT. See [LICENSE](LICENSE).
