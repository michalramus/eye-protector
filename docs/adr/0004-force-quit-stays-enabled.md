# Force Quit stays enabled, and Lockout always lifts within a minute

`NSApplicationPresentationOptions` can disable Force Quit, and a maximally
strict eye-protector would. We deliberately leave it enabled, and additionally
guarantee that Lockout lifts no later than one minute after a Break was due to
end, by a timer independent of the cycle engine.

Both exist because every other way out of Lockout — the Escape hold, the Break
timer — depends on this app's own code being correct. A bug in the Overlay
would otherwise leave the user with no keyboard route out of their own machine.
Force Quit is clumsy enough that it is unlikely to become a habitual skip.

## Status

Accepted, with the intent to revisit. Both safeguards are behind flags so that
strictness can be raised later once the app has been trusted in daily use for a
while; the user has asked for that to be the eventual destination.
