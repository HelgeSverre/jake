# Changelog Entry Generation Prompt

Generate a changelog entry from these git commits.

Format: Keep a Changelog (https://keepachangelog.com/)

Categories to use:
- Added - new features
- Changed - changes in existing functionality
- Deprecated - soon-to-be removed features
- Removed - removed features
- Fixed - bug fixes
- Security - vulnerability fixes

Rules:
- Be concise (one line per change)
- Group related commits
- Use imperative mood ("Add" not "Added")
- Include PR/issue numbers if present in commits
- Focus on user-visible changes, skip internal refactoring unless significant

Example output:

### Added
- Add shell completion for fish shell
- Add `--json` flag for machine-readable output

### Changed
- Improve error messages with source context

### Fixed
- Fix race condition in parallel execution

Output only the changelog section content (the categories and items), no version headers.
