## Summary
<!-- Brief description of what this PR does -->

## Changes
<!-- List the main changes -->
-
-
-

## Type of Change
- [ ] `feat` — New feature
- [ ] `fix` — Bug fix
- [ ] `refactor` — Code refactoring
- [ ] `docs` — Documentation update
- [ ] `test` — Test additions/updates
- [ ] `chore` — Build/tooling changes

## Testing
- [ ] `swift test` passes
- [ ] Snapshot references updated if UI changed intentionally
- [ ] Manual testing performed (describe below)

**Manual testing notes:**
<!-- What did you test and how? -->

## Code Quality
- [ ] `swift build` succeeds with no warnings in changed files
- [ ] Zero-platform-import check passes for `StreamDownCore` changes
- [ ] Documentation comments added/updated for new public APIs
- [ ] Example apps (`StreamDownChat`, `StreamDownExample`) still compile

## StreamDownCore Changes
<!-- Complete if you modified Sources/StreamDownCore/ — otherwise delete -->
- [ ] No platform-specific imports added (`SwiftUI`, `UIKit`, `AppKit`, etc.)
- [ ] All new types are KMP-portable (primitives, enums, structs — no platform types)

## Screenshots / Recordings
<!-- Add screenshots or a screen recording for UI changes. Delete if not applicable. -->

## Related Issues
Closes #
Relates to #

## Breaking Changes
- [ ] This PR includes breaking changes
- [ ] Migration notes added to CHANGELOG or PR description

**Breaking changes:**
-

## Additional Context
<!-- Any decisions, trade-offs, or context reviewers should know -->

---

## Reviewer Checklist
- [ ] Code follows project standards (CLAUDE.md)
- [ ] `StreamDownCore` remains free of platform imports
- [ ] Tests are meaningful and pass
- [ ] Public API documentation is clear
- [ ] No scope creep or unasked-for changes
- [ ] Commit messages follow conventional commit format
- [ ] CI checks pass
