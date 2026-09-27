# Shutter Loved for macOS — 0.2.3 alpha

A native SwiftUI app for Apple Silicon and macOS 14 or later. This fork was created by Sebastian Maderak, based on Shutter Lover by Sébastien Roy. Version 0.2.3 adds visible whole-test deletion and a recoverable Trash alongside individual reading deletion. Reading explanations are off by default. The app includes a tested-camera database, 3:2 photographs, dated test history, comparisons, service records, PDF reports and Armarium Lucis interchange. See the [native app plan](../docs/MACOS_NATIVE_APP_PLAN.md) and [approved camera database design](../docs/CAMERA_DATABASE_PROPOSAL.md).

## Build and run

Build with Xcode's Swift toolchain installed and selected:

```sh
cd macos
zsh scripts/build-app.sh
open "build/Shutter Loved.app"
```

The script creates an arm64 application with a local ad-hoc signature, App Sandbox, serial-device access and user-selected file access. Quit an older running build before rebuilding. If only `Shutter Lover.app` exists in the output directory, the script renames it to `Shutter Loved.app` before updating it. It uses Apple frameworks with no external package dependencies. This development build is not Developer ID signed or notarized for distribution.

For development, open `Package.swift` in Xcode, or use `swift build` / `swift run ShutterLover`. Use the bundled app for sandbox and hardware checks. Its icon is drawn locally using an SF Symbol.

## Cameras and tests

1. Choose **Add camera** in the sidebar, or **Import Armarium cameras…** to review an exported Armarium catalogue. Create one record per physical camera; matching names or serial numbers never merge bodies automatically.
2. Enter a display name and any useful identity, format, shutter, lens, condition, acquisition, storage and default-test details. Unknown values can stay blank. Search finds names, make/model, serials, collection IDs, nicknames and tags.
3. Click **Add camera photo** to choose a local image. The app retains the original and a bounded display copy. Choose **Crop to fill** or **Fit entire photo** inside the 3:2 frame. Manual crop positioning/zoom is a follow-up. File-URL drag/drop is implemented but still needs native smoke testing.
4. Choose **New test** on that camera. Set a title, operator, lighting, conditions, planned speeds, repeat target and timing tolerance through **Edit test details**. Repeat targets describe coverage; they do not automate physical shutter release or certify a camera's condition.
5. Connect the tester using **Connect tester**, select its USB serial port and click **Connect**. Use a data cable, close another application using that port, then physically reset the Shutter Lover and release the camera shutter. The app never opens an arbitrary first port or sends device commands.
6. Browse **Results**, **Test history**, **Camera details**, and **Service & notes**. Results belong to the selected dated test. Inspect original readings for every sensor metric, explanations, raw packets, exclusions and setting corrections. Compare two tests explicitly, or link before/after tests to a service event.

Existing sessions appear in **Unassigned tests**. Open one and choose **Assign this test to a camera**, then confirm the physical camera. This retains the original camera label, records the assignment time and adds that provenance to an Armarium export. Demo sessions stay separate and cannot be assigned as real camera evidence.

Browsing a camera or historical test does not redirect incoming measurements. The persistent **Recording to…** indicator names the active destination; **Return to live test** returns there. Starting a new camera test or choosing **Record into this test** explicitly changes the destination.

To explore without hardware, use a clearly marked demo session and **Add demo reading**, including partial readings from its menu. **Measurement guide** provides separate manufacturer-specific instructions for each supported guide model.

Click anywhere inside a sidebar card to open that test or camera. Within a test, select a reading and click **Delete reading** above the table, press Delete while the table is focused, or right-click the reading to delete it directly. **Undo delete** restores the most recently deleted reading and its original data. These controls delete individual readings, not the whole test.

To delete the whole test, click its sidebar **trash button**, choose **Delete test…** from the card's right-click menu, or open it and use **Delete test…** near Test details / **File → Delete Test…**. Confirm **Move to Trash**. This works for empty, real and demo tests. The **Trash** sidebar section offers **Restore**, including after restarting the app. Tests retain their readings, identifiers, export revisions and service links; there is no permanent-purge command in this build. Disconnect the tester before deleting its active recording destination. Trashed tests are omitted from normal results/history and can be exported after restoration; full camera archives retain them for recovery.

**Edit → Delete Reading** acts on the selected individual reading. **Undo Delete Reading** is a different command and stays disabled until a reading has been deleted.

Choose **Hide demo tests** above the unassigned cards (or in a demo card's context menu) to hide simulated tests without deleting them. **Show demo tests** reveals them again; **View → Show Demo Tests** controls the same preference. The choice survives relaunch. Creating a new demo reveals demo tests automatically.

## Armarium Lucis workflow

1. In Armarium Lucis, export the selected physical cameras using its **Shutter Tester** command.
2. In Shutter Loved, choose **Import Armarium cameras…** and review the batch. New identities create camera records; newer profile revisions update catalogue-owned descriptions while retaining local photos, notes, services and tests. Identical revisions are no-ops, older revisions are skipped and conflicts block the entire batch.
3. Start a test from an imported camera, or explicitly assign an existing unlinked real test to it.
4. Export that test with **Export ArmariumLucis results…** / **Test results for Armarium (JSON)…**, then review the file in the originating Armarium collection.

The independent implementation uses **Shutter Tester JSON v1**, including its catalogue and producer UUID namespaces. Camera names and serials are never matching keys. Test UUIDs stay stable across corrections; revised evidence increments its revision. Catalogue refreshes do not rewrite historical test identity.

The interchange includes only complete, included real readings, expressed as numeric seconds. A typical three-sensor reading contributes three exposures and two positive measured curtain intervals. Its **512-quantity limit permits 102 such complete readings per test**; larger exports fail clearly without truncation. Partial/invalid/excluded readings and unavailable curtain intervals are counted as omissions. Demonstrations and empty exports are blocked. Full-frame estimates are not exported as measured travel. Raw packets and complete local evidence remain in Shutter Loved.

See [SHUTTER_TESTER_JSON.md](../docs/SHUTTER_TESTER_JSON.md) for the exact field policy, defensive limits, assignment provenance and interoperability verification. ArmariumCore is not a dependency of this app.

## Choose the right export

| Export | Contains | Import/use |
| --- | --- | --- |
| **Full camera archive** (`.shuttercamera`) | Camera metadata, original/display photo, service records, all linked tests, raw packets, corrections and calculation snapshots | Import explicitly **as a separate copy** with new local camera/test/reading IDs and no Armarium link. Original archive bytes are retained locally for provenance. |
| **Complete session** (`.shutterlover`) | One schema-1-compatible session with raw packets and recorded setup | Import legacy/session files as separate unassigned copies. Camera-library metadata and photographs are not included. |
| **Armarium JSON** (`.json`) | Supported timing evidence from one stable test revision, catalogue identity, conditions and provenance notes | Review/import in the originating Armarium collection. It is not a full camera backup. |
| **CSV / Copy results** | Original measurement columns plus quality, exclusion and provenance fields; copied output is TSV | Spreadsheet analysis. Copy uses the selected reading, or all readings when there is no selection. |
| **Photo report** (`.pdf`) | Selected test summary, 3:2 photograph, camera identity, conditions, chosen tolerance, means, sample counts, SD and planned settings | Read/print/share. Individual raw evidence stays in the full archive. |

Full camera archives and local library snapshots are limited to 64 MiB; exchange JSON to 8 MiB. Photo import accepts files up to 25 MiB and retains a display image bounded to 2400 pixels. Camera-archive import preserves original measurements but deliberately creates a copy, rather than continuing the original producer's export identity.

## Measurement behavior

- All sixteen legacy measurement fields are retained. Missing, invalid, measured and estimated values stay distinct.
- Each reading keeps the nominal setting, direction, fixed geometry, receipt time, firmware, device path, raw packet, correction history, calculation version and calculated snapshot.
- Camera summaries group complete, included center readings by setting **and** curtain direction. They show mean duration, timing difference, sample standard deviation and contributing count. Partial readings retain their valid channels in the inspector but do not enter those summaries.
- Timing tolerance is an operator-selected comparison rule, not a camera health grade. The UI also identifies individual readings outside tolerance, so an in-range mean cannot conceal variation.
- Before/after comparisons match recorded settings and directions, disclose unmatched groups, and flag differences in recorded conditions, firmware and calculation versions.
- The existing auto-advance sequence runs from 1/15 to 1/1000, stops at its end, and does not advance for partial/invalid readings. Configurable coverage targets do not change that sequence into an automated repeat controller.
- Current full-frame estimates support only the documented 32 × 20 mm sensor rectangle and 36 × 24 mm frame. Other formats can be catalogued; entering a format does not change the measurement geometry.

## Tester support and documentation

| Tester | In this alpha | Official instructions |
| --- | --- | --- |
| Shutter Lover | `MultiSensorMeasure` USB reader. The user confirmed a successful physical connection in the preceding build; this camera-database update has not repeated that hardware check. | [English manual 1.1.0](https://photographyelectronics.com/wp-content/uploads/2025/06/ShutterLover_UserManual_en_1.1.0_-_Release.pdf), [interface specification](https://github.com/sebastienroy/shutter_lover_remote_app/wiki/Interface-Specifications) |
| Baby Shutter Tester mk II | Model-specific instructions only; this build does not decode its protocol. | [English manual 1.0.0-B, firmware 1.0.0](https://photographyelectronics.com/wp-content/uploads/2025/08/BabyShutterTester_mkII_UserManual_en_1.0.0_-B.pdf) |

The guide covers Shutter Lover calibration distance, orientation, physical mode-button transitions, alignment and reset. The Baby mk II guide distinguishes Automatic and Global modes, diffuser use, fixed illumination/aperture, effective-time readings and E₀ checks. Summaries link to the full manuals; PDFs are not redistributed. Sources were checked on 27 September 2026 against the [manufacturer documentation page](https://photographyelectronics.com/resources/documentation/).

## Storage, migration and verification

The sandboxed bundle saves under its Application Support directory inside `~/Library/Containers/com.shutterlover.mac/`. An unbundled `swift run` uses `~/Library/Application Support/ShutterLover/`. The Shutter Loved rename retains these paths, the bundle identifier, file extensions and exchange format identifiers so existing libraries and exports remain compatible. The hardware tester is still named Shutter Lover. Existing generated export evidence notes retain their original wording so re-exporting the same test revision does not create a content conflict in Armarium.

- **`library.json`** is the schema-2 camera library, including its persistent producer UUID, cameras and sessions. **`library.previous.json`** retains the previous saved snapshot.
- On first migration, the app reads schema-1 **`sessions.json`**, leaves it intact, and saves a byte-for-byte **`sessions.pre-camera-library.json`** backup before writing the new library. Existing session/reading identities and measurements are preserved, and sessions remain unassigned.
- **`photos/`** stores managed display photos and originals. **`imported-archives/`** retains imported full-camera archive bytes. Copy these alongside the JSON files when backing up the entire local database directory.
- Loads validate identity relationships, raw packets, calculation snapshots and managed filenames. Failed or corrupt loads are reported rather than silently replaced with an empty library. Writes are atomic.

```sh
swift test
```

Tests cover the measurement core, serial framing/lifecycle, session integrity, camera-library migration and relationships, capture/navigation separation, archive handling, calculations, provenance and interchange. See the latest verification output for the current results. The busy-port test skips on hosts whose pseudo-terminal driver does not enforce `TIOCEXCL`; it does not replace a hardware check.

Interchange has also been verified against Armarium's published JSON Schema and, in a separate temporary process, its actual public import/export APIs. Synthetic tests exercised both directions, duplicate imports, revisions, conflicting content and catalogue mismatch. That harness did not modify a user collection or introduce a runtime dependency.

## Remaining release work

- Repeat physical capture and reconnect qualification for this update, including USB hubs, sleep/wake and the macOS 14 baseline. Verify serial parameters and DTR/RTS/open behavior across firmware versions. The 9600/8N1 setting is inherited from the Python client's defaults; reconnection currently follows the selected path rather than a persistent hardware identity.
- Qualify photo drag/drop; add manual crop positioning/zoom and service-document attachments. Fit/fill photo presentation, text service records and before/after links are available now.
- Add configurable repeated sweep control, richer comparison visualisations and optional individual-reading PDF appendices. Current coverage targets and comparisons are informational.
- Implement Baby mk II acquisition separately; its instructional guide does not imply protocol support.
- Qualify large libraries and full-directory restore workflows. Storage uses versioned Codable JSON snapshots, not SwiftData, and importing a camera archive creates a copy rather than replacing the database.
- Public distribution requires Developer ID signing, notarization and installer qualification.
- Exclusion remains a flag without a reason field; deletion undo retains the most recent removed reading. Exact historical TSV preamble compatibility is not implemented.

The Python app remains available as a reference. The repository's GPL v3 license and original attribution are preserved.
