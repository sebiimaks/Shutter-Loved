# Shutter Loved for macOS — native app build plan

Prepared 27 September 2026. The original proposal below is retained as the release roadmap. A working native alpha is now implemented in `macos/`; see [the implementation README](../macos/README.md) for what is complete, how to run it, and remaining hardware/release checks.

Planning validation: the requirements and formulas were reviewed against the cloned source and upstream documentation. The interface concept was checked in a browser at desktop and narrow widths, including metric explanations and adding a simulated reading. These checks validate the proposal, not USB compatibility.

## Recommendation

Build a native **Swift + SwiftUI macOS application for Apple Silicon**, with a proposed minimum of **macOS 14**. Use a focused measurement workspace, a session library, and contextual explanations. Preserve all existing measurements while making the everyday workflow understandable without reading the interface specification.

The first release should let someone connect their tester, understand how to take a reading, record a camera session, inspect trustworthy results, and reopen or export that session. Use native tables, menus, keyboard shortcuts, light/dark appearance, and a collapsible inspector. Deliver a signed, notarized app in a drag-to-install DMG.

These are recommended planning defaults, not confirmed user constraints. macOS 14 provides a practical baseline for the proposed observation, persistence, and inspector APIs; current macOS styling should come from system components rather than a hand-built imitation.

## Reviewed baseline

Fork repository: [sebiimaks/Shutter-Loved](https://github.com/sebiimaks/Shutter-Loved), originally cloned as `sebiimaks/shutter_lover_remote_app`.

Reviewed commit: `47195037ddad661b75ce052e16625a85cd90f6aa` (8 June 2026). The Python source identifies itself as version 1.2.0. It is a small Tkinter application with PySerial and one main Python file. Its LICENSE contains GPL version 3; preserve the existing license and attribution when extending this repository.

| Existing capability | Native replacement requirement |
| --- | --- |
| Serial-port list, connection status, background receipt of JSON | Device picker with meaningful status, hot-plug handling, and reconnect |
| Vertical/horizontal curtain selection | Explicit camera setup with a diagram and per-reading geometry |
| Camera-speed selector and editable recorded setting | Familiar fractions such as `1/125 s`, custom exposure durations, clear correction action |
| Auto-increment in this fork | Keep the `1/15 → 1/30 → 1/60 → 1/125 → 1/250 → 1/500 → 1/1000` sequence available |
| Sixteen table columns | Keep every field; show a useful subset first and the remainder in details or optional columns |
| Tab-separated clipboard export | Preserve a compatible export and add clean CSV plus a complete session file |
| Clear all | Provide New Session and an undoable delete operation |
| Synthetic test input | Provide a clearly marked demo/replay transport for development and onboarding |

The source is the authority for fork-specific behavior; the README does not describe auto-increment. The original window is `1024×200` and places connection, geometry, speed, actions, and sixteen measurement columns into a compact layout. The main improvement is to separate setup, capture, and interpretation.

Current reliability gaps to address include missing persistent sessions, limited input validation, connection attempts against the first listed port, a potentially blocking line read, and lost measurement context in clipboard exports. Curtain direction changes the factor for future readings, but is not stored alongside each existing reading.

Source references: [source at the reviewed commit](https://github.com/sebiimaks/Shutter-Loved/blob/47195037ddad661b75ce052e16625a85cd90f6aa/shutter_lover_remote_app.py), [README](https://github.com/sebiimaks/Shutter-Loved/blob/47195037ddad661b75ce052e16625a85cd90f6aa/README.md), [LICENSE](https://github.com/sebiimaks/Shutter-Loved/blob/47195037ddad661b75ce052e16625a85cd90f6aa/LICENSE).

## Hardware boundary

The app receives timing measurements; it does not measure shutter timing using Mac clocks. The published USB interface is a virtual serial port carrying line-delimited JSON. The event currently handled is `MultiSensorMeasure`; timestamps and calibration offsets are in microseconds. Text that is not JSON can also appear on the connection. Corner offsets are required corrections, and a negative raw timestamp means that the corresponding event was not measured.

The documented workflow involves physical actions on the tester and camera. Do not present a software Fire, Arm, Reset Tester, or Change Camera Speed action: no host command for these operations is documented. A connection indicator may say “Listening for measurements”; it must not claim that the tester is armed or that its sensors are currently illuminated.

The documented sensor rectangle is 32 mm wide by 20 mm high. The existing app extrapolates to a 36 mm wide by 24 mm high film frame. This is an estimate based on geometry and approximately uniform travel, not an additional sensor measurement.

The published specification does not establish all transport settings or USB identifiers. Confirm baud rate, framing, flow control, DTR/RTS behavior, device identity, driver requirements, firmware variants, and any reset-on-open behavior with the actual device before freezing the transport implementation.

The manufacturer's manual also describes a physical Test mode to check illumination at all three sensor positions, a cable-right placement convention when facing the camera, and a specified LED-to-sensor distance. Incomplete results can arrive after approximately two seconds. Put these instructions, with the relevant device revision, in setup help; the Mac cannot infer live illumination or readiness from the published measurement event.

Sources: [upstream interface specification](https://github.com/sebastienroy/shutter_lover_remote_app/wiki/Interface-Specifications), [raw specification](https://raw.githubusercontent.com/wiki/sebastienroy/shutter_lover_remote_app/Interface-Specifications.md), [manufacturer user manual v1.1.0](https://photographyelectronics.com/wp-content/uploads/2025/06/ShutterLover_UserManual_en_1.1.0_-_Release.pdf), [manufacturer site](https://photographyelectronics.com).

## The intended workflow

1. **Connect.** Show likely compatible devices and remember a previously selected device. Keep a manual picker. When identity is uncertain, let the user choose rather than opening arbitrary serial devices. A port can be open without a Shutter Lover measurement having been received.
2. **Set up a session.** Enter a camera name, optional serial number and notes; choose curtain travel direction; select the exposure actually set on the camera. Make “Unknown direction” a valid choice: measured values remain available and extrapolation stays unavailable.
3. **Prepare the reading.** Give a short illustrated checklist: position the tester and light as directed by the manufacturer, set the camera, physically reset the tester, then release the camera shutter. The app waits for a result.
4. **Review.** Show the latest center exposure, difference from the target, and curtain travel. Append a timestamped row, preserve the original data, and save the reading. A partial reading remains visible with an explanation of the missing sensor events.
5. **Repeat.** Stay at the same setting by default. If auto-advance is enabled, show the next suggested camera setting prominently. The user changes the camera manually. Partial or invalid readings do not advance a guided sequence by default.
6. **Finish and reuse.** Reopen saved sessions, add notes, compare repeat readings, copy a selection, or export a complete session. Starting a new session preserves the previous one.

## Interface layout

Use a resizable native window with three areas:

| Area | Contents | Purpose |
| --- | --- | --- |
| Sidebar | Current session, saved sessions, camera profiles, guide | Stable navigation without a crowded toolbar |
| Main workspace | Session title; compact camera setup; next physical action; latest reading; measurement table | Keep the measurement loop visible |
| Optional right inspector | Selected reading, three sensor values, curtain timings, explanations, notes, raw data disclosure | Make detail available without forcing sixteen columns on everyone |

The toolbar contains the device/status control, New Session, Export, and the inspector toggle. File and Edit menus carry their normal Mac equivalents. Put destructive deletion in a menu or context menu with Undo, away from the primary capture workflow.

Default table columns: reading number, time received, camera setting, measured center exposure, exposure difference, and quality. Optional columns expose both curtain travel measurements, estimated full-frame travel, all three sensor durations and reciprocal speeds, and segment timings. Use sorting and row selection without changing capture order or sequence state. Do not pull the view back to the newest row while someone is inspecting older data; offer a Follow Latest control.

Use a neutral background, restrained accent color, system typography, SF Symbols, and aligned numerals. Reserve status color for meaning and pair it with text. Keep every measurement value selectable for copying. Explanations must work with keyboard focus and VoiceOver, not only hover. At smaller window sizes, collapse the sidebar and inspector before hiding essential capture controls.

The interface concept uses synthetic readings to demonstrate navigation and explanations. It is a design aid; it is not a running native application or evidence of device connectivity.

## Function explanations to ship in the app

Each unfamiliar control gets a short visible explanation or an adjacent information button. The inspector adds units, interpretation, and a worked example; a bundled, searchable guide provides the longer explanation offline. Keep the same names in the UI, help, and exports.

| Function | Suggested plain-language explanation |
| --- | --- |
| Device | “Choose the Shutter Lover connected to your Mac. If it is missing, check the USB data cable and device power.” |
| Listening | “The connection is open. Reset the tester and fire the camera shutter to send a reading.” |
| Camera setting | “The exposure selected on the camera. This is the reference for comparison; changing it here does not change the camera.” |
| Curtain direction | “The direction the curtains cross the film frame. This changes the full-frame travel estimate.” |
| Unknown direction | “Sensor measurements are still available. Select a direction to calculate full-frame estimates.” |
| Auto-advance | “After a complete reading, suggest the next setting in the sequence. Set that speed on the camera yourself.” |
| Correct setting | “Fix the reference setting recorded for this reading. The measured sensor data stays unchanged.” |
| Correct geometry | “Apply a corrected direction to selected readings. Original setup is retained; updated estimates are identified.” |
| New Session | “Start a separate set of readings. Your previous session remains saved.” |
| Exclude from statistics | “Keep this reading, but omit it from summaries. Add a reason so the result stays explainable.” |
| Copy | “Copy selected readings as a table for Numbers, Excel, or a text editor.” |
| Export | “Save a spreadsheet table, or a complete session containing original measurements and setup.” |
| Delete readings | “Remove selected readings from the session. Undo is available.” |
| Demo mode | “Explore sample measurements without a connected tester. These results are simulated.” |

### Measurement vocabulary and full parity

| Existing field(s) | Proposed label | Explanation |
| --- | --- | --- |
| Id | Reading | Session-local display number; an internal stable ID is separate |
| Setting (1/s) | Camera setting | Nominal exposure set by the user, displayed as a fraction or seconds |
| Speed (1/s), Time (ms) | Center exposure | How long the center sensor received light, displayed in ms and as an equivalent reciprocal shutter speed |
| Open (ms) | Opening curtain travel | Time between opening events at the two corner sensors |
| Close (ms) | Closing curtain travel | Time between closing events at the two corner sensors |
| Open ext, Close ext | Estimated full-frame travel | Sensor travel scaled to the selected frame and direction; clearly mark as an estimate |
| Speed Bot. L., Time Bot. L. | Bottom-left exposure | Light duration at the bottom-left sensor and its reciprocal |
| Speed Top R., Time Top R. | Top-right exposure | Light duration at the top-right sensor and its reciprocal |
| Open 1/2, Open 2/2 | Opening travel: corner–center segments | Opening-event time differences between bottom-left/center and center/top-right |
| Close 1/2, Close 2/2 | Closing travel: corner–center segments | Closing-event time differences between bottom-left/center and center/top-right |
| New | Exposure difference | Longer or shorter center exposure relative to the chosen camera setting, in stops and optionally percent |
| New | Reading quality | Complete, partial, invalid, or unverified protocol; identifies the specific missing or unsupported data |

Do not call reciprocal exposure time “curtain speed”: they are different quantities. Do not imply the labels “first half” and “second half” establish chronological direction; the original fields refer to fixed sensor pairs. A three-sensor diagram should show physical positions and the selected orientation, with only observed events plotted.

## Recommended feature priorities

### First release: reliable replacement

- All existing measurement fields, offset handling, custom camera settings, per-row corrections, clipboard export, and the fork's auto-advance sequence.
- Native USB connection lifecycle, actionable error messages, demo/replay mode, and clear partial-reading states.
- Autosaved sessions, camera identity and notes, original packet retention, undo, versioned JSON session export/import, CSV, and compatible TSV copy.
- Center exposure error in stops; per-setting repeatability summary using sample count, mean duration, standard deviation, and range. Excluded/invalid values are visible and counted separately.
- Contextual help and a short guided first session.

### Next release: most valuable additions

| Proposal | Why it helps | Boundary |
| --- | --- | --- |
| Guided speed sweeps | Repeat N readings at each chosen setting; show progress and suggest the next speed | App guidance only; camera adjustment and tester reset remain physical |
| Before/after comparison | Compare a camera before and after service using matched settings and plots | Compare consistent geometry and acquisition conditions |
| Camera profiles | Reuse direction, nominal speed list, notes, and sourced target travel times | Defaults are editable; targets require source/model/conditions |
| Sensor exposure comparison | Reveal uneven exposure across the three measured positions | Three samples are not a full-frame exposure map or a definitive fault diagnosis |
| Session report | Produce a readable PDF with setup, charts, sample counts, exclusions, and notes | Include measurement context and identify extrapolated values |
| Optional sound feedback | Let the operator hear that a reading arrived while watching the camera | Distinct sounds for complete/partial readings; off by default |
| Legacy table import | Bring older TSV exports into the session library | Mark imported rows as derived-only; raw timestamps and direction may be unrecoverable |

### Later or dependent on new hardware support

Custom film-frame geometry needs documented sensor coverage and supported mounting arrangements. A reference library should begin with user-entered, sourced values; verify licensing and applicability before bundling community data. Remote firing/reset, live sensor-level alignment, writing calibration, and firmware updates require a documented device command interface and cannot be promised from the current stream.

A useful reference is the [community curtain travel-time compilation](https://github.com/srozum/film_camera_tester/wiki/Curtains-Travel-Times). Treat it as a source to inspect for a particular camera, not a universal pass/fail threshold. “Within target” must always identify the selected target and tolerance.

## Native architecture

| Component | Proposed implementation | Responsibility |
| --- | --- | --- |
| App shell | SwiftUI `NavigationSplitView`, native table, inspector, Settings and Commands | Navigation, selection, accessibility, keyboard and window behavior |
| Presentation model | Main-actor observable state | Reflect connection/session state without performing serial work on the UI thread |
| Measurement core | Foundation-only Swift package | Typed events, validation, calibration, calculations, quality, statistics, export transformations |
| Serial transport | Small IOKit discovery + POSIX `termios` adapter, owned by a serial actor/queue | Device discovery, byte buffering, cancellation, connect/disconnect and error reporting |
| Replay transport | Same transport interface using saved/synthetic packets | Develop and test UI and calculations without hardware |
| Session repository | SwiftData local persistence with explicit save/error handling and schema migrations | Sessions, captures, annotations, profiles and restart recovery |
| Portable format | Versioned UTF-8 JSON | Export/import complete records independently of the local database |
| Charts and reports | Swift Charts; native printing/PDF path in a later phase | Repeatability, comparisons and shareable results |

Use a `MeasurementTransport` abstraction producing received bytes/events plus connection changes. Keep transport, parsing, calculation, and persistence separable so simulated and hardware data follow the same path. A single connection owner should route readings to one explicitly active session even when several windows are open.

Recommended processing order: bytes → bounded line buffer → decode/validate → preserve raw packet and setup snapshot → derive results → persist → update UI and eligible sequence progress. If saving fails, show “Not saved,” retain pending data in memory, and stop automatic advancement; never display an autosaved claim before persistence succeeds.

Apple documents the native [split-view pattern](https://developer.apple.com/documentation/swiftui/navigationsplitview) and [Swift Charts](https://developer.apple.com/documentation/charts). Its archived [serial device guide](https://developer.apple.com/library/archive/documentation/DeviceDrivers/Conceptual/WorkingWSerial/WWSerial_SerialDevs/SerialDevices.html) describes IOKit discovery and POSIX device-file access. Use that for the approach, then verify current SDK APIs and behavior in the hardware spike rather than copying the old sample directly.

### Connection and protocol rules

- Distinguish Disconnected, Connecting, Listening (unverified device), Receiving supported measurements, Reconnecting, and Error. A device may remain silent between shots; silence alone is not a disconnect.
- Identify devices using verified USB metadata where available. Prefer the remembered physical identity rather than a transient port path. Do not send probing commands to arbitrary ports.
- Match the documented CRLF framing, accepting normal LF line endings as a compatibility measure. Support a JSON line arriving in several reads and multiple lines arriving together. Bound packet and diagnostic sizes.
- Treat boot text, malformed JSON, unsupported events, unsupported units, missing fields, and disconnects as distinct outcomes. Preserve useful diagnostics without crashing or inventing a valid measurement.
- Validate integer timestamps/offsets, required keys, and supported schema. A newer firmware string alone is not proof of incompatibility; use tested schema/capability handling and show the reported version. Unknown units must not silently be treated as microseconds.
- Make offset requirements explicit by protocol version. Missing offsets are not automatically zero unless a verified schema defines that behavior.
- Confirm serial settings on hardware. The current Python app relies on [PySerial defaults](https://pyserial.readthedocs.io/en/latest/pyserial_api.html): 9600 baud, 8 data bits, no parity, one stop bit, no flow control, and no read timeout. Use 9600/8N1 as a compatibility starting point; these defaults are evidence of the app's implementation, not a complete device specification.
- Cancel reads on disconnect/termination, close the previous handle before switching ports, discard incomplete packets from a dead connection, and use bounded reconnect backoff.
- Do not deduplicate readings merely because their values match: consecutive real shots may produce identical payloads. Preserve arrival order with app-generated IDs; the published event has no guaranteed unique capture ID.
- If an operator edits setup while bytes are in flight, associate the reading with an explicitly defined receipt snapshot and offer correction. Host receipt time is not a hardware shutter-release timestamp.

### Calculation contract

Retain raw integer microseconds. Check raw negative sentinels before adding offsets; a correction must not turn a missing event into a valid event. A corrected timestamp can legitimately be negative and must not be reclassified as a missing raw event. Store calibrated values separately. For supported data, apply each corner's opening/closing offset once; center events have no published offset fields.

For parity with the current app, with corrected timestamps `t` in microseconds:

```text
sensor exposure, ms = abs(t_close − t_open) / 1,000
reciprocal exposure, 1/s = 1,000,000 / abs(t_close − t_open)
opening travel, ms = abs(t_topRightOpen − t_bottomLeftOpen) / 1,000
closing travel, ms = abs(t_topRightClose − t_bottomLeftClose) / 1,000
vertical full-frame estimate = measured travel × 24/20
horizontal full-frame estimate = measured travel × 36/32
target exposure, ms = 1,000 / reciprocal camera setting
exposure difference, stops = log2(measured exposure / target exposure)
exposure difference, percent = 100 × (measured exposure / target exposure − 1)
```

For example, a synthetic 8.2 ms center exposure against `1/125 s` (8 ms) is approximately `1/122 s`, **+0.04 stops**, or **2.5% longer**. Positive stops means longer exposure; negative means shorter. This is timing difference, not a complete photographic exposure-meter reading.

Zero duration has no finite reciprocal and is excluded from logarithms/statistics. Unexpected close-before-open ordering must be flagged for review; the legacy absolute-value calculation should not conceal suspicious input. Some metrics can remain valid when another sensor is missing; give each derived metric its own availability/quality rather than treating an entire row as either all valid or all zero.

Preserve unrounded values and round only for presentation. Compute summaries in duration space; do not average reciprocal shutter-speed denominators and call that the mean exposure. Show standard deviation only for at least two included valid readings. Group summaries by target setting and compatible setup. Do not describe displayed microsecond resolution as calibrated accuracy.

The audit evaluated the original Python helpers against the published interface example, without launching the app or opening serial hardware. Use these as initial regression expectations: center exposure **1.024 ms**, reciprocal **976.5625 s⁻¹**, corrected bottom-left exposure **0.978 ms**, corrected top-right exposure **1.120 ms**, opening travel **12.332 ms**, and closing travel **12.474 ms**. Opening-travel estimates are **14.7984 ms vertical** and **13.8735 ms horizontal**. Preserve the source packet with the future test fixture; these calculations do not establish physical calibration accuracy.

### What a saved reading contains

- Stable ID, session ID, display order, host receipt time, raw line and decoded protocol fields.
- Device identity where known, reported firmware, connection provenance, unit, raw timestamps, and all supplied offsets.
- Camera setting and direction at receipt, sensor spacing, frame dimensions, extrapolation factor, and calculation version.
- Derived values and their validity, notes, inclusion/exclusion state and reason.
- Corrections with original value, revised value and revision time; never silently change historical measurements when session defaults change.

Use an explicit portable schema version, stable numeric units and locale-independent serialization. CSV uses one header row and separate numeric fields/units; metadata belongs in defined columns or a companion session file. Offer a legacy-compatible TSV option for the old column names/order and metadata preamble. Keep missing values distinct from numeric zero. Demo data remains visibly marked in storage and exports.

## Build sequence and review gates

Approximate engineering effort for one experienced macOS developer: **16–23 working days for the first release**, subject to hardware access and protocol findings. This is a planning range, not a delivery commitment. Advanced reports, reference libraries, and comparisons are additional work.

| Phase | Effort | Deliverable | Exit condition |
| --- | --- | --- | --- |
| 1. Device/protocol spike | 2–3 days | Small arm64 reader plus captured fixtures; documented transport settings | Real hardware connects, produces parsed readings, and recovers from unplug/replug; driver and sandbox approach verified |
| 2. Measurement foundation | 2–3 days | Typed core, validation, calibration and reference fixtures | Complete and partial fixtures match legacy calculations where valid; intentional validation differences documented |
| 3. Native workspace | 3–4 days | Setup, table, selected-reading inspector, explanations, demo transport | Main workflow is usable with keyboard and VoiceOver; all sixteen original fields accessible |
| 4. Sessions and export | 3–4 days | Autosave, reopen, notes, corrections, undo, JSON/CSV/TSV | Restart preserves records; export/import retains raw data and context; failure paths are visible |
| 5. Sequence and analysis | 3–5 days | Auto-advance, per-setting summaries, quality guidance, help | Sequence follows committed setting and quality rules; statistics handle missing/excluded readings correctly |
| 6. Release qualification | 3–4 days | Signed/notarized DMG, hardware results, release notes | Release build passes hardware, persistence, accessibility, and fresh-install checks |

Start with a vertical slice that receives one real measurement and displays an explained center exposure. This establishes hardware compatibility early and gives the rest of the UI a working data path.

Suggested implementation layout when building begins:

```text
macos/
  ShutterLover.xcodeproj
  ShutterLover/
    App/
    Features/{Measurement,Sessions,Profiles,Help}/
    Persistence/
    Resources/
  Packages/
    MeasurementCore/
    DeviceTransport/
  ShutterLoverTests/
  ShutterLoverUITests/
  Fixtures/
```

Keep the Python app available as the behavior reference during migration. Do not alter its calculations just to make a new result appear to match.

## Acceptance criteria

- **Correctness:** Golden packets cover complete captures, every missing-event combination of interest, offsets of either sign, zero durations, suspicious ordering, and both direction factors. Compare numerical results with the original helpers using the same raw fixture.
- **Stream behavior:** Split packets, several packets per read, boot text, malformed JSON, unknown events/units, oversized records, unplug mid-packet, port switching, sleep/wake, and reconnect do not freeze or corrupt the session.
- **Hardware:** Record real readings using the actual tester firmware and supported Mac; test direct connection and a representative USB hub. Replay those identical packets through old and new calculations. Do not have both apps claim the same serial port concurrently.
- **Data integrity:** Saved readings survive app restart; interrupted save/import is handled; raw packets and geometry round-trip; undo/corrections preserve provenance; disk-write failure is visible. New-session and sequence changes do not rewrite old readings.
- **Usability:** A first-time user can find the device, choose a camera setting, understand a partial capture, locate all sensor metrics, and export a session without guessing acronyms.
- **Native behavior:** Keyboard navigation, VoiceOver, light/dark appearance, increased contrast, larger text, resizing, copy/paste, menus, and standard save/open panels work. No essential meaning depends on color alone.
- **Responsiveness:** Replay at least 10,000 records to check table responsiveness and bounded diagnostics. This is a software stress test, not a claim about device capture rate.
- **Distribution:** Verify the release executable is arm64 and works without Python or Rosetta. Test the downloaded, quarantined DMG on a clean supported Mac with real USB access.

Begin the serial spike with App Sandbox and the serial-device entitlement, plus user-selected file access for import/export. Verify device discovery and opening in a signed build; do not assume an entitlement alone proves hardware compatibility. Apple lists serial access in its [sandbox entitlement reference](https://developer.apple.com/library/archive/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/EnablingAppSandbox.html). If that approach fails, document the cause and assess a Developer ID distribution configuration before expanding permissions.

For public distribution, use Developer ID signing, Hardened Runtime, notarization, and ticket stapling. Signing credentials and an Apple developer account are release dependencies, not prerequisites for producing the prototype. Follow Apple's [notarization guidance](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution) and [packaging/test guidance](https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution).

## Decisions to settle during the first build phase

1. Confirm the user's tester model/revision, firmware, connection settings, USB identity, and availability for measurements.
2. Confirm whether the proposed macOS 14 minimum covers the intended Macs.
3. Establish the shipped frame/sensor geometry and orientation convention for the actual hardware.
4. Choose the default end-of-sequence behavior: recommend Stop, with Repeat available; keep the legacy looping sequence as an option.
5. Confirm initial distribution scope and signing access when preparing a public release.

These do not prevent interface or core-model work. Real-device verification is required before describing the application as a complete hardware replacement.
