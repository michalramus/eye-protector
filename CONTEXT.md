# Context

Glossary for Eye Protector. Terms only — no implementation detail.

## Display

A physical screen connected to the machine.

## Space

A macOS virtual desktop. Maximising an app creates a new Space of its own; the
three-finger swipe moves between Spaces. **Not** a Display. When the user says
"monitor" or "desktop" in the context of switching, they mean a Space.

## Session

A stretch of uninterrupted work, 30 minutes by default, during which the app is
invisible. Always begun deliberately, by starting it from the Overlay. A Session
does not advance while the machine is asleep or locked; input idleness does not
pause it.

## Break

The forced rest that follows a Session, 30 seconds by default. Lockout is in
force for its whole duration. A Break ends either by expiring or by an Escape.

## Idle

The state between a Break ending and the next Session beginning. The Overlay is
visible and Lockout is still in force, so the machine is unusable until the user
starts a Session — but, unlike during a Break, that is one click away at any
moment. Reached by a Break ending, by launching the app, and by an Escape being
spent.

## Overlay

The surface covering every Display and present on every Space, shown during a
Break and while Idle, and the only part of the app the user normally sees. It
disappears when a Session starts. Carries the Start Session control, plus
settings and quit controls that are live only while Idle.

## Lockout

The condition of being unable to reach any other application: no switching
between Spaces or applications, no Dock, no menu bar. In force during a Break
and while Idle. Lifting Lockout is what makes the Start Session control
clickable, and it is guaranteed to lift no later than one minute after a Break
was due to end, whatever else goes wrong.

## Escape

A deliberate abort of a Break before its timer expires, performed by holding a
key. An Escape ends the Break and begins a new Session immediately, so it trades
the rest away rather than postponing it. Escapes are counted and shown back to
the user, but never refused.

## Warning

A brief notice shown on every Display shortly before a Session ends, so the
Break does not arrive unannounced. Optional.
