# Agent conventions — rails-markup

## Commits
- **No AI attribution in commits.** Never add `Co-Authored-By: Claude`, `Generated with Claude Code`, `Claude-Session`, or any AI disclaimer/footer to commit messages.
- Branch before committing on `main` only if asked; this repo's workflow commits to `main` directly and releases by tag.

## Repo
- Gem `rails-markup` (Rails engine + browser toolbar + MCP server + CLI). Published on RubyGems; repo `github.com/nauman/rails-markup`.
- Release: bump `lib/rails_markup/version.rb` + `CHANGELOG.md` → commit → `git push origin main` → `git tag vX.Y.Z && git push origin vX.Y.Z`. GitHub Actions (`release.yml`) runs tests, builds, and `gem push`.

## Tests
- `bundle exec rake test` — default suite (Chrome-free).
- `rake test:system` — Capybara + Cuprite browser tests (needs Chrome).
- `node --test test/javascript/*_test.mjs` — toolbar JS unit tests.

## Cross-agent coordination
- Shared thread: `../.agents/rails-markup/NOTES.md`.
