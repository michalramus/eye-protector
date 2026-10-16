# A Session does not survive the app quitting

If the app quits or crashes part-way through a Session, the next launch starts
Idle rather than resuming the remaining time. Reviving a half-finished timer
after a crash is confusing — the user has no idea how much time the app thinks
is left — and a deliberate quit most plausibly means "stop watching me", so
honouring it is the friendlier reading.

The daily Session and Escape counters are the exception: those are persisted,
because they exist to be looked at over a whole day.

## Consequences

The cycle engine needs no serialisation, no schema and no migration story, and
its state can stay a plain in-memory value. The cost is that quitting the app
is an unlimited, uncounted way to skip a Break — which is acceptable, since
Escape already provides a counted one and nothing here is trying to defeat a
determined user.
