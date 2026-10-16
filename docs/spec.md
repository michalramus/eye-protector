# Eye Protector

## Problem Statement

Working at a computer for hours without looking away damages your eyes. Every
reminder the user has tried is trivially ignorable: a notification is dismissed
without reading it, a timer app is switched away from, and a full-screen
reminder is escaped by swiping to another Space or glancing at a second
Display. The user wants a break reminder that cannot be ignored by reflex — one
that has to be dealt with deliberately rather than waved away.

## Solution

An app that covers every Display with an Overlay during the rest period and
genuinely prevents reaching any other application while it is up. The user
starts a Session deliberately, works uninterrupted for a configurable stretch,
is warned shortly before the end, and is then held in a Break for a
configurable rest. Skipping is possible but must be deliberate — a held key,
counted and shown back — rather than a reflex.

## User Stories

1. As a user with sore eyes, I want a full-screen Overlay during my break, so
   that I cannot carry on reading without noticing.
2. As a user, I want the Overlay on every Display, so that I cannot simply look
   at my other monitor.
3. As a user, I want the Overlay present on every Space, so that swiping to
   another desktop does not escape it.
4. As a user who works in fullscreen apps, I want the Overlay above them, so
   that fullscreen is not a way out.
5. As a user, I want Cmd-Tab, Mission Control, the Dock and the menu bar
   disabled during a Break, so that reflexes cannot defeat the break.
6. As a user, I want to start each Session by pressing a button, so that the
   app never starts timing me without my say-so.
7. As a user, I want a 30 minute Session by default, so that it works sensibly
   with no setup.
8. As a user, I want a 30 second Break by default, so that the rest is long
   enough to matter and short enough to tolerate.
9. As a user, I want to configure the Session length, so that it fits how I
   actually work.
10. As a user, I want to configure the Break length, so that I can rest longer
    if I need to.
11. As a user, I want those values bounded, so that I cannot set a zero-second
    break or a ninety-hour session by accident.
12. As a user, I want to set them with steppers, so that an invalid value is
    unreachable rather than rejected.
13. As a user, I want a warning shortly before a Break, so that it does not
    interrupt me mid-sentence.
14. As a user, I want the warning on every Display, so that I see it on the
    screen I am actually facing.
15. As a user, I want the warning to work inside fullscreen apps and under Do
    Not Disturb, so that it cannot be silently suppressed.
16. As a user, I want to turn the warning off, so that I can have the Break
    arrive unannounced if I prefer.
17. As a user in the middle of something urgent, I want to abandon a Break by
    holding a key, so that my own tool cannot hijack a live demo.
18. As a user, I want skipping to take a deliberate three-second hold, so that
    it cannot happen by reflex.
19. As a user, I want visible progress while I hold the key, so that I know how
    long is left.
20. As a user, I want skipping to start a fresh Session immediately, so that
    skipping costs me the rest rather than postponing it.
21. As a user, I want my skips counted and shown back to me, so that I notice
    if I am quietly turning the app off.
22. As a user, I want skipping never to be refused, so that the app does not
    fight me when I genuinely need the screen.
23. As a user, I want completed Sessions counted, so that I can see what the
    day looked like.
24. As a user, I want both counts to reset at midnight, so that they describe
    today.
25. As a user who locks the screen, I want the Session clock to pause, so that
    time away from the screen does not count as work.
26. As a user who closes the lid, I want the same, so that reopening does not
    immediately throw a Break at me.
27. As a user who is reading paper or on a call, I do **not** want input
    idleness to pause the clock, so that watching a video still counts as
    screen time.
28. As a user, I want the app in the menu bar with no Dock icon, so that a
    background utility does not take a Dock slot.
29. As a user mid-Session, I want to see the time remaining in the menu bar, so
    that I can judge whether to start something new.
30. As a user mid-Session, I want settings reachable from the menu bar, so that
    I can adjust without waiting.
31. As a user looking at the Overlay, I want settings reachable from the
    Overlay itself, so that a bad value is correctable without sitting through
    it.
32. As a user looking at the Overlay, I want a quit control there, so that the
    app is never a trap.
33. As a user, I want settings to persist across restarts, so that I configure
    once.
34. As a user, I want the app to start at login, so that I do not have to
    remember it.
35. As a user, I want the Overlay at login too, so that the day starts with a
    deliberate choice.
36. As a user who quits mid-Session, I want a clean slate on relaunch, so that
    a half-finished timer does not reappear confusingly.
37. As a user, I want Force Quit to keep working, so that a bug in this app
    cannot lock me out of my own machine.
38. As a user, I want a guarantee that I reach Idle — where Start is clickable
    — within a minute of the Break's due end, so that a wedged app is
    survivable without Force Quit. Idle is still locked; what is restored is
    the ability to act.
39. As a user who plugs in a monitor mid-Break, I want it covered too, so that
    a new screen is not a gap.
40. As a user who unplugs one mid-Break, I want the rest to keep working.
41. As a user changing the Session length mid-Session, I want it to take effect
    now, so that shortening it is not pointless.
42. As a user, I want the app to take activation straight back if something
    steals focus during Lockout, so that another app cannot end my Break by
    appearing in front of it.
43. As a user, I want log out, restart and shut down to keep working during a
    Break, so that Lockout never stands between me and my own machine.
44. As a user, I want the app to kill itself if it hangs while my screen is
    locked out, so that a crash in an eye-protector cannot cost me my
    machine.

## Implementation Decisions

**One seam.** The whole Idle → Session → Warning → Break → Idle cycle lives in
a pure value type, `CycleEngine`, in a core module. It reads no clock and
touches no AppKit: every instant arrives as a `now` argument. Events in,
`[Effect]` out. Everything else is a thin adapter.

```
Events    appLaunched(.user|.login) · startPressed · escapeCompleted · tick ·
          machineSlept · machineWoke · settingsChanged(Config)

Effects   presentOverlay · dismissOverlay · presentWarning ·
          dismissWarning · persistCounters(Counters)

State     idle · session(endsAt:) · warning(endsAt:) ·
          break(endsAt:escapable:)
```

Effects are returned as values rather than dispatched through a gateway
protocol, so the engine stays a pure function and its tests are plain equality
assertions with no mock.

**Lockout is engaged while Idle as well as during a Break.** Idle and Break
differ only in whether Start is live. This was a deliberate choice over a
non-blocking idle state.

**Project shape.** SwiftPM package assembled into an `.app` by `build.sh`
rather than an Xcode project (ADR 0001). `LSUIElement`, ad-hoc signed, bundle
id `com.michalramus.eyeprotector`.

**Space switching is absorbed, not blocked** (ADR 0003). Kiosk mode does not
swallow the trackpad swipe; `canJoinAllSpaces` means the swipe lands on a Space
that already has the Overlay. Overlay windows are therefore built for every
Display *before* Lockout engages. A `CGEventTap` was rejected to avoid the
Accessibility permission.

**No state persistence across launches** (ADR 0002), except the daily counters,
which are stored as loose `UserDefaults` keys so `Counters` stays a plain value
type.

**Force Quit stays enabled, plus two independent dead-man's switches**
(ADR 0004). The first lives in the adapter, not the engine, and recovers by
rebuilding the engine in its Idle state rather than asking it to transition —
a safety net that calls into the thing it protects against is not a safety
net. The second runs on its own thread and ends the process outright if the
main thread stops responding while Lockout is engaged, because every other
safeguard is main-thread code and so fails together with it. All three limits
live on one `SafetyNets` value with `.lenient` and `.strict` presets.

The decision of what counts as a stall is a pure `StallPolicy` in the core, so
it is unit-tested; the acting on it cannot be, since the only available action
is ending the process. A `EYE_PROTECTOR_WEDGE_AFTER` env var injects a
deliberate hang so that the kill can at least be observed by hand.

**Lockout keeps activation** by re-activating on `didResignActive`, without
consulting `presentationOptions` — that property keeps its assigned value even
once it has stopped taking effect, so reading it back cannot tell you whether
Lockout is still real.

**Display sleep is not treated as the user going away.** `screensDidSleep` is
driven by the system idle timer, so observing it would pause the Session clock
for a user who simply is not typing. Only machine sleep, screen lock and fast
user switching pause it, each as a matched away/back pair so that one source's
"back" cannot cancel another's "away".

**Escape** is detected with a local `NSEvent` monitor, not an event tap:
Lockout keeps the app frontmost for the whole Break, so the key events arrive
anyway. The escape count is checked against an `EscapePolicy`, currently
`.unlimited`, which exists so a cap can be added later without reshaping
anything.

**One settings view**, hosted twice: in the menu-bar popover during a Session
and on the Overlay while Idle.

**The Warning is a non-activating panel**, not a system notification, because
notifications need a permission prompt and are suppressed by Do Not Disturb and
by fullscreen apps.

**Config values are clamped on construction** rather than validated, so no
caller can hold a `Config` the engine would have to defend against.

## Testing Decisions

Tests exercise external behaviour through the single seam: feed the engine
events with explicit instants, assert on the returned state and effects. No
test reaches inside the engine's private fields, and none waits on a real
clock — a 30 minute Session is tested in microseconds.

Covered: launch, the full cycle end to end, warning timing, warning disabled,
escape counting and its no-ops outside a Break, sleep and wake including sleep
spanning a Session end and repeated sleeps, config clamping, config changes
mid-phase, midnight rollover, counter persistence only on change, and a very
late tick still owing a full Break.

Everything depending on the window server, the menu bar or a human holding a
key is checked by hand against `docs/manual-checks.md`, because there is no
honest unit test for "Mission Control is disabled".

There is no prior art in this repo — it is the first code in it.

## Out of Scope

- Input-idleness detection as a pause or break trigger (story 27 rules it out).
- Enabling a cap on Escapes. `EscapePolicy.maxPerDay` exists and works, but
  nothing selects it: the policy is always `.unlimited`. It is kept as the
  agreed hook for adding a cap later without reshaping anything.
- Configurable Escape hold duration, Overlay appearance, warning lead time, or
  choosing which Displays are covered.
- Sounds.
- Any persistence of Session progress across launches.
- A `CGEventTap`, and the Accessibility permission it would require.
- Notarisation and distribution beyond running locally.
- Recovering a Session after the watchdog has killed the process: the app
  restarts Idle like any other launch.
- Any history or reporting beyond today's two counts.

## Further Notes

The riskiest assumption — that macOS can be made to hold a user on one screen —
was spiked before anything was built on it, and the result is recorded in ADR
0003. The outcome changed the design: the swipe is not blocked, so the
all-Spaces Overlay is load-bearing rather than belt-and-braces.

Launch-at-login registration via `SMAppService` may be refused for an ad-hoc
signed app. The failure is surfaced in the settings UI rather than swallowed;
the fallback is a `~/Library/LaunchAgents` plist.
