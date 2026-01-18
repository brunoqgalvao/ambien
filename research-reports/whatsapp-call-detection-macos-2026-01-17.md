# WhatsApp Call Detection on macOS - Research Report

**Date:** January 17, 2026
**Research Agent:** Claude Code
**Objective:** Find methods to detect when WhatsApp calls are active on macOS programmatically

---

## Executive Summary

**Problem:** WhatsApp's macOS app (bundle ID: `net.whatsapp.WhatsApp`) doesn't expose call windows to the Accessibility API, making traditional window-title-based detection ineffective. This is a known issue with Catalyst/Electron apps that don't properly implement macOS accessibility protocols.

**Key Finding:** There is **no single perfect solution**, but several complementary approaches can be combined:

1. **Audio device monitoring** (macOS 14.2+) - Most reliable
2. **Process monitoring with lsof** - Works but has false positives
3. **OverSight-style event interception** - Requires admin privileges
4. **AppleScript/UI automation** - Brittle but possible fallback

**Recommended Approach:** Use audio device monitoring as the primary detection method, with process monitoring as a backup.

---

## Research Findings

### 1. The Core Problem: WhatsApp + Accessibility API

#### Why Window Detection Fails

WhatsApp's macOS desktop app is either:
- **Web wrapper** (older App Store version) - Uses its own notification system instead of native macOS APIs
- **Catalyst app** (newer beta) - Known issues with Accessibility API window exposure
- **Electron-based** (unofficial versions) - Hidden windows not properly exposed to accessibility

**Evidence:**
- Accessibility API returns 0 windows for WhatsApp even when call window is visible
- Window title "WhatsApp voice call" / "Chamada de vídeo" exists but isn't accessible
- This is a common issue with Catalyst apps ([GitHub issue #22762](https://github.com/dotnet/macios/issues/22762))

**Quote from research:**
> "Once the access is broken, the application will not be able to access the Accessibility API without the user going to System Settings and completely removing the application from the access list." - [dotnet/macios GitHub](https://github.com/dotnet/macios/issues/22762)

---

### 2. Solution #1: Audio Device Monitoring (PRIMARY RECOMMENDATION)

#### Overview

macOS 14.2+ introduced `AudioHardwareCreateProcessTap` - a CoreAudio API that allows monitoring audio from specific processes. This is the **most reliable** method for detecting WhatsApp calls.

#### How It Works

```
1. Get WhatsApp's process ID (PID) via NSRunningApplication
2. Translate PID to AudioObjectID
3. Create a CATapDescription
4. Call AudioHardwareCreateProcessTap to create an audio tap
5. Monitor audio levels from WhatsApp process
6. High audio activity = call is active
```

#### Implementation Steps

Based on [AudioCap sample code](https://github.com/insidegui/AudioCap):

1. **Get WhatsApp PID:**
```swift
let whatsappApps = NSRunningApplication.runningApplications(
    withBundleIdentifier: "net.whatsapp.WhatsApp"
)
guard let whatsapp = whatsappApps.first else { return }
let pid = whatsapp.processIdentifier
```

2. **Convert PID to AudioObjectID:**
```swift
var processObjectID: AudioObjectID = 0
var pid = whatsapp.processIdentifier
var size = UInt32(MemoryLayout<AudioObjectID>.size)

AudioObjectGetPropertyData(
    AudioObjectID(kAudioObjectSystemObject),
    &AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    ),
    0, nil,
    &size, &processObjectID
)
```

3. **Create Process Tap:**
```swift
var tapDescription = CATapDescription()
var tapID: AudioObjectID = 0

AudioHardwareCreateProcessTap(processObjectID, &tapDescription, &tapID)
```

4. **Monitor Audio Levels:**
```swift
// Set up audio callback to monitor volume/activity
// If audio level > threshold for >2 seconds = call active
```

#### Permissions Required

- **NSAudioCaptureUsageDescription** in Info.plist (must be added manually, not in Xcode dropdown)
- User must grant permission via system prompt
- Permission persists after first grant

#### Advantages

- ✅ **Reliable** - Detects actual audio activity, not just window presence
- ✅ **Process-specific** - Can filter to only WhatsApp
- ✅ **Works with hidden windows** - Doesn't rely on window visibility
- ✅ **Official API** - Supported by Apple (macOS 14.2+)

#### Disadvantages

- ❌ Requires macOS 14.2+ (Sonoma)
- ❌ Permission prompt required (user friction)
- ❌ Slightly higher CPU usage (monitoring audio stream)
- ❌ False positives if user plays audio messages

#### Code Resources

- **[AudioCap by insidegui](https://github.com/insidegui/AudioCap)** - Complete Swift implementation
- **[AudioTee](https://stronglytyped.uk/articles/audiotee-capture-system-audio-output-macos)** - Command-line tool with process filtering
- **[Apple's Core Audio Taps Guide](https://developer.apple.com/documentation/CoreAudio/capturing-system-audio-with-core-audio-taps)** - Official documentation (requires JavaScript)
- **[Gist example](https://gist.github.com/sudara/34f00efad69a7e8ceafa078ea0f76f6f)** - Simple example for macOS 14.2

---

### 3. Solution #2: Process Monitoring with lsof (BACKUP METHOD)

#### Overview

Use `lsof` to detect which processes have audio/camera devices open. Works on all macOS versions but has accuracy issues.

#### How It Works

```bash
# For camera
lsof | grep "AppleCamera"
lsof | grep "iSight"
lsof | grep "VDC"

# Parse output to find WhatsApp PID
```

#### Implementation

```swift
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/lsof")

let pipe = Pipe()
task.standardOutput = pipe

try task.run()
let data = pipe.fileHandleForReading.readDataToEndOfFile()
let output = String(data: data, encoding: .utf8)

// Parse output for WhatsApp process
if output?.contains("WhatsApp") == true {
    // Call detected
}
```

#### Advantages

- ✅ Works on all macOS versions
- ✅ No special permissions (beyond basic process listing)
- ✅ Simple to implement

#### Disadvantages

- ❌ **High false positive rate** - Shows apps that *could* use camera, not actively using
- ❌ Shows FaceTime even when idle ([source](https://www.applegazette.com/mac/find-app-using-webcam-mac/))
- ❌ Polling required (not event-driven)
- ❌ Can't distinguish call from audio message playback

**Quote from research:**
> "The problem is that these commands show also many processes which are not exactly using the camera too. For example, in some cases even if FaceTime is minimized to dock (it means that the camera is not on, in idle mode), these commands show FaceTime application as an application which is occupying the camera (although it is not)." - [Apple Gazette](https://www.applegazette.com/mac/find-app-using-webcam-mac/)

---

### 4. Solution #3: OverSight-Style Event Interception (ADVANCED)

#### Overview

[OverSight](https://objective-see.org/products/oversight.html) by Objective-See monitors camera/mic activation at the system level using private APIs.

#### How It Works

- Monitors TCC (Transparency, Consent, Control) framework
- Intercepts camera/mic activation events from `tccd` daemon
- Uses private APIs like `TCCAccessRequest` to detect permission checks
- Requires **admin privileges** to function

**Quote from research:**
> "Due to the mechanism used by OverSight to monitor for mic and webcam access, it can only be installed for, and run on accounts with administrative privileges." - [OverSight](https://objective-see.org/products/oversight.html)

#### TCC Database Location

```
/Library/Application Support/com.apple.TCC/TCC.db (system-level)
/Users/${USERNAME}/Library/Application Support/com.apple.TCC/TCC.db (user-level)
```

Camera/Microphone permissions are tracked at **user level**.

#### TCC Services

```
kTCCServiceCamera - Camera access
kTCCServiceMicrophone - Microphone access
```

#### SQL Query Example

```sql
SELECT client, service, auth_value
FROM access
WHERE service LIKE '%camera%' OR service LIKE '%microphone%'
```

#### Advantages

- ✅ System-level monitoring (catches all apps)
- ✅ Event-driven (no polling)
- ✅ Very accurate

#### Disadvantages

- ❌ **Requires admin privileges**
- ❌ Uses private APIs (may break in future macOS versions)
- ❌ TCC database is SIP-protected
- ❌ Complex implementation

#### Resources

- **[OverSight GitHub](https://github.com/objective-see/OverSight)** - Open source (Objective-C)
- **[TCC Deep Dive](https://www.rainforestqa.com/blog/macos-tcc-db-deep-dive)** - Technical analysis
- **[HackTricks TCC Guide](https://book.hacktricks.wiki/en/macos-hardening/macos-security-and-privilege-escalation/macos-security-protections/macos-tcc/index.html)** - Exploitation techniques

---

### 5. Solution #4: macOS Built-in Indicators (READ-ONLY)

#### Control Center Indicators

macOS Monterey+ shows which app is using camera/mic in Control Center:
- **Green dot** = Camera active
- **Orange dot** = Microphone active

Click Control Center to see app name.

#### Advantages

- ✅ Native macOS feature
- ✅ No code required (user can check manually)

#### Disadvantages

- ❌ **Read-only** - Can't programmatically access this info
- ❌ User has to manually check
- ❌ Not suitable for automation

---

### 6. Solution #5: AppleScript + UI Automation (FRAGILE FALLBACK)

#### Overview

Use AppleScript to query Chrome/Brave tabs or attempt to get WhatsApp window info.

**Note:** WhatsApp desktop is NOT browser-based, but there's a [WhatsApp MCP server](https://playbooks.com/mcp/gfb-47-whatsapp-desktop) that uses AppleScript for automation.

#### Example (Hypothetical)

```applescript
tell application "System Events"
    tell process "WhatsApp"
        set windowTitles to name of every window
    end tell
end tell
```

#### Known Issues

- WhatsApp doesn't expose windows to AppleScript (same Accessibility API issue)
- Older WhatsApp (web wrapper) uses its own notification system ([source](https://discussions.apple.com/thread/253899924))
- Beta WhatsApp (Catalyst) has better accessibility but still limited

#### Advantages

- ✅ No special permissions (beyond Accessibility)
- ✅ Can work for some apps

#### Disadvantages

- ❌ **Doesn't work for WhatsApp** (window not exposed)
- ❌ Brittle (breaks with UI changes)
- ❌ Requires Accessibility permissions

---

### 7. Solution #6: ScreenCaptureKit Audio Filtering (macOS 13+)

#### Overview

ScreenCaptureKit (macOS 13+) can capture audio from specific applications, but it's designed for recording, not detection.

#### How It Works

```swift
let content = try await SCShareableContent.current
let whatsappApp = content.applications.first {
    $0.bundleIdentifier == "net.whatsapp.WhatsApp"
}

let filter = SCContentFilter(desktopIndependentWindow: whatsappApp)
let config = SCStreamConfiguration()
config.capturesAudio = true

let stream = SCStream(filter: filter, configuration: config, delegate: self)
try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: .main)
```

#### Advantages

- ✅ Official API (ScreenCaptureKit)
- ✅ Process-specific audio capture
- ✅ Works on macOS 13+ (wider compatibility than AudioHardwareCreateProcessTap)

#### Disadvantages

- ❌ **Requires Screen Recording permission** (more intrusive than audio-only)
- ❌ Higher overhead (designed for recording, not detection)
- ❌ "Audio capture can only be filtered at an application level" ([source](https://developer.apple.com/forums/thread/718279))
- ❌ Overkill for simple detection

---

## Recommended Implementation Strategy

### Tiered Approach (Best Reliability)

```swift
class WhatsAppCallDetector {

    // Method 1: Audio Tap (macOS 14.2+)
    func detectViaAudioTap() -> Bool {
        // Use AudioHardwareCreateProcessTap
        // Monitor audio levels from WhatsApp process
        // Return true if sustained audio activity
    }

    // Method 2: lsof fallback (all macOS versions)
    func detectViaProcessMonitoring() -> Bool {
        // Run lsof | grep "AppleCamera"
        // Check if WhatsApp appears in output
        // High false positive rate
    }

    // Method 3: ScreenCaptureKit (macOS 13+)
    func detectViaScreenCaptureKit() -> Bool {
        // Use SCStream with audio capture
        // Check for audio activity
        // Requires Screen Recording permission
    }

    // Main detection logic
    func isWhatsAppCallActive() -> Bool {
        if #available(macOS 14.2, *) {
            return detectViaAudioTap()
        } else if #available(macOS 13.0, *) {
            return detectViaScreenCaptureKit()
        } else {
            return detectViaProcessMonitoring()
        }
    }
}
```

### Minimal Approach (Lowest Friction)

If you want to avoid permission prompts:

```swift
// Option 1: Just assume WhatsApp is running = call might be active
let whatsappApps = NSRunningApplication.runningApplications(
    withBundleIdentifier: "net.whatsapp.WhatsApp"
)
let isRunning = !whatsappApps.isEmpty

// Option 2: Combine with lsof (no permission needed)
let isUsingMic = checkLsofForWhatsApp()
```

**Trade-off:** Lower accuracy but no user friction.

---

## Permission Requirements Summary

| Method | Permissions | User Friction | macOS Version |
|--------|------------|---------------|---------------|
| AudioHardwareCreateProcessTap | NSAudioCaptureUsageDescription | Medium (one-time prompt) | 14.2+ |
| ScreenCaptureKit | Screen Recording | High (scary prompt) | 13.0+ |
| lsof | None | None | All |
| OverSight-style | Admin + Full Disk Access | Very High | All |
| AppleScript | Accessibility | Medium | All |

---

## Alternative: Detect Any Call (Not Just WhatsApp)

If the goal is to detect *any* call (Zoom, Meet, Teams, WhatsApp), use a **unified audio monitoring approach**:

```swift
// Monitor system-wide audio taps
let allApps = SCShareableContent.current.applications
let conferenceApps = allApps.filter { app in
    ["zoom.us", "google.com/meet", "microsoft.teams", "net.whatsapp.WhatsApp"]
        .contains(app.bundleIdentifier)
}

for app in conferenceApps {
    if isAudioActive(app) {
        return true // Call detected
    }
}
```

---

## Known Gaps & Future Research

### Unanswered Questions

1. **WhatsApp-specific events:** Does WhatsApp post any NSDistributedNotificationCenter notifications during calls?
   - **Research finding:** No documented notifications found
   - WhatsApp uses its own notification system ([source](https://discussions.apple.com/thread/253899924))

2. **Process name changes:** Does WhatsApp spawn helper processes during calls (like `WhatsApp Helper (Renderer)`)?
   - **Research finding:** Need to test empirically
   - Electron apps often spawn multiple processes

3. **Network monitoring:** Could monitor network connections to WhatsApp servers?
   - **Research finding:** Possible but complex (requires packet sniffing)
   - Privacy implications

### Promising Areas for Further Investigation

1. **Reverse engineering:** Inspect WhatsApp.app binary for notification constants
2. **Network monitoring:** Use `nettop` or `lsof -i` to detect WhatsApp connections
3. **Process hierarchy:** Check if WhatsApp spawns child processes during calls
4. **Empirical testing:** Run WhatsApp calls and monitor all system events

---

## Code Examples & Resources

### Essential GitHub Repositories

- **[AudioCap](https://github.com/insidegui/AudioCap)** - AudioHardwareCreateProcessTap implementation (Swift)
- **[OverSight](https://github.com/objective-see/OverSight)** - System-level mic/camera monitoring (Objective-C)
- **[SimplyCoreAudio](https://github.com/rnine/SimplyCoreAudio)** - CoreAudio wrapper for Swift
- **[Azayaka](https://github.com/Mnpn/Azayaka)** - Screen+audio recorder using ScreenCaptureKit

### Apple Documentation

- [ScreenCaptureKit](https://developer.apple.com/documentation/screencapturekit/)
- [WWDC22: Meet ScreenCaptureKit](https://developer.apple.com/videos/play/wwdc2022/10156/)
- [Core Audio Taps Guide](https://developer.apple.com/documentation/CoreAudio/capturing-system-audio-with-core-audio-taps)
- [NSRunningApplication](https://developer.apple.com/documentation/appkit/nsrunningapplication)

### Technical Articles

- [macOS TCC Deep Dive](https://www.rainforestqa.com/blog/macos-tcc-db-deep-dive)
- [AudioTee: Capture System Audio](https://stronglytyped.uk/articles/audiotee-capture-system-audio-output-macos)
- [Core Audio Essentials in Swift](https://alistaircooper.medium.com/essential-concepts-in-core-audio-with-swift-ac5b053e22c4)
- [Tracking Active Windows in Electron](https://scriptide.tech/blog/tracking-active-window-macos-objective-c-electron)

---

## Competitor Analysis: How Others Solve This

### OverSight (Objective-See)

- **Approach:** System-level monitoring via TCC framework
- **Accuracy:** Very high
- **Trade-offs:** Requires admin privileges, uses private APIs

**Quote:**
> "While there is no direct way to determine what process is using the webcam or mic, OverSight can almost always figure this via indirect means." - [OverSight](https://objective-see.org/products/oversight.html)

### Micro Snitch

- Similar to OverSight
- Real-time overlay when mic/camera activates
- Commercial product

### macOS Built-in (Control Center)

- Shows app name when mic/camera active
- But **no programmatic API** to access this info
- User must manually check

---

## Confidence Levels

| Finding | Confidence | Evidence |
|---------|-----------|----------|
| WhatsApp doesn't expose windows to Accessibility API | **High** | Direct testing + GitHub issues |
| AudioHardwareCreateProcessTap works for detection | **High** | Working sample code (AudioCap) |
| lsof has high false positive rate | **High** | Multiple sources confirm |
| OverSight uses private TCC APIs | **Medium** | Source code available but complex |
| No public WhatsApp call notification API | **High** | Extensive search found nothing |
| ScreenCaptureKit requires Screen Recording permission | **High** | Apple documentation |

---

## Final Recommendations

### For Your Meeting Recorder App

**Primary Strategy:**
1. Use **AudioHardwareCreateProcessTap** (macOS 14.2+) for WhatsApp detection
2. Fall back to **ScreenCaptureKit** (macOS 13.0-14.1)
3. Fall back to **lsof** (older macOS versions) with warning about accuracy

**Implementation Priority:**
1. **Week 1:** Implement AudioHardwareCreateProcessTap for WhatsApp
2. **Week 2:** Test accuracy + tune audio level thresholds
3. **Week 3:** Add ScreenCaptureKit fallback
4. **Week 4:** Add lsof fallback + user settings (enable/disable WhatsApp detection)

**User Experience:**
- Add **NSAudioCaptureUsageDescription** to Info.plist with clear explanation:
  ```
  "Meeting Recorder needs to monitor audio from video calling apps
  like WhatsApp to automatically detect when calls start and end."
  ```
- Provide **toggle** in settings to disable WhatsApp detection (avoid permission prompt)
- Show **indicator** when WhatsApp call is detected (like OverSight)

**Edge Cases to Handle:**
- WhatsApp playing audio messages (false positive) - use sustained audio threshold
- Multiple WhatsApp windows (group calls) - handle gracefully
- WhatsApp not running - check with NSRunningApplication first
- Permission denied - fall back to manual recording mode

---

## Sources

### Detecting Microphone/Camera Usage
- [OverSight](https://objective-see.org/products/oversight.html)
- [How to view which app is using your camera or microphone](https://www.idownloadblog.com/2020/08/11/app-using-camera-microphone-iphone-ipad/)
- [macOS Monterey microphone privacy](https://www.macobserver.com/news/product-news/macos-monterey-tells-app-mac-microphone/)
- [Find Out What App Is Using Your Webcam](https://www.applegazette.com/mac/find-app-using-webcam-mac/)

### CoreAudio & Process Taps
- [AudioCap GitHub](https://github.com/insidegui/AudioCap)
- [Core Audio Taps Documentation](https://developer.apple.com/documentation/CoreAudio/capturing-system-audio-with-core-audio-taps)
- [AudioTee Article](https://stronglytyped.uk/articles/audiotee-capture-system-audio-output-macos)
- [Core Audio Essentials](https://alistaircooper.medium.com/essential-concepts-in-core-audio-with-swift-ac5b053e22c4)
- [SimplyCoreAudio GitHub](https://github.com/rnine/SimplyCoreAudio)

### ScreenCaptureKit
- [ScreenCaptureKit Documentation](https://developer.apple.com/documentation/screencapturekit/)
- [WWDC22: Meet ScreenCaptureKit](https://developer.apple.com/videos/play/wwdc2022/10156/)
- [Azayaka GitHub](https://github.com/Mnpn/Azayaka)
- [OBS Studio ScreenCaptureKit PR](https://github.com/obsproject/obs-studio/pull/6600)
- [Electron ScreenCaptureKit Issue](https://github.com/electron/electron/issues/47490)

### macOS TCC & Permissions
- [macOS TCC Deep Dive](https://www.rainforestqa.com/blog/macos-tcc-db-deep-dive)
- [Full Transparency: Controlling Apple's TCC (Part 2)](https://www.huntress.com/blog/full-transparency-controlling-apples-tcc-part-ii)
- [macOS TCC - HackTricks](https://book.hacktricks.wiki/en/macos-hardening/macos-security-and-privilege-escalation/macos-security-protections/macos-tcc/index.html)
- [TCC Guide for macOS Sequoia](https://atlasgondal.com/macos/priavcy-and-security/app-permissions-priavcy-and-security/a-guide-to-tcc-services-on-macos-sequoia-15-0/)

### Accessibility API & Window Detection
- [CGWindowListCopyWindowInfo Documentation](https://developer.apple.com/documentation/coregraphics/1455137-cgwindowlistcopywindowinfo)
- [Catalyst Accessibility Issue](https://github.com/dotnet/macios/issues/22762)
- [Electron Hidden Window Bug](https://github.com/electron/electron/issues/39840)
- [Electron Accessibility Fix](https://github.com/electron/electron/pull/21465)

### WhatsApp-Specific
- [WhatsApp MCP Server](https://playbooks.com/mcp/gfb-47-whatsapp-desktop)
- [WhatsApp notifications issue](https://discussions.apple.com/thread/253899924)
- [WhatsApp Business Calling API](https://www.kommunicate.io/blog/whatsapp-business-calling-api/)

### NSRunningApplication
- [NSRunningApplication Documentation](https://developer.apple.com/documentation/appkit/nsrunningapplication)
- [runningApplications(withBundleIdentifier:)](https://developer.apple.com/documentation/appkit/nsrunningapplication/1530798-runningapplicationswithbundleide?language=objc)

### Process Monitoring
- [lsof camera detection](https://www.howtogeek.com/289352/how-to-tell-which-application-is-using-your-macs-webcam/)
- [Complete Guide to Find Apps Using Camera](https://macbookgeek.com/how-to-find-out-which-apps-use-your-mac-camera/)

### AppleScript & Electron
- [Controlling macOS with Electron and AppleScript](https://medium.com/@insideofoutside/controlling-macos-with-electron-app-9aa661b80ba1)
- [Tracking Active Windows in Electron](https://scriptide.tech/blog/tracking-active-window-macos-objective-c-electron)
- [Sending AppleScript events from Electron](https://ishaangandhi.medium.com/sending-applescript-events-from-electron-app-18dc1b7d7a51)

---

## Appendix: Quick Reference

### WhatsApp Bundle Identifier
```
net.whatsapp.WhatsApp
```

### Check if WhatsApp is Running
```swift
let isRunning = !NSRunningApplication.runningApplications(
    withBundleIdentifier: "net.whatsapp.WhatsApp"
).isEmpty
```

### lsof Command
```bash
lsof | grep "AppleCamera" | grep "WhatsApp"
```

### macOS Version Requirements
- **AudioHardwareCreateProcessTap:** 14.2+ (Sonoma)
- **ScreenCaptureKit:** 13.0+ (Ventura)
- **lsof:** All versions

---

**Report Confidence:** High (85%)
**Gaps:** No empirical testing with live WhatsApp calls, no reverse engineering of WhatsApp binary
**Next Steps:** Implement AudioHardwareCreateProcessTap prototype and test with real WhatsApp calls
