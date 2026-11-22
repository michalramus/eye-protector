# Manual checks

Everything the cycle engine does is covered by `swift test`. Everything below
depends on the window server, the menu bar or a real human holding a key, and
has no honest unit test — so it is checked by hand.

Run `./build.sh && open "Eye Protector.app"`. Set Session to 1 min and Break to
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
- [ ] One cursor, not two: hover a link in a browser so the pointer is a
      pointing hand, then wait for the Overlay. Pass: exactly one cursor is
      visible when it appears, and it moves with the mouse; over the retype
      field it is the text cursor, elsewhere the arrow

## The cycle

- [ ] Launching shows the Overlay with Start live
- [ ] Start hides the Overlay and restores the Dock and menu bar
- [ ] The menu bar shows a counting-down timer during the Session
- [ ] The Warning appears top-right on every Display before the Break
- [ ] The Break arrives on time and covers every Display
- [ ] The Break ends into Idle with the Overlay still up and Start live
- [ ] Today's counts in settings go up as expected

## Skipping a Break

- [ ] "Skip this break" shows a hundred-character challenge
- [ ] Typing a wrong character does nothing at all — it does not appear
- [ ] Correct characters dim in the displayed string as you go
- [ ] Cmd-V does not fill the field, with the string on the clipboard
- [ ] Dragging selected text onto the field does nothing
- [ ] The displayed string cannot be selected with the mouse
- [ ] Cmd-A in the field does nothing
- [ ] Completing it starts a new Session immediately
- [ ] The skipped count goes up by one
- [ ] Cancel returns to the Break with the timer still running
- [ ] If the Break ends while you are typing, the challenge disappears rather
      than letting you finish for nothing

## Quitting

- [ ] Quit on the Overlay shows the same challenge
- [ ] Quit in the menu bar popover shows it too
- [ ] Clicking outside the popover mid-challenge does not close it
- [ ] Completing it quits the app
- [ ] Force Quit still bypasses the whole thing, as designed

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
EYE_PROTECTOR_WEDGE_AFTER=3 "./Eye Protector.app/Contents/MacOS/EyeProtectorApp"
```

The Overlay appears and Lockout engages, the main thread hangs on purpose
after 3 s, and about 10 s later the process should die on its own — printing
to stderr as it goes — and hand the Dock and menu bar back. Expect roughly 13
seconds of a black, genuinely frozen screen: the Start button will not respond
during it, which is the whole point.

- [ ] The process exits by itself and the desktop comes back
- [ ] Without the env var set, normal use never triggers it

## Curfew

**These need a real install, and an installed Curfew blocks the screen.** Run
them only on a machine you are willing to have blocked, with another way in
ready (see "Ways out" in [curfew.md](curfew.md)). Nothing here is safe to try
on a machine you need.

Setup: `./build-curfew.sh release`, copy `Curfew.app` to `/Applications`, then
`sudo /Applications/Curfew.app/Contents/MacOS/Curfew --install`. Shorthand
below: `curfew` is that binary. To avoid waiting for 20:00, edit the config with
`sudo` and set `nightStart` a couple of minutes ahead of now (the daemon
reloads within a second), and `nightGrace` to 120 so a full cycle is quick.
Set it back afterwards.

- [ ] The shield appears when the night window opens: wait for `nightStart`.
      Pass: every display is covered within a few seconds of that minute, and
      `curfew --status` says `shield: up`
- [ ] Typing the string buys the configured time: type the challenge in full.
      Pass: the shield drops, `--status` shows `shield: down` and
      `unlocks:` one higher, and it comes back after `nightGrace` (with the
      warning shown `warningLead` before). Wrong keystrokes do nothing and the
      field rejects paste
- [ ] The field stays put while typing: type most of the string. Pass: the box
      neither grows over the string above it nor hides what you have just
      typed, and the tail being typed is always in view
- [ ] Killing the agent keeps the grace: while unlocked, run
      `pkill -f 'Curfew --agent'`. Pass: within a few seconds the agent is
      running again (`pgrep -f 'Curfew --agent'`), the shield is still down,
      and `--status` shows the same unlock time rather than a fresh one
- [ ] The daemon restores a booted-out agent: run
      `launchctl bootout gui/$UID/com.michalramus.curfew.agent`. Pass:
      `launchctl list | grep curfew.agent` shows the job again within ten
      seconds, with no password asked
- [ ] Deleting the state file while unlocked brings the shield back:
      `sudo rm "/Library/Application Support/Curfew/state.json"`. Pass: the
      shield returns within a few seconds and the grace is gone
- [ ] Rebooting inside the night window lands on a shield: reboot with the
      window open and log in. Pass: the shield is up at login, with no moment
      of a usable desktop beyond the login screen itself
- [ ] `--uninstall` leaves no jobs behind: run
      `sudo /Applications/Curfew.app/Contents/MacOS/Curfew --uninstall`. Pass:
      `launchctl list | grep curfew` prints nothing, `sudo launchctl list |
      grep curfew` prints nothing, both plists are gone from
      `/Library/LaunchDaemons` and `/Library/LaunchAgents`, and the shield
      has gone
- [ ] Both shields at once: with Eye Protector's overlay up, let Curfew's
      shield come up. Pass: Curfew stays on top and focused, Eye Protector's
      overlay is covered, and there is no flicker or focus ping-pong
