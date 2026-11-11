# Instructions for Claude in this repository

## Commit messages and PR titles

- Start every commit message and every PR title with an emoji for the change type, then a short imperative summary.
- ✨ feature; 🐛 bug fix; 🔧 tooling, refactoring, renames, scripts, CI; 📝 documentation.
- ⚡ performance and 🔥 removal are also allowed (already used in the history).
- A type word after the emoji (`feat:`, `fix:`, `docs:`, `refactor:`) is optional; the emoji is not.
- Choose by what the change does: a fix to documentation is 📝, a fix to code is 🐛.
- Never rewrite or force-push `main` to add emojis to old commits.
- The standard and its reasons: `README.org` (section "Commit and PR messages start with an emoji") and `adr/0026-emoji-prefix-for-commits-and-prs.org`.

## Branches and changelog

- Name PR branches with the PR number first, e.g. `18-relationship-annotator` (ADR 0004).
- Feature and fix PRs do not edit `CHANGELOG.org`; the nightly tidy does.
- Keep documentation as bullet lists, not long paragraphs.
