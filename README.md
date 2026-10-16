# Eye Protector

A break reminder for macOS that you cannot wave away by reflex.

During a break it covers **every** display, sits above fullscreen apps, and is
present on every Space — so swiping to another desktop lands you back on it.
Cmd-Tab, Mission Control, the Dock and the menu bar are all disabled while it
is up. Skipping a break is possible, but it takes a deliberate three-second
key hold, and it is counted and shown back to you.

## How it works

```
Idle ──click Start──▶ Session (30 min) ──warning at 30s──▶ Break (30s) ──▶ Idle
       ▲                                                                    │
       └────────────────────────────────────────────────────────────────────┘
```

The overlay is up while Idle as well as during a break: the two differ only in
whether the Start button is live. Starting a session is always one click away,
so this is a gate, not a cage.

The session clock pauses when the machine sleeps or the screen locks. It does
**not** pause when you simply stop typing — watching a video is still screen
time.

## Install

Grab the DMG from [Releases](../../releases). It is ad-hoc signed and not
notarised, so Gatekeeper will refuse it on first launch: right-click the app
and choose Open, or run

```
xattr -dr com.apple.quarantine /Applications/EyeProtector.app
```

Apple Silicon only.

## Build from source

```
./build.sh release          # assembles EyeProtector.app
./Scripts/make-dmg.sh 1.0   # packages it into dist/
swift test                  # runs the cycle engine tests
```

Needs Xcode 26 or newer. There is no `.xcodeproj` — see
[ADR 0001](docs/adr/0001-swiftpm-package-over-xcode-project.md) for why.

## Settings

Session length, break length, the pre-break warning and launch-at-login, from
the menu bar during a session or the gear on the overlay while idle. Session
1–180 min, break 5–600 s.

## It cannot trap you

An app that deliberately locks your screen has to be honest about its failure
modes, so there are three independent ways out that do not depend on this
code being correct:

- Force Quit stays enabled, as do log out, restart and shut down.
- A dead-man's switch returns you to Idle within a minute of a break's due
  end, however confused the state machine gets.
- A watchdog on its own thread ends the process outright if the main thread
  stops responding while the screen is locked out.

See [ADR 0004](docs/adr/0004-force-quit-stays-enabled.md).

## Layout

| Path | What |
| --- | --- |
| `Sources/EyeProtectorCore` | The cycle as a pure, clock-free value type. All the tests point here. |
| `Sources/EyeProtectorApp` | AppKit adapter: windows, lockout, menu bar, settings. |
| `CONTEXT.md` | Glossary. Session, Break, Space, Lockout and friends mean specific things. |
| `docs/spec.md` | What was asked for, as user stories. |
| `docs/adr/` | Decisions that would otherwise look arbitrary. |
| `docs/manual-checks.md` | The things no unit test can honestly cover. |
