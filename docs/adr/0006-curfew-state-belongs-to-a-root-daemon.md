# Curfew state belongs to a root daemon, not to the app the user can kill

Curfew blocks the machine on a wall-clock schedule — nights and weekends — and
charges a two-hundred-character retype to buy twenty or thirty minutes back.
The user it polices is an admin on the machine, has `htop` open and has asked,
in as many words, not to be able to unlock the screen and then kill the process.

That rules out the shape Eye Protector uses. There, the app is a single
user-session process holding its state in memory, and quitting it is an
acknowledged, unlimited way out (ADR 0002). Here the same design would make
`kill` strictly better than typing: unlock, kill, and the night is free.

So Curfew splits in two.

**`curfew --daemon`** runs as root from a `LaunchDaemon` with `KeepAlive`. It
owns the config, the state file and the clock, and it draws nothing — a daemon
has no access to the window server, and wanting one is a sign of a design
error. It also supervises the agent: every few seconds it checks that the
agent is bootstrapped in the console user's GUI session and kickstarts it if
not. That is what makes `launchctl bootout` of the agent — which needs no
password — a pause of a few seconds rather than an escape.

**`curfew --agent`** runs as the user, in the Aqua session, from a
`LaunchAgent` with `KeepAlive`. It draws the shield, shows the challenge and
reports what was typed. It decides nothing. Its state is a cache of what the
daemon last said.

The two talk over a unix socket the daemon owns in `/var/run`.

## Why the state file cannot live with the agent

The agent runs as the user, so anything it can write, the user can write. A
state file holding `unlockedUntil` would be editable at 19:55 to say 2030, and
every other mechanism in the app would be decoration. Root ownership of the
state is therefore not hardening, it is the load-bearing wall.

The same argument covers the config: a curfew whose start time the user can
move without a password is not a curfew. `/Library/Application Support/Curfew/`
is root-owned, and changing the schedule costs a `sudo`.

## Fail closed, everywhere

A missing, unreadable or corrupt state file is read as *no grace*, not as a
clean slate with the night off. A daemon the agent cannot reach is read as
*shield up*. Deleting things is therefore a way to lock yourself out and never
a way in, which is the only direction an error here is allowed to point.

Winding the system clock back counts as tampering: more than five minutes of
backwards movement (generous for an NTP correction, useless for moving a
curfew) raises the shield on its own account and discards any grace that was
running.

## What this does not claim

Root can kill anything, and the user has root. `sudo launchctl bootout
system/…` ends Curfew, which is the documented uninstall. Recovery mode, a
second admin account and a pre-written script that talks to the socket before
20:00 all work too.

Blocking those needs an Endpoint Security client authorising `SIGKILL`, which
needs an entitlement Apple grants case by case, or a non-removable MDM profile,
which needs enrolment. Neither is available to a personal project, and
pretending otherwise — hiding the process, renaming it, blocking Activity
Monitor — would buy nothing against a user who already knows where it lives.

What is bought instead is that every bypass is deliberate, takes minutes, and
cannot be done by reflex at 23:00. That is the product.

## Status

Accepted. Force Quit and session termination stay enabled, as in ADR 0004: the
main-thread watchdog ends a wedged process and `KeepAlive` brings it straight
back with its state intact, so killing the shield costs a second and gains
nothing. The safety net and the lock are, for once, the same mechanism.
