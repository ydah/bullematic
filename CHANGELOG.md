# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] - 2026-08-29

### Added

- Add a `bullematic` executable with explicit `record`, `plan`, `apply`, `verify`, `fix`, and `doctor` commands. Recorded evidence and commands persist across processes, and verification reruns the recorded command to confirm that N+1 warnings are gone.
- Support high-confidence fixes for direct Active Record queries assigned to local variables, namespaced models, and structurally verified nested associations.

### Changed

- Disable source writes by default: automatic fixing is off, dry-run planning is on, and backups are enabled. Ambiguous, dynamic, or unverifiable query origins and associations are skipped instead of guessed.
- Record detections without retaining or applying them during normal Rails requests; source changes now require an explicit command or configuration.
- Support Bullet 6.x through 8.x and report installed dependency compatibility through `bullematic doctor`.

### Fixed

- Preserve and deduplicate detections across complete RSpec and Minitest runs, and capture Rails notifications before Bullet clears them.
- Preserve existing eager-loading arguments, multibyte and legacy source encodings, and line endings while rejecting generated Ruby with invalid syntax.
- Reject stale, missing, read-only, symlinked, or newly excluded sources and unsafe backup paths, and replace files atomically on Unix and Windows without changing their permissions.

## [0.1.0] - 2026-01-13

- Initial release
