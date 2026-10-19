# Skipping a Break and quitting both require retyping a random string

Abandoning a Break originally took a three-second hold of the Escape key, and
quitting took a single click. Both are now gated by a randomly generated
100-character alphanumeric string that must be retyped exactly.

A three-second hold is a speed bump, not a decision: it is short enough to
become reflex within a week, at which point the app stops working for its
purpose. A hundred characters is roughly half a minute of deliberate typing —
long enough that you cannot do it without noticing you have chosen to.

## Considered Options

An unambiguous alphabet (dropping `l`/`1`/`I`/`O`/`0`) and a word list were
both rejected in favour of full alphanumeric: telling the look-alikes apart is
part of the intended cost.

Mistyping could have invalidated the attempt and generated a fresh string. We
instead live-lock: the field refuses any character that does not match the
next expected one, so a wrong keystroke never lands. Being told at character
100 that you erred at character 12 punishes clumsiness rather than
irresolution, which is not the behaviour being targeted.

## Consequences

The string is displayed on screen in full, so it is only meaningful if it
cannot be copied. Paste, paste-as-plain-text, drag-and-drop, Services and
Cmd-A are all suppressed on the input, and the displayed string is
non-selectable. Screenshot-and-OCR still defeats it, and that is accepted: the
goal is cost, not secrecy.

Force Quit, log out, restart and shut down all remain available and bypass the
challenge entirely (ADR 0004). The quit challenge is therefore not a lock, it
is a way of making quitting no longer the path of least resistance. The
automatic safety nets — the dead-man's switch and the main-thread watchdog —
deliberately require no typing at all, since they exist for moments when the
user cannot interact with the app.
