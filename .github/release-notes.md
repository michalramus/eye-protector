Two DMGs: `EyeProtector-*.dmg` (break reminder) and `Curfew-*.dmg` (night and
weekend shield, see [docs/curfew.md](docs/curfew.md) before installing).

Ad-hoc signed and **not notarised**, so Gatekeeper refuses them on first launch.
Right-click the app and choose Open, or clear the quarantine flag:

```
xattr -dr com.apple.quarantine "/Applications/Eye Protector.app"
xattr -dr com.apple.quarantine /Applications/Curfew.app
```

Apple Silicon only — `x86_64` is deprecated for this deployment target.
