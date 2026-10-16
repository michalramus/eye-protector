# Force Quit stays enabled, and Lockout always lifts within a minute

`NSApplicationPresentationOptions` can disable Force Quit and session
termination, and a maximally strict eye-protector would do both. We
deliberately leave them enabled, and additionally guarantee that the user
reaches Idle — where Start is one click away — no later than one minute after
a Break was due to end, by a timer independent of the cycle engine.

A third net sits underneath both: a watchdog on its own thread that ends the
process if the main thread stops responding while Lockout is engaged. The other
safeguards are all main-thread code, so a wedged main thread disables every one
of them at once — including the dead-man's switch. Presentation options can
only be changed from the main thread, so there is nothing to do but exit and
let the window server restore the Dock and menu bar. Losing an in-progress
Session costs nothing, since none of it is persisted anyway (ADR 0002).

Note what the dead-man's switch is not: Idle is itself locked, so the net
restores the ability to *act*, not the desktop. Being unable to restart the
machine was never part of what Lockout was asked to do, which is why session
termination stays available too.

Both exist because every other way out of Lockout — the Escape hold, the Break
timer — depends on this app's own code being correct. A bug in the Overlay
would otherwise leave the user with no keyboard route out of their own machine.
Force Quit is clumsy enough that it is unlikely to become a habitual skip.

## Status

Accepted, with the intent to revisit. All three safeguards live on a single
`SafetyNets` value with a `.lenient` default and a `.strict` alternative, so
strictness can be raised in one place once the app has been trusted in daily
use for a while; the user has asked for that to be the eventual destination.
