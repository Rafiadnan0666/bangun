# Release Checklist

## Pre-tag

- [ ] `flutter test --coverage` passes
- [ ] Evidence committed (`evidence/` tree)
- [ ] Paper numbers synced with repo
- [ ] CHANGELOG updated
- [ ] README updated with current numbers

## Tag & Publish

- [ ] `git tag vX.Y.Z`
- [ ] `git push origin vX.Y.Z`
- [ ] GitHub release created
- [ ] APK signed with release keystore
