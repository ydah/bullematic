# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

- Preserve detections across complete RSpec and Minitest runs and deduplicate them safely.
- Remove the incompatible Bullet notification constructor hook.
- Reject ambiguous query locations and support namespaced model constants.
- Rewrite source by byte offset, validate generated Ruby, detect stale source, and write atomically.
- Preserve complex eager-loading arguments and generate verified nested association trees.
- Default to dry-run planning with automatic fixes disabled and backups enabled.
- Add persistent recording and explicit `record`, `plan`, `apply`, `verify`, `fix`, and `doctor` commands.
- Emit accurate dry-run hunks and reject evidence when its source snapshot has changed.
- Preserve child command flags, verify only N+1 evidence, and reject read-only or symlinked write targets.
- Reject snapshot-less or newly excluded evidence and require structural proof before merging nested associations.

## [0.1.0] - 2026-01-13

- Initial release
