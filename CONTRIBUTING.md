# Contributing

## Canonical State

The canonical state is the latest tag (`vX.Y.Z`). Commits before the latest tag are a stale snapshot and unsupported.

## Process

1. `git pull --rebase` before working
2. Run `flutter test --coverage` before committing
3. Commit evidence for any changed behavior
4. Update CHANGELOG with version bump
5. Tag release (`git tag v1.1.0 && git push origin v1.1.0`)

## Style

- Follow existing code style
- No new dependencies without justification
- Test first, code second
