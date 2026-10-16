# Manual checks

Everything the cycle engine does is covered by `swift test`. Everything below
depends on the window server, the menu bar or a real human holding a key, and
has no honest unit test — so it is checked by hand.

Run `./build.sh && open EyeProtector.app`. Set Session to 1 min and Break to
10 s in settings first, so a full cycle takes about a minute.

## Lockout

Last verified: macOS 27.0.1, 2026-10-16.

With the Overlay up, none of these may reach another application:

- [ ] Three-finger swipe between Spaces — the Space change is *allowed* to
      happen; the Overlay must be there on arrival (see ADR 0003)
- [ ] Mission Control (F3, or four-finger swipe up)
- [ ] Cmd-Tab
- [ ] Clicking a second Display — it must be covered too
- [ ] Cmd-Q
- [ ] Clicking where the Dock would be
- [ ] A fullscreen app running behind the Overlay stays behind it

Force Quit (Cmd-Opt-Esc) **must** still work, and so must log out, restart and
shut down. All three are deliberate — ADR 0004.

- [ ] Another app stealing focus during a Break does not end Lockout: the
      Overlay takes activation back

## The cycle

- [ ] Launching shows the Overlay with Start live
- [ ] Start hides the Overlay and restores the Dock and menu bar
- [ ] The menu bar shows a counting-down timer during the Session
- [ ] The Warning appears top-right on every Display before the Break
- [ ] The Break arrives on time and covers every Display
- [ ] The Break ends into Idle with the Overlay still up and Start live
- [ ] Today's counts in settings go up as expected

## Escape

- [ ] Holding Esc during a Break fills the progress bar
- [ ] Releasing early resets it to empty
- [ ] A completed hold starts a new Session immediately
- [ ] The skipped count goes up by one
- [ ] Esc does nothing while Idle

## Sleep and lock

- [ ] Lock the screen mid-Session, wait, unlock: the remaining time is
      unchanged, not advanced
- [ ] Close the lid mid-Break, reopen: the Break resumes rather than having
      expired
- [ ] Leave the machine untouched but awake past the display-sleep timeout:
      the Session clock must keep running. Display sleep is *not* the user
      going away

## Displays

- [ ] Plug in a Display during a Break: it gets covered within a moment
- [ ] Unplug one during a Break: the rest stay covered, nothing crashes
- [ ] Swap one Display for a different one without changing the count: the
      Overlay must re-cover the new arrangement, not sit on stale frames

## Settings

- [ ] Changing the Session length mid-Session takes effect immediately
- [ ] Settings are reachable from the Overlay gear while Idle
- [ ] Settings are reachable from the menu bar during a Session
- [ ] Values survive a quit and relaunch
- [ ] Launch at login: toggle on, reboot, confirm the Overlay appears. If the
      toggle refuses and shows an error, that is the ad-hoc signing limitation
      in ADR 0001 — fall back to a LaunchAgent plist

## Safety nets

- [ ] With the dead-man's switch temporarily shortened, a Break that never
      ends still returns to Idle and Start becomes clickable

### The main-thread watchdog

This is the only safeguard that survives the main thread failing, and its only
action is ending the process, so it cannot be unit-tested. `StallPolicy`
covers the decision; this covers the act.

```
EYE_PROTECTOR_WEDGE_AFTER=3 ./EyeProtector.app/Contents/MacOS/EyeProtectorApp
```

The Overlay appears and Lockout engages, the main thread hangs on purpose
after 3 s, and about 10 s later the process should die on its own — printing
to stderr as it goes — and hand the Dock and menu bar back. Expect roughly 13
seconds of a black, genuinely frozen screen: the Start button will not respond
during it, which is the whole point.

- [ ] The process exits by itself and the desktop comes back
- [ ] Without the env var set, normal use never triggers it
