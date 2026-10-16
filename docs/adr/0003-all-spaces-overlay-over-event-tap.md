# Space swipes are absorbed by an all-Spaces Overlay, not blocked by an event tap

The core requirement is that the user cannot swipe away to another Space during
a Break. Two ways to get there: mark the Overlay `canJoinAllSpaces` so that
whichever Space the swipe lands on already has the Overlay on it, or install a
`CGEventTap` that swallows the gesture outright. We chose the Overlay.

## Considered Options

A `CGEventTap` would block the gesture completely, but it requires
Accessibility permission — granted by hand in System Settings, and re-granted
every time the binary is rebuilt during development — and it puts a callback in
front of every input event on the system. That is a large, permanently visible
permission to buy a cosmetic improvement.

## Consequences

The swipe is not prevented, only made pointless: the user sees the Space
transition animation and then the Overlay again. If that leak turns out to be
genuinely irritating in daily use, the escalation path is the event tap, and
this ADR is the record of what it costs. The same mechanism also covers
Mission Control and fullscreen apps, so no separate handling is needed for
those.
