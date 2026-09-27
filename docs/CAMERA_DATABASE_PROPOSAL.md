# Camera database design and implementation status

Status: **UI proposal approved; the first implementation is included in the 0.2.0 alpha.** The user approved proceeding on 27 September 2026, with Armarium Lucis import/export compatibility added to the scope. This document records the implemented subset and remaining design follow-ups. The earlier interactive proposal remains an illustrative mockup, not the running application.

## Navigation and identity — implemented

One record represents one physical camera, with many dated tests and service events. Bodies of the same model remain separate. The sidebar searches make, model, display name/nickname, serial number, collection ID and tags. Existing sessions remain in **Unassigned tests** until explicitly linked; demo records remain distinct from device evidence.

The camera header contains an optional 3:2 landscape photograph, display identity, serial, collection ID and last-tested date, with New test, Edit camera and Export actions. **Connect tester** retains a visible text label.

The photo picker stores the original and a bounded display image in the local library. **Crop to fill** and **Fit entire photo** keep the 3:2 frame. Manual crop positioning and zoom are future follow-ups. A file-URL drag/drop handler is implemented, but its native interaction still needs smoke testing; the verified selection path is the photo picker.

## Camera page — implemented

| Section | Current behavior |
| --- | --- |
| Results | Explicitly selected test, chosen timing tolerance, speed/repeat coverage, included/excluded/incomplete counts, setting/direction summaries, individual-reading inspection and captured identity |
| Test history | Dated tests, titles, counts, results navigation, service milestones and explicit two-test comparison |
| Camera details | Identity, camera/shutter/lens metadata, default test settings, condition, optional acquisition/storage fields and external catalogue identity |
| Service & notes | Dated service entries, provider, work/notes, links to before/after tests and persistent camera notes; document attachments remain a follow-up |

Results default to the latest test and never blend different test dates or service events implicitly. Center-exposure summaries use complete, included readings grouped by shutter setting and curtain direction. Each group shows mean exposure, timing difference, sample SD and contributing count. Partial and excluded records remain inspectable. An in-range mean is accompanied by the count of individual readings outside tolerance.

The default ±⅓-stop tolerance is configurable operator metadata, not a manufacturer specification or overall camera grade. Untested speeds receive no grade; repeat targets describe coverage. The existing auto-advance sequence remains separate from these targets and does not automatically repeat or release the camera shutter.

Comparisons match settings and recorded curtain directions across two explicitly selected tests. They show means, sample counts, SD, differences and unmatched-group counts, with warnings for differing lighting/conditions, firmware, calculation versions and date order. The current comparison uses a table rather than a chart.

## Fields — implemented subset

Only the camera display name is required. Unknown values stay blank.

| Group | Available fields |
| --- | --- |
| Identity | Local UUID, make/model, display name, nickname, body serial, collection ID, tags, created/updated dates |
| Photograph | Managed original/display photo and fit/fill preference |
| Camera/shutter | Format, frame dimensions, shutter type, default curtain direction, planned speeds, production year, mount, lens name and serial |
| Condition | Free-text observations and camera notes; separate structured meter/light-seal checklists are not implemented |
| Ownership, optional | Acquisition date/source, purchase price/currency, storage location and archived flag |
| Test | Stable UUID, camera link and identity snapshot, title, dates, operator, lighting, conditions, planned speeds, repeat target, saved tolerance and notes; firmware/device/calibration provenance remains with readings |
| Service event | Date, title, provider, work/notes and optional before/after test links |
| Armarium link | Original catalogue UUID, camera UUID, imported revision and retained source profile snapshots |

Lens/aperture details specific to a test can be recorded in its conditions or notes; there are no separate per-test lens/aperture controls. Catalogue metadata is descriptive, not a verified specification database. Other camera formats can be catalogued, but the measurement engine's 32 × 20 mm sensor / 36 × 24 mm full-frame geometry remains explicit and unchanged.

## Reports and interchange — implemented

- A printable PDF summarises the selected test with its 3:2 photo, identity, date, conditions, chosen tolerance, planned settings, results, sample counts and notes. Optional individual-reading appendices remain future work.
- CSV/TSV exports retain measurement columns for analysis.
- A full `.shuttercamera` archive includes the camera, managed original/display photo, linked tests, services, raw readings, corrections and calculation snapshots. Import is explicitly **as a separate copy**, with new local IDs, no Armarium link and retained original archive bytes.
- Legacy `.shutterlover` session files remain importable as unassigned copies and exportable separately.
- [Shutter Tester JSON v1](SHUTTER_TESTER_JSON.md) imports Armarium camera catalogues through a read-only review and exports supported timing evidence back to the original catalogue. UUIDs and revisions preserve identity; name/serial matching is never used. The 512-quantity limit, omissions and supported units are explicit. Actual independent interoperability checks cover both application directions.

## Storage and capture safeguards — implemented

- Schema-2 `library.json` has a persistent producer/library UUID. Migration preserves `sessions.json`, creates `sessions.pre-camera-library.json`, retains existing reading/session IDs, and leaves historical sessions unassigned. `library.previous.json` retains the previous saved library snapshot.
- Assignment requires the operator's explicit camera choice and confirmation. Retrospective assignment retains the original camera name and records when the association was made; exported provenance states that context.
- New tests snapshot their camera identity. Later metadata edits or catalogue refreshes do not rewrite existing tests. Each reading keeps its recorded setup and a validated calculation snapshot.
- Active capture is independent of navigation. A persistent **Recording to…** indicator and **Return to live test** identify its destination. Starting a new camera test or choosing **Record into this test** is an explicit destination change.
- Demo data remains separate. Raw-packet validation, atomic saves, failed-load protection, correction history and one-level reading-deletion undo remain in place.

## Follow-ups and verification boundaries

Manual crop positioning/zoom and service-document attachments are future work. Native drag/drop qualification remains outstanding despite the existing handler. Richer comparison charts, optional PDF reading appendices, structured condition checklists and automated repeat sequencing are also outside this first implementation.

The UI proposal's field list and interactions were broader than this subset; the app contains working actions for the implemented features rather than placeholder controls for these follow-ups. Use [macos/README.md](../macos/README.md) for current build, storage, export and testing instructions.

Automated checks cover migration, legacy import, identity, archive integrity, capture destination, calculation/sample-count semantics and exchange validation. Native smoke/media verification is tracked with the current build results. A physical Shutter Lover connection succeeded in the preceding version according to the user's confirmation; this camera-database update has not repeated hardware, sleep/wake or minimum-OS qualification. The build remains locally signed and unnotarized.
