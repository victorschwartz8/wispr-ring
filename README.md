# WisprRing

Turns a cheap Bluetooth "TikTok scrolling ring" into a remote for
[Wispr Flow](https://wisprflow.ai) dictation on a Mac: start and stop dictating,
send, cancel, clear, and scroll, all from your finger.

Built for the **FiKavi F3** ring (Bluetooth name "F3"). Keep its side switch on **C**.

| Ring | Does |
|---|---|
| Middle, press | Wispr hands-free on/off (sends Control+Option+W) |
| Middle, double press | Enter, to send the message |
| Next, press | scroll up |
| Previous, press | scroll down |
| Hold next | Escape, which cancels Wispr while it's listening (once per hold) |
| Hold previous | Select All + Delete. Only in a text field, and beeps anywhere else. ⌘Z undoes |

Hold the ring upright with the USB-C port at the bottom: next is on top, previous
at the bottom. A printable-style quick reference is in [`ring-guide.html`](ring-guide.html).

## How it works

The ring isn't a keyboard, so key remappers like Karabiner-Elements can't use most
of it. In C mode it pretends to be a touchscreen and a media remote:

- the middle button sends Volume Up or Volume Down (it alternates)
- next and previous send fake horizontal swipes
- a double press of middle sends a fake double tap
- holding next or previous sends a repeating two-finger pinch (in or out)

`WisprRing.app` is a small background app (one Swift file, [`main.swift`](main.swift))
that reads those reports straight from the ring, takes the ring exclusively so the
volume key and fake touches never reach macOS, and sends the keys and scrolls above.

## Install

You need macOS 13 or later and the Xcode command line tools (`xcode-select --install`).

1. Pair the ring with the Mac in System Settings → Bluetooth. Turn Bluetooth off on
   your phone first, or the ring keeps reconnecting to it.
2. Optional, but recommended: sign with your own Apple Development certificate so
   macOS remembers the app's permissions when you rebuild. See the top of
   [`build.sh`](build.sh).
3. Run:
   ```bash
   ./install.sh
   ```
   This builds `~/Applications/WisprRing.app` and starts it now and at every login.
4. In System Settings → Privacy & Security, switch **WisprRing** on under both
   **Input Monitoring** and **Accessibility**. If it isn't listed, click **+**, press
   ⌘⇧G and enter `~/Applications/WisprRing.app`. Then restart it:
   ```bash
   launchctl kickstart -k gui/$(id -u)/local.wisprring
   ```
5. In Wispr Flow's settings, set the **hands-free** shortcut by typing
   **Control+Option+W on your keyboard**. Wispr's recorder is too slow to catch the
   ring's combo, but the ring triggers it fine once it's set.

If you use Karabiner-Elements, set the F3 ring to ignored in its Devices settings,
or Karabiner will hold the ring and WisprRing can't read it.

## Files

- App: `~/Applications/WisprRing.app`
- Starts at login: `~/Library/LaunchAgents/local.wisprring.plist` (restarts if it stops)
- Log: `~/Library/Logs/WisprRing.log` (every gesture and action is written here)

## Tuning (no rebuild)

```bash
defaults write local.wisprring scrollPixels -int 500   # scroll distance per press (default 360)
defaults write local.wisprring flipScroll -int 1       # reverse scroll direction
defaults write local.wisprring swapHolds -int 1        # swap the two holds (Escape <-> clear)
defaults write local.wisprring clearOnlyInText -int 0  # let clear run outside text fields (risky)
defaults write local.wisprring wisprKeyCode -int 13    # Wispr key's macOS key code (13 = W)
defaults write local.wisprring wisprModifiers -int 3   # 1 control + 2 option + 4 command + 8 shift
launchctl kickstart -k gui/$(id -u)/local.wisprring    # restart to apply
```

Wispr allows at most three keys in a shortcut. If you change the key, record the new
shortcut in Wispr by typing it on the keyboard.

To see the ring's raw reports (useful for a different ring), stop the login agent
and run the app once with `open --env WISPRRING_RAW=1 ~/Applications/WisprRing.app`.

## Rebuild after editing main.swift

```bash
./build.sh && launchctl kickstart -k gui/$(id -u)/local.wisprring
```

## Uninstall

```bash
launchctl bootout gui/$(id -u)/local.wisprring
rm ~/Library/LaunchAgents/local.wisprring.plist
rm -rf ~/Applications/WisprRing.app
defaults delete local.wisprring
```

Then remove WisprRing from Privacy & Security → Input Monitoring and Accessibility,
and change Wispr's hands-free shortcut back. To use the ring with your phone again,
unpair it from the Mac and pair it with the phone.

## Why only on a Mac

Everything happens in the helper app; the ring itself is unchanged. iPhone doesn't
let apps intercept a Bluetooth device like this, so on a phone the ring keeps its
original TikTok and camera-shutter behavior.
