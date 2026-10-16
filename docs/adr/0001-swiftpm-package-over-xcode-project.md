# SwiftPM package assembled into an .app, not an Xcode project

Eye Protector needs a real application bundle — Lockout, `LSUIElement` and
launch-at-login all require one — but an `.xcodeproj` is effectively opaque to
diff and to edit outside Xcode, which makes every build-setting change a hunt
through generated XML. We keep the whole project as a SwiftPM package and
assemble the bundle with a short `build.sh` that copies the binary, drops in a
hand-written `Info.plist` and ad-hoc signs the result.

## Consequences

Everything about the build is plain text and reviewable, and the pure logic is
testable with `swift test` and no Xcode involvement. The costs: no Interface
Builder, no Xcode scheme for one-key run-and-debug, and an ad-hoc signature
rather than a Developer ID one. Ad-hoc signing is the known risk for
`SMAppService` login-item registration — if it refuses the signature, the
fallback is a `~/Library/LaunchAgents` plist, which needs no signing at all.
