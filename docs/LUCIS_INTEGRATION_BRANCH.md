# Keeping the Lucis integration branch current

`lucis-integration` was created from main commit `9803ffd` before the integration UI was hidden. Its history preserves the original working integration. Main retains the exchange implementation, tests, archive compatibility and existing catalogue metadata, but hides Armarium import/export controls. **File → Import Camera Catalogue…** is present and disabled.

The only intentional code difference between the maintained branches is `macos/Sources/ShutterLover/LucisIntegration.swift`: `isEnabled` is `false` on main and `true` on lucis-integration. The initial UI change is merged into lucis-integration before its flag is enabled. This common ancestry allows later ordinary merges to retain the enabled flag without undoing new fixes.

**Sync lucis-integration** runs in GitHub Actions after each push to main. It fetches the latest main, merges it into the existing integration branch, checks that integration remains enabled, runs the Swift tests, and pushes normally. Concurrent sync runs are serialised. The workflow can also be run manually from main in the Actions tab.

A merge conflict, failed test, missing branch, disabled integration flag or rejected push stops the sync without updating the remote integration branch. The Actions run records the failure. Resolve conflicts on lucis-integration while keeping its flag enabled, run the tests, push that resolution and rerun the workflow. Do not use a force push or an `ours` merge strategy to hide conflicts. GitHub Actions must remain enabled and permitted to write repository contents.

When ready to reintegrate, open a pull request from lucis-integration to main. Its enabled flag restores the Armarium controls. Remove the sync workflow once the branch is no longer needed. Stored camera catalogue identities and historical exports are retained throughout.

## Initial validation — 30 September 2026

- Swift tests passed on both branches: 155 passed, one existing host-dependent serial-port test skipped, no failures.
- Main's Apple Silicon release build is version 0.3.4 (build 10). Native UI inspection confirmed the disabled **Import Camera Catalogue…** File command and the removed Armarium buttons. The saved library was unchanged after launch.
- Isolated Git fixtures verified successful merging, repeated no-op runs, conflict recovery, missing-branch handling, rejection of a disabled integration flag, and rejection of a concurrent remote update without overwriting it.
- The [initial GitHub Actions run](https://github.com/sebiimaks/Shutter-Loved/actions/runs/36721485650) passed with the integration branch already containing main. The subsequent full merge run stopped before pushing when Xcode 16.4 could not type-check a large existing CSV expression; splitting that expression into typed field groups preserves the export format and allows the older compiler to check it. See the [workflow run history](https://github.com/sebiimaks/Shutter-Loved/actions/workflows/sync-lucis-integration.yml) for ongoing merge, test and push results.
