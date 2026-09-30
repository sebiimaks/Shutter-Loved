# Armarium Lucis interchange in Shutter Loved

Shutter Loved independently implements **Shutter Tester JSON, version 1**, identified by `org.armarium-lucis.shutter-tester`. This is an application interchange format, not an industry standard. The implementation is based on Armarium Lucis's public documentation, JSON Schema and synthetic examples. No Armarium application source or camera measurements were copied.

## Camera catalogues into Shutter Loved

1. In Armarium Lucis, select the physical cameras and export **Shutter Tester** camera profiles. Include serial numbers only if desired.
2. In Shutter Loved, import the camera catalogue JSON. Review every row before applying.
3. New identities create separate camera records. Newer profile revisions update catalogue identity/specification fields while preserving the local camera UUID, photos, acquisition details, notes, services and test history. If serial was omitted, the imported serial field is empty.
4. Start a new test from that camera record. The run captures the original catalogue UUID and camera UUID alongside its display identity. Changing camera details later does not rewrite that captured identity.

Matching uses **catalogue UUID + camera UUID**, never name, model or serial. Two catalogues can contain cameras with the same UUID without referring to the same physical item. Imported source profiles are retained in full as canonical JSON, including descriptors without a dedicated editor field. Every accepted revision is retained.

Review is read-only. An identical previously imported revision is a no-op; an unknown older revision is skipped. The same revision with different content is a conflict and blocks the whole batch. Apply reparses the same original bytes and checks relevant camera state again; intervening edits require a new review. The application then saves the complete candidate library atomically.

Catalogue-owned fields updated by a new revision are name, manufacturer, model, serial, inventory ID, mount, format, shutter architecture and the suggested curtain direction. This can replace local edits to those fields; the review explains the update before application. Other local fields are preserved. Camera/shutter specification text is descriptive; only an exact supported horizontal/vertical direction becomes a suggested setup value.

## Results back to Armarium Lucis

Export **Armarium JSON** from an individual real camera test. Import the result in the original Armarium collection and use Armarium's review before applying.

- The producer database UUID remains stable. Each test uses its existing session UUID and revision; correcting a run increments its revision, while a genuinely new run receives a new UUID.
- Results target the catalogue/camera identity captured when that test began. An unlinked test must first be explicitly assigned by the operator to an imported camera, or a new test started from that camera. Retrospective assignment is recorded with its timestamp and the original camera name in exported provenance notes; it is never inferred by name or serial.
- Each included, complete **Shutter Lover USB reading** contributes three exposure durations and, when positive, two calibrated outer-sensor curtain travel intervals. Every value and nominal duration is numeric **seconds**, with `unit: "s"`.
- Each included, valid **Baby Shutter Tester Mk I or Mk II manual reading** contributes one `exposureDuration` in numeric seconds. Its sensor position is unknown, so `position`, corner exposures and curtain travel are omitted. Version 1 has no separate effective-exposure quantity: per-sample notes identify Mk II values as **effective exposure** and Mk I values as **measured exposure**, preserving the distinction and the fact that the display was manually transcribed.
- Exposure nominal values are `1 / nominalDenominator`. An 8.2 ms duration is `0.0082` seconds. Reciprocal speeds, percentages and exposure errors are not exported as durations.
- Shutter Lover USB curtain intervals span the documented 32 × 20 mm sensor rectangle. Full-frame extrapolations are estimates and are **not** exported as measured travel.
- The original one-based reading position is `sampleIndex`; gaps therefore remain when readings are excluded. Run notes map exported sample numbers to immutable local reading UUIDs, capture times and curtain directions. Reading order is preserved.
- Tester details use the existing v1 `tester` fields for manufacturer, model, serial and firmware when applicable and consistent across included readings. Per-sample notes retain each reading's captured tester identity, owned-tester UUID and USB identity where recorded; manual notes also retain the original value and unit, mode, supplied illumination values and entry notes. Selecting or editing a tester later does not relabel earlier readings. No new fields or capabilities are added to the v1 contract.
- Partial, invalid and excluded readings are omitted with a count and explanation. Zero/unavailable curtain intervals are omitted and counted. Demonstration sessions or mixed simulated/device records are blocked entirely. A run with no qualifying measurements is blocked.
- Version 1 permits 512 structured quantities per test. A typical complete three-sensor Shutter Lover USB reading contributes five quantities, so 102 such readings fit; a Baby manual reading contributes one. The separate 16 KiB notes limit may be reached sooner. Larger exports fail visibly; they are never silently truncated or assigned artificial run identities.
- Light source and test conditions are included when supplied. Test notes are included; private camera acquisition details, photos, service history and raw packets are not part of the exchange.

The JSON format cannot represent the full Shutter Loved evidence model. Use **Full camera archive** to retain raw packets where present, original manual entries, tester snapshots, calibration, invalid/partial/excluded readings, correction history, calculation snapshots and camera media. An Armarium JSON file is a deliberately narrower interchange record, not a Shutter Loved backup.

## Defensive parsing

Import and result validation reject unsupported fields, explicit null, duplicate keys (including escaped equivalents), unknown versions/capabilities, invalid UUIDs/dates, numeric booleans, incorrect units, nonfinite/out-of-range numbers and malformed JSON. Limits are 8 MiB per file, 32 levels of nesting, 64 KiB UTF-8 per string, 256 object fields and 10,000 array elements, with tighter schema-specific limits (1,000 cameras/runs, 512 measurements/run, 512-byte titles and 16 KiB run notes). RFC 3339 dates require a real calendar date, explicit timezone and seconds 00–59.

## Verification and provenance

`macos/Tests/ShutterLoverTests/ShutterTesterExchangeTests.swift` exercises the independent public fixtures, catalogue namespace and revision handling, duplicate/stale/conflict review, intervening-edit checks, parser boundaries, identity-preserving export, numeric seconds, omitted evidence, result limits and rejection of simulated data.

`macos/Tests/ShutterLoverTests/TesterResultsTests.swift` covers Baby Mk I and Mk II manual exports, conversion to numeric seconds, omitted sensor/travel quantities, tester and manual-entry provenance, mixed tester metadata, preservation of legacy USB export evidence, and manual-entry archive round trips. These local tests do not constitute a fresh receiving-process check in Armarium Lucis for Baby readings; the external verification below records the earlier Shutter Lover USB implementation.

Public contract references are copied under `docs/fixtures/shutter-tester-v1/` for reproducible tests:

- `camera-catalog-v1.json`: Armarium's independent synthetic catalogue example.
- `test-results-v1.json`: Armarium's independent invented-results example.
- `shutter-tester-v1.schema.json`: the documented public v1 schema.

These fixtures contain no real measurements or customer data. They are sourced from the sibling Armarium Lucis project's `Documentation/examples/` and `Documentation/schema/` as supplied on 27 September 2026. The compatibility code uses Apple Foundation and Shutter Loved's own evidence model only.

On 27 September 2026, the actual Shutter Loved exporter output also passed independent Draft 2020-12 JSON Schema validation (with UUID/date format checking) and an isolated receiving-process check against ArmariumCore's public `reviewResults` / `applying` API. The receiving application accepted the new test, preserved original archive bytes and measured seconds, treated a duplicate as a no-op, retained earlier evidence on a revision update, and blocked both conflicting same-revision content and an unrelated collection. The harness used only a synthetic in-memory Armarium collection and temporary build files; it did not edit Armarium source or a user collection. The reverse direction was also exercised: a catalogue generated by ArmariumCore’s real `exportCameras` API was accepted by Shutter Loved and a second import was recognized as a duplicate. ArmariumCore is not a Shutter Loved runtime or build dependency.

For a repeatable exported synthetic artifact, set `SHUTTER_TESTER_INTEROP_OUTPUT` to an absolute temporary `.json` path when running `ShutterTesterExchangeTests.testResultsExportPreservesIDsRevisionSecondsAndReadingProvenance`. The test uses invented measurements and public fixture identities. The resulting file can be validated with any Draft 2020-12 JSON Schema validator against the schema above. `SHUTTER_TESTER_CATALOGUE_INPUT` optionally supplies an actual externally exported catalogue to `testPublicSyntheticFixturesAreAcceptedWithoutNameMatching` for reverse-direction import and duplicate checks.
