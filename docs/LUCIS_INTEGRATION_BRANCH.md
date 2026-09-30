# Keeping the Lucis integration branch current

`lucis-integration` was created from main commit `9803ffd` before the integration UI was hidden. Its history preserves the original working integration. Main retains the exchange implementation, tests, archive compatibility and existing catalogue metadata, but hides Armarium import/export controls. **File → Import Camera Catalogue…** is present and disabled.

The only intentional code difference between the maintained branches is `macos/Sources/ShutterLover/LucisIntegration.swift`: `isEnabled` is `false` on main and `true` on lucis-integration. The initial UI change is merged into lucis-integration before its flag is enabled. This common ancestry allows later ordinary merges to retain the enabled flag without undoing new fixes.

**Sync lucis-integration** runs in GitHub Actions after each push to main. It fetches the latest main, merges it into the existing integration branch, checks that integration remains enabled, runs the Swift tests, and pushes normally. Concurrent sync runs are serialised. The workflow can also be run manually from main in the Actions tab.

A merge conflict, failed test, missing branch, disabled integration flag or rejected push stops the sync without updating the remote integration branch. The Actions run records the failure. Resolve conflicts on lucis-integration while keeping its flag enabled, run the tests, push that resolution and rerun the workflow. Do not use a force push or an `ours` merge strategy to hide conflicts. GitHub Actions must remain enabled and permitted to write repository contents.

When ready to reintegrate, open a pull request from lucis-integration to main. Its enabled flag restores the Armarium controls. Remove the sync workflow once the branch is no longer needed. Stored camera catalogue identities and historical exports are retained throughout.
