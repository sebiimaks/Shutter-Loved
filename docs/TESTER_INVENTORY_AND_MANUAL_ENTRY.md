# Testers and manual readings in Shutter Loved 0.3.3

Shutter Loved records results from the Baby Shutter Tester series by manual entry, alongside its existing Shutter Lover USB reader. Each new reading records which model produced it and, when selected, the saved details of your individual tester.

## Record your equipment

1. Open **My testers** in the sidebar or **File → My Testers…**.
2. Choose **Add tester** and select its model. The catalogue accepts only **Shutter Lover**, **Baby Shutter Tester Mk I**, and **Baby Shutter Tester Mk II** from Photography Electronics. The manufacturer's [project history](https://github.com/sebastienroy/shutter_speed_tester) confirms the original commercial Mk I; its [current shop](https://photographyelectronics.com/shop/) lists Mk II and Shutter Lover. No generic or third-party model can be entered.
3. Optionally enter a nickname, the hardware serial printed on the unit, firmware version, calibration/check date, calibration notes and ownership/accessory notes. If the nickname is blank, the model name is used.
4. Choose **Save tester**. A saved unit's model cannot be changed; create another equipment record for a different unit/model.

The displayed **App record UUID** identifies this equipment record in your library. It is not a factory serial or a UUID supplied by the tester. Two units of the same model receive different app UUIDs. A unit with no hardware serial can still be recorded and explicitly selected for readings.

Edits apply to future readings. Removing a tester asks for confirmation, removes its saved USB association, and retains historical readings with their original tester snapshots. Disconnect an actively recording tester before editing or removing its profile.

## Shutter Lover calibration document and distance

In **My testers → Edit…**, open **Calibration / checks** for a Shutter Lover. Enter the optional **Calibrated optimal distance (mm)** from that individual unit's documentation. For example, 25 cm is 250 mm; leave the field blank if unknown. The manufacturer defines this as the optimum distance from the case LEDs to the sensor in its [Shutter Lover manual, calibration section](https://photographyelectronics.com/wp-content/uploads/2025/06/ShutterLover_UserManual_en_1.1.0_-_Release.pdf). It is a setup reference, not an observed distance or a software correction. The app accepts positive finite values up to 10,000 mm as an entry bound, not a specified hardware operating range.

Choose **Attach calibration certificate…** to select a PDF or PNG, JPEG, TIFF or HEIC scan/photo, up to 10 MB. Use **Preview…**, **Save a copy…**, **Replace…** or **Remove** to manage it. Choose **Save tester** to commit both the distance and attachment. **Cancel** discards staged changes; the original document is never edited. These fields appear only for Shutter Lover.

The certificate's exact bytes are copied into the equipment library; moving or removing the original file does not break the attachment. A full Application Support library backup includes it. Camera/session archives and Armarium exports do not include the certificate itself. Save a copy to share it separately. Replacing/removing a certificate or removing its equipment record removes that active library attachment, so keep a separate copy if needed.

New readings retain the calibrated distance in their immutable tester snapshot. It appears in reading details, reports, CSV and Armarium provenance notes. Existing readings remain unchanged. Different recorded calibrated distances form separate result groups. This optional addition remains compatible with schema-3 libraries and version-2 session/camera archives; missing older values remain unknown.

## Position a connected Shutter Lover using the camera mount

1. Save the individual Shutter Lover's calibration distance in **My testers**, and select it for the connection or associate its unique USB identity.
2. Set the camera's **Mount** in its camera details. **Choose mount…** offers the same reference table used for positioning; imported or typed mount text is also accepted when it matches a known name or alias exactly.
3. Start/open that camera's test and connect the tester. The test view automatically shows **LEDs → mount**. Open **Positioning details…** for the camera and tester names, calculation and physical positioning instructions. The connection panel also shows the distance for the actual recording camera.

The calculation is **LED-to-mount spacing = calibrated LED-to-sensor distance − flange focal distance**. For example, a 250 mm calibration with a Nikon F mount's 46.5 mm default gives 203.5 mm. Remove the lens and measure from the LEDs to the camera's lens-seating flange, with the tester sensor at the film plane, no mount adapter, and the tester and sensor aligned parallel. This is a calculated setup reference; the app does not measure the actual placement. An adapter, altered camera or displaced sensor requires an appropriate physical reference rather than blindly using the bare-mount calculation.

Before connection, selecting an owned tester provides a **Positioning preview**. During recording, guidance uses the connected tester's captured calibration and the active test's assigned camera. Browsing another camera does not change the recording target; its test shows its own preview. Connecting from a camera's library page selects a suitable existing test for that camera or creates one, rather than recording into an unrelated previously viewed test.

Missing calibration, an unassigned camera, an unknown/ambiguous mount, unreadable settings, or a calibration distance no greater than the flange distance produces an explanation instead of a guessed number. In particular, **M39** does not uniquely identify a mount; choose the precise rangefinder or SLR variant.

### Edit the flange-distance reference table

Open **Shutter Loved → Settings…** (⌘,) or **Positioning details… → Flange distances…** in the measurement workspace. If positioning is unavailable, choose **Set up…** for the reason and reference-table link. Search for a mount, inspect its default, source links and notes, and edit its distance in millimetres. Individual defaults can be restored. Custom mounts can be added for a missing or modified system. Changes update positioning guidance; they do not alter timing measurements or historical tester snapshots.

The built-in factual table combines the requested [Brian Smith flange-distance guide](https://briansmith.com/flange-focal-distance-guide/) and [Wikipedia flange-distance table](https://en.wikipedia.org/wiki/Flange_focal_distance), checked on **30 September 2026**. Source disagreements and reference-plane distinctions are noted in the relevant entries. These are editable reference defaults, not a claim that every camera body or mount adapter has been measured. Values and custom entries must be positive finite numbers up to 1,000 mm, an input bound rather than a hardware specification.

Overrides and custom entries are local application settings, separate from camera/test evidence. They persist across restarts and are not included in camera/session or Armarium exports. Invalid stored settings are preserved and block calculations until the user explicitly restores defaults; they are not silently replaced.

## Associate a USB device

The equipment editor's **Recognise this tester by USB** picker lists discovered serial devices with a unique USB vendor ID, product ID and nonblank serial number. Connect the tester using a data cable and choose **Refresh devices**. Select the correct physical tester, inspect the vendor/product and USB serial details, and save. **Clear USB association** removes the binding; disconnection alone does not remove it.

Discovery reads macOS IOKit registry properties without opening the serial port or transmitting identification commands. Matching uses the vendor/product/serial combination, preserves serial case, and ignores surrounding whitespace. It never substitutes a port path, USB location, friendly device name or model for a stable hardware identity. It stops at the nearest physical USB device so a missing tester serial cannot be replaced by a hub's serial.

Devices with missing serials, duplicate connected identities or an association to another equipment record are omitted from the editor picker. The library rejects duplicate bindings. A USB serial can be absent or reused by firmware; it is not an authentication credential. Selecting an existing tester explicitly for a connection is available when stable USB matching is unavailable. If a saved binding conflicts with the chosen port, change the selection or deliberately update the association before recording.

The [Shutter Lover interface specification](https://github.com/sebastienroy/shutter_lover_remote_app/wiki/Interface-Specifications) includes firmware and timing fields, but no individual tester UUID/serial. The app can recognise saved equipment through USB metadata when available. It does not infer the model from an arbitrary serial port: the user chooses equipment, and Shutter Lover acquisition accepts its supported measurement packets.

USB associations may also be stored for Baby models that expose a usable serial device. **This does not enable automatic Baby capture.** Manufacturer [Mk II firmware 1.1.0 added USB JSON output](https://photographyelectronics.com/resources/firmware-update/); its [reference application and interface documentation](https://photographyelectronics.com/resources/interface-specification/) describe a separate protocol. This app currently records Baby results through manual entry.

## Enter Baby results

1. Use **File → New Baby Tester Test**, or start a test on a camera and choose a Baby model or owned unit in **Tester for next reading**. Start a separate test for a different model. Baby manual readings cannot be mixed with Shutter Lover USB packets in one test.
2. Follow the instructions for that model and firmware, take a measurement on the device, and choose **Add manual reading…**.
3. Choose the model/owned tester and enter the camera's nominal setting. For 1/125 s, enter `125` or `1/125`. For a two-second nominal setting, enter `0.5` as its reciprocal denominator.
4. Select the displayed unit and copy the measured number. Enter `8` in **Milliseconds** for 8 ms, `0.008` in **Seconds** for the same duration, or `125` / `1/125` in **Reciprocal seconds**. The app shows a converted preview and retains the original numeric value and selected unit.
5. Set the measurement date/time and optional notes. Mk II additionally accepts **Automatic**, **Global** or **Not recorded**, plus optional E₀ on its unitless 0–100 scale. Global mode can also record the series maximum E₀. Leave unknown values blank.
6. Choose **Add reading**, or **Save & add another** to keep the form open for a series.

Validation requires finite positive exposure values from 1 microsecond to 1,000 seconds, and a valid nominal setting. These are data-entry bounds, not claims about a tester's certified operating range. E₀ values must lie between 0 and 100; a series maximum requires Global mode and cannot be lower than that reading's E₀. Mk I cannot store Mk II mode/E₀ fields. Invalid entries remain in the form for correction and are not committed.

Manual records contain the entered value/unit, time, nominal camera setting, notes, conditions and tester snapshot. They contain no fabricated raw serial packet, corner readings, sensor position or curtain travel. Mk II results are labelled **effective exposure**, while Mk I results are labelled **measured exposure**. Calculated equivalents and timing differences do not change the source entry.

## Use the correct model instructions

**Shutter Lover:** follow the individual unit's calibration distance, sensor orientation/alignment and reset procedure. The [English manual 1.1.0](https://photographyelectronics.com/wp-content/uploads/2025/06/ShutterLover_UserManual_en_1.1.0_-_Release.pdf) and [USB interface specification](https://github.com/sebastienroy/shutter_lover_remote_app/wiki/Interface-Specifications) remain the sources for its USB readings.

**Baby Shutter Tester Mk I:** check the firmware in Information mode and use the [manufacturer's firmware-specific manual index](https://github.com/sebastienroy/shutter_speed_tester/wiki/Shutter-Testers-documentation). It separates [firmware 2.0.1 and later](https://github.com/sebastienroy/shutter_speed_tester/blob/master/baby_shutter_tester/documentation/2.0.1/BabyShutterTester_UserManual_en_2.0.1_--.pdf), [2.0.0](https://github.com/sebastienroy/shutter_speed_tester/blob/master/baby_shutter_tester/documentation/2.0.0/BabyShutterTester_UserManual_en_2.0.0_--.pdf), and [1.1.0 through 1.2.1](https://github.com/sebastienroy/shutter_speed_tester/blob/master/baby_shutter_tester/documentation/1.1.0/BabyShutterTester_Manual_en_1.1.0_-C.pdf). The in-app setup summary is explicitly based on manual 2.0.1: fixed alignment and subdued ambient light are required for high-speed calibration; use Test mode's distance indication, then measure without changing the setup and reset between shots. Mk II's Automatic/Global modes and calibration-free operation do not apply to Mk I.

**Baby Shutter Tester Mk II:** use the [English manual 1.0.0-B](https://photographyelectronics.com/wp-content/uploads/2025/08/BabyShutterTester_mkII_UserManual_en_1.0.0_-B.pdf). Its effective-time method differs from Mk I. Use diffuse illumination covering the lens for leaf shutters; choose Automatic or Global according to the manual. Global measurements require fixed illumination/aperture and a controlled series. The app records your selected mode and copied E₀; it does not control the device's mode, calibrate it, or correct an unsuitable lighting setup.

Sources and the Mk I 2.0.1 manual were checked on 29 September 2026. The PDFs are linked, not redistributed in the app. Consult the complete document for your firmware before testing.

## Results, provenance and interchange

Every new reading has an immutable tester snapshot containing the known model, owned UUID/name, hardware serial, firmware, calibration details and, for USB captures, observed USB identity/path. Changing the inventory or the tester chosen for the next reading does not relabel existing readings. Old USB packets identify the **Shutter Lover** model; their physical unit remains **not recorded**. A newly added inventory profile is never guessed to be that historical unit.

Summaries and comparisons distinguish tester context alongside nominal setting and curtain direction. Context includes model, known individual identity, manual versus USB acquisition and Mk II mode. Different contexts do not silently share a mean. Unidentified old ports can separate groups conservatively, but the port is never presented as a persistent hardware identifier. USB model context, manual Mk I measured exposure and manual Mk II effective exposure retain distinct descriptions.

Armarium Lucis uses the unchanged **Shutter Tester JSON v1** contract. Manual results export as numeric-second `exposureDuration` values. Supported tester fields and provenance notes identify the tester and manual source, original units, and effective versus measured exposure. Unknown sensor positions, corner exposures and curtain quantities are omitted. Existing camera/test UUID and revision rules, catalogue validation, quantity limits and conflict handling remain in force. The exact local evidence belongs in a full archive; Armarium JSON is an interchange summary, not an inventory backup.

## Storage and backups

The local library is now **schema 3**, storing cameras, sessions and `ownedTesters`. When loading a schema-2 library, the app saves its exact original bytes as **`library.pre-tester-library.json`** before migration. Existing identifiers, measurements and revisions are preserved. **`library.previous.json`** continues to hold the previous saved snapshot. Migration from the older `sessions.json` retains its separate **`sessions.pre-camera-library.json`** backup.

Portable `.shutterlover` sessions and `.shuttercamera` camera archives are now **version 2** and retain manual entries and reading-level tester snapshots. The app reads versions 1 and 2. Camera/session copies preserve historical tester provenance but do not create equipment inventory entries or USB bindings. Back up the complete Application Support library directory, including photos and imported archives, to preserve editable equipment records and all local evidence. Older app versions do not understand the new storage/archive versions.

Model validation applies to decoded storage and imports, not just picker controls. Unknown models, duplicate owned UUIDs/USB bindings and inconsistent manual/USB evidence are rejected. Saves are atomic; a failed write does not publish a successful edit.

The integrated 0.3.1 automated run executed 133 tests: 132 passed; the existing hardware-busy simulation skipped because the host's pseudo-terminal driver does not enforce exclusive access. Calibration checks include exact certificate-byte persistence after deleting the original, all accepted image formats, malformed and password-locked files, distance/model validation, legacy decoding, immutable distance snapshots, export column alignment and Armarium/PDF provenance.

Native UI checks used a separate app container and synthetic equipment/readings. They verified the three-model picker, owned tester creation, invalid-value blocking, millisecond and reciprocal-second entry, Global-mode illumination fields, repeated entry, reading-level tester details, and persistence after restart. Manual results displayed no invented corner or curtain-travel measurements. The user's existing schema-2 library also migrated to schema 3 with its library identity, cameras and sessions unchanged; the pre-migration backup matched the original bytes exactly. No physical tester was used in these checks, so USB hardware matching and live acquisition still require testing with the user's equipment.

For 0.3.1, native checks in that isolated container verified zero-distance rejection, attaching and previewing a synthetic PDF, saving a byte-identical copy, persistence of the distance and embedded certificate after restart, and cancellation of a staged attachment removal. The arm64 release build and signature verification passed. The existing real library, including its equipment records and readings, remained unchanged after opening the update.

For 0.3.2 (build 8), the integrated run executed 156 tests: 155 passed and the same host-dependent busy-port test skipped. New coverage includes mount aliases and ambiguity, persisted overrides and custom mounts, invalid/corrupt settings, positioning geometry, saved versus connected tester context, USB recognition, and the recording target when connecting from a camera page.

Native checks on 30 September 2026 used the isolated QA container to create a synthetic Canon FD camera through the searchable mount chooser. A saved Shutter Lover with a 250.5 mm calibration displayed 208.5 mm LED-to-mount spacing. Editing Canon FD from 42 to 43 mm immediately changed the preview to 207.5 mm with a custom-value label; both the override and calculation survived restarting the app. Zero disabled Save. Source links, reference/reset controls and the Settings layout were inspected. The arm64 release build and signature verification passed. Opening the update preserved the user's full library JSON unchanged. Physical positioning, hardware recognition and live acquisition were not exercised with a real tester.

## Compact measurement workspace (0.3.3)

The setup area remains visible above the readings table, without its former nested scrolling pane. Camera identity and assignment, tester selection, exposure setting, curtain direction and next-speed suggestion share one compact group. A linked test shows its title on the test-details button. Delete test remains a visible trash button; deletion still asks for confirmation.

The LED-to-mount distance stays visible when available. **Positioning details…** opens the full formula, calibration context and positioning instructions; **Set up…** explains missing information. **Notes** opens a saved text editor without expanding the setup area. **Speed coverage…** opens the planned-speed grid. The three equal-height result cards and repeatability summary remain above the readings table; selecting a reading updates them as before. Long reading histories and optional detail panels can still scroll.

Native checks used the separate QA app container at the minimum window height, with a 610-point measurement pane and the reading inspector open. Shutter Lover positioning, missing-data guidance, notes, coverage, Baby manual readings and demo reading selection remained accessible. Text entered in the dedicated Notes editor was verified in the saved library. The Apple Silicon release build and signature verification passed, and opening the final build preserved the user's full library JSON unchanged. This change only reorganises views; measurement calculations, storage and interchange schemas remain unchanged.
