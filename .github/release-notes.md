Ad-hoc signed and **not notarised**, so Gatekeeper refuses it on first launch.
Right-click the app and choose Open, or clear the quarantine flag:

```
xattr -dr com.apple.quarantine /Applications/EyeProtector.app
```

Apple Silicon only — `x86_64` is deprecated for this deployment target.
