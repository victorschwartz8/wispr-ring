// WisprRing helper for the F3 ring (switch on C):
//   middle press  (Volume Up key)   -> F18, Wispr Flow's hands-free shortcut
//   middle double (fake double tap) -> Enter
//   next/previous (fake swipes)     -> scroll up/down
//   hold next (pinch in)            -> Escape (once per hold)
//   hold previous (pinch out)       -> Select All + Delete, only in a text field
// It holds the ring exclusively so the volume key and fake touches never reach macOS.
import Foundation
import IOKit.hid
import CoreGraphics
import ApplicationServices
import AppKit

// ---- Settings (override with: defaults write local.wisprring <key> <value>, then restart) ----
let prefs = UserDefaults.standard   // reads the local.wisprring domain
func setting(_ key: String, _ fallback: Int) -> Int { prefs.object(forKey: key) == nil ? fallback : prefs.integer(forKey: key) }
let ringVendorID = 0x05AC     // the ring borrows Apple's vendor ID
let ringProductID = 0x0220
let doubleTapWindow = Double(setting("doubleTapMs", 300)) / 1000  // gap allowed between the two taps
let tapMaxMove = setting("tapMaxMove", 150)        // touch moving less than this = a tap
let swipeMinMove = setting("swipeMinMove", 300)    // touch moving more than this = a swipe
let scrollPixels = setting("scrollPixels", 360)    // how far one press scrolls
let scrollSteps = 12          // split into small steps so it glides
let wisprKeyCode = CGKeyCode(setting("wisprKeyCode", 79))  // 79 = F18
let wisprModifiers = setting("wisprModifiers", 7)  // add up: 1 control, 2 option, 4 command, 8 shift
let flipScroll = setting("flipScroll", 0) != 0     // 1 = previous scrolls down, next scrolls up
let swapHolds = setting("swapHolds", 0) != 0       // 1 = swap which hold is Escape and which clears
let clearOnlyInText = setting("clearOnlyInText", 1) != 0  // only select-all+delete inside a text field

// ---- Logging ----
let logURL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Logs/WisprRing.log")
let stamp: DateFormatter = { let f = DateFormatter(); f.dateFormat = "HH:mm:ss.SSS"; return f }()
func log(_ s: String) {
    let line = "\(stamp.string(from: Date())) \(s)\n"
    if let h = try? FileHandle(forWritingTo: logURL) { h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); try? h.close() }
    else { try? line.write(to: logURL, atomically: true, encoding: .utf8) }
}

// ---- Actions ----
func pressEscape() {
    let src = CGEventSource(stateID: .hidSystemState)
    CGEvent(keyboardEventSource: src, virtualKey: 53, keyDown: true)?.post(tap: .cghidEventTap)
    CGEvent(keyboardEventSource: src, virtualKey: 53, keyDown: false)?.post(tap: .cghidEventTap)
    log("ACTION escape")
}
let textRoles: Set<String> = ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"]

// Is the keyboard focus in an editable text field? nil = couldn't tell.
func focusIsText() -> (Bool?, String) {
    func focused(in el: AXUIElement) -> AXUIElement? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXFocusedUIElementAttribute as CFString, &v) == .success, let v else { return nil }
        return (v as! AXUIElement)
    }
    var el = focused(in: AXUIElementCreateSystemWide())
    if el == nil, let app = NSWorkspace.shared.frontmostApplication {
        // Electron/Chromium apps (Claude, Slack...) only expose focus once asked.
        let appEl = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetAttributeValue(appEl, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        el = focused(in: appEl)
    }
    guard let el else { return (nil, "no focused element") }
    var role: CFTypeRef?
    AXUIElementCopyAttributeValue(el, kAXRoleAttribute as CFString, &role)
    let r = role as? String ?? "?"
    var settable = DarwinBoolean(false)
    AXUIElementIsAttributeSettable(el, kAXValueAttribute as CFString, &settable)
    return (textRoles.contains(r) || settable.boolValue, r)
}

func clearText() {
    if clearOnlyInText {
        let (isText, role) = focusIsText()
        guard isText == true else { log("clear skipped: focus is \(role), not a text field"); NSSound.beep(); return }
    }
    let src = CGEventSource(stateID: .hidSystemState)
    for (key, down) in [(CGKeyCode(0), true), (CGKeyCode(0), false)] {   // Command-A
        let e = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: down)
        e?.flags = .maskCommand
        e?.post(tap: .cghidEventTap)
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {             // then Delete
        CGEvent(keyboardEventSource: src, virtualKey: 51, keyDown: true)?.post(tap: .cghidEventTap)
        CGEvent(keyboardEventSource: src, virtualKey: 51, keyDown: false)?.post(tap: .cghidEventTap)
        log("ACTION select all + delete")
    }
}

func pressEnter() {
    let src = CGEventSource(stateID: .hidSystemState)
    CGEvent(keyboardEventSource: src, virtualKey: 36, keyDown: true)?.post(tap: .cghidEventTap)
    CGEvent(keyboardEventSource: src, virtualKey: 36, keyDown: false)?.post(tap: .cghidEventTap)
    log("ACTION enter")
}
func pressWisprKey() {
    // Press the modifiers for real (not just flags) so any shortcut recorder or listener sees them.
    let mods: [(bit: Int, key: CGKeyCode, flag: CGEventFlags)] = [
        (1, 59, .maskControl), (2, 58, .maskAlternate), (4, 55, .maskCommand), (8, 56, .maskShift)]
    let active = mods.filter { wisprModifiers & $0.bit != 0 }
    let flags = CGEventFlags(active.map { $0.flag })
    let src = CGEventSource(stateID: .hidSystemState)
    func post(_ key: CGKeyCode, _ down: Bool, _ f: CGEventFlags) {
        let e = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: down)
        e?.flags = f
        e?.post(tap: .cghidEventTap)
    }
    var held = CGEventFlags()
    for m in active { held.insert(m.flag); post(m.key, true, held) }
    post(wisprKeyCode, true, flags)
    post(wisprKeyCode, false, flags)
    for m in active.reversed() { held.remove(m.flag); post(m.key, false, held) }
    log("ACTION wispr key")
}
func scroll(up requestedUp: Bool) {
    let up = flipScroll ? !requestedUp : requestedUp
    let step = Int32(scrollPixels / scrollSteps) * (up ? 1 : -1)
    for i in 0..<scrollSteps {
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.012) {
            CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1,
                    wheel1: step, wheel2: 0, wheel3: 0)?.post(tap: .cghidEventTap)
        }
    }
    log("ACTION scroll \(up ? "up" : "down")")
}

// ---- Gesture tracking ----
var strokeStart: (x: Int, y: Int)? = nil
var strokeLast: (x: Int, y: Int) = (0, 0)
var strokeMulti = false        // a second finger appeared (the ring's "hold" pinch)
var gapStart = -1, gapLast = -1   // distance between the two fingers, first and last report
var lastPinch = Date.distantPast
var tapPending = false
var tapToken = 0

func handleTap() {
    if tapPending {
        tapPending = false; tapToken += 1
        pressEnter()
    } else {
        tapPending = true; tapToken += 1
        let mine = tapToken
        DispatchQueue.main.asyncAfter(deadline: .now() + doubleTapWindow) {
            if tapPending && tapToken == mine { tapPending = false; log("single tap (ignored)") }
        }
    }
}

func endStroke() {
    guard let s = strokeStart else { return }
    strokeStart = nil
    if strokeMulti {
        // Holding a button makes the ring repeat a two-finger pinch ~8x/second.
        // One Escape per hold: fire on the first pinch, ignore the rest of the stream.
        strokeMulti = false
        let now = Date()
        if now.timeIntervalSince(lastPinch) > 0.5 {
            let pinchIn = gapLast < gapStart          // fingers moving together
            log("pinch \(pinchIn ? "in" : "out") (hold) gap \(gapStart)->\(gapLast)")
            // hold next = pinch in = Escape; hold previous = pinch out = clear text
            if pinchIn != swapHolds { pressEscape() } else { clearText() }
        }
        lastPinch = now
        return
    }
    let dx = strokeLast.x - s.x, dy = strokeLast.y - s.y
    let dist = max(abs(dx), abs(dy))
    log("stroke from (\(s.x),\(s.y)) to (\(strokeLast.x),\(strokeLast.y)) dx=\(dx) dy=\(dy)")
    if dist < tapMaxMove { handleTap(); return }
    guard dist >= swipeMinMove else { log("unclear gesture (ignored)"); return }
    if abs(dy) > abs(dx) {
        // T mode: previous = swipe down -> scroll down, next = swipe up -> scroll up
        scroll(up: dy < 0)
    } else {
        // C mode: previous = swipe right -> scroll down, next = swipe left -> scroll up
        scroll(up: dx < 0)
    }
}

let reportCallback: IOHIDReportCallback = { _, _, _, _, reportID, report, length in
    let bytes = Array(UnsafeBufferPointer(start: report, count: length))
    if ProcessInfo.processInfo.environment["WISPRRING_RAW"] != nil {
        log("raw id=\(reportID) " + bytes.map { String(format: "%02x", $0) }.joined(separator: " "))
    }
    if reportID == 2 {
        // media key report: [id] usage-lo usage-hi ; nonzero = press, zero = release
        let o = (bytes.first == 2 && length >= 3) ? 1 : 0
        guard length >= o + 2 else { return }
        let usage = Int(bytes[o]) | (Int(bytes[o + 1]) << 8)
        if usage != 0 { log(String(format: "media key 0x%02x", usage)); pressWisprKey() }
        return
    }
    guard reportID == 3 else { return }
    let o = (bytes.first == 3 && length >= 14) ? 1 : 0   // skip report ID byte if present
    guard length >= o + 4 else { return }
    let flags = bytes[o]
    let x = Int(bytes[o + 1]) | (Int(bytes[o + 2] & 0x0F) << 8)
    let y = (Int(bytes[o + 2]) >> 4) | (Int(bytes[o + 3]) << 4)
    let secondFinger = length >= o + 8 && (bytes[o + 5] | bytes[o + 6] | bytes[o + 7]) != 0
    if flags & 0x01 != 0 {
        if strokeStart == nil { strokeStart = (x, y); strokeMulti = false; gapStart = -1 }
        if secondFinger {
            strokeMulti = true
            let x2 = Int(bytes[o + 5]) | (Int(bytes[o + 6] & 0x0F) << 8)
            let gap = abs(x2 - x)
            if gapStart < 0 { gapStart = gap }
            gapLast = gap
        }
        strokeLast = (x, y)
    } else {
        if strokeStart != nil { strokeLast = (x, y) }
        endStroke()
    }
}

// ---- Startup ----
log("WisprRing starting (pid \(ProcessInfo.processInfo.processIdentifier))")
let listen = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
log("input monitoring granted: \(listen)")
let axOpts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
log("accessibility granted: \(AXIsProcessTrustedWithOptions(axOpts))")

let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
IOHIDManagerSetDeviceMatching(manager, [kIOHIDVendorIDKey: ringVendorID, kIOHIDProductIDKey: ringProductID] as CFDictionary)
IOHIDManagerRegisterDeviceMatchingCallback(manager, { _, _, _, device in
    let name = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "?"
    log("ring connected: \(name)")
}, nil)
IOHIDManagerRegisterDeviceRemovalCallback(manager, { _, _, _, _ in log("ring disconnected") }, nil)
IOHIDManagerRegisterInputReportCallback(manager, reportCallback, nil)
IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
var openResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
log("open (exclusive) result: \(String(format: "0x%08x", openResult))\(openResult == kIOReturnSuccess ? " (ok)" : "")")
if openResult != kIOReturnSuccess {
    openResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    log("open (shared) result: \(String(format: "0x%08x", openResult))\(openResult == kIOReturnSuccess ? " (ok) - volume key will also reach macOS" : "")")
}
CFRunLoopRun()
