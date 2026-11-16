# Curfew

A second app in this repo, built from `Sources/CurfewApp`. Where Eye Protector
interrupts a working day, Curfew blocks the machine outright on a schedule:
nights and weekends. It is for someone who is an admin on their own machine and
has asked not to be able to talk themselves out of it at 23:00.

**It blocks the screen once installed.** Read [Ways out](#ways-out) before
running `--install`, and do not try it on a machine you need.

## What it does

By default the shield is up from 20:00 to 11:00 every day, and all day on
Saturday and Sunday. It covers every display, the way Eye Protector's overlay
does.

Getting through costs a retyped string, 200 characters, which cannot be pasted.
A passed challenge buys 20 minutes at night and 30 at the weekend. When the
time is up the shield comes back; a short warning appears before it does. The
schedule, the toll and the grace are all in the config file below.

## Two processes, one binary

`curfew --daemon` runs as root and owns the config, the state and the clock. It
draws nothing. `curfew --agent` runs as the user, draws the shield and reports
what was typed. It decides nothing, and the daemon puts it back within a few
seconds if it is killed or booted out.

The reason is that anything the user can write, the user can edit: a state file
in their home directory would turn "20:00" into "2030" with one line. So the
state lives with root. [ADR 0006](adr/0006-curfew-state-belongs-to-a-root-daemon.md)
has the argument, including why a missing or corrupt file means "shield up"
and why winding the clock back counts as tampering.

## Config

`/Library/Application Support/Curfew/config.json`, root-owned. Edit it with
`sudo`; the daemon reloads it within a second. Every field is optional and
falls back to its default, so the file may hold only the lines being changed.
Out-of-range values are clamped, not rejected.

| Field | Default | Bounds |
| --- | --- | --- |
| `nightStart` | `"20:00"` | May wrap midnight |
| `nightEnd` | `"11:00"` | |
| `weekendDays` | `[1, 7]` | 1 is Sunday, 7 is Saturday; values outside 1–7 are dropped. These days are blocked end to end |
| `nightGrace` | 1200 (20 min) | 60–14400 seconds |
| `weekendGrace` | 1800 (30 min) | 60–14400 seconds |
| `warningLead` | 120 seconds | 0 up to the shorter of the two graces |
| `challengeLength` | 200 | 10–1000 characters |

`nightStart` and `nightEnd` are `"HH:MM"` strings, 24-hour, for example
`{"nightStart": "21:30"}`.

## Install and uninstall

```
./build-curfew.sh release
cp -R Curfew.app /Applications/
sudo /Applications/Curfew.app/Contents/MacOS/Curfew --install
```

The DMG from `./Scripts/make-dmg.sh <version> curfew` holds the same app. It is
ad-hoc signed and not notarised, so clear the quarantine flag as for Eye
Protector.

`--install` writes a LaunchDaemon and a LaunchAgent, writes a default config if
there is none, and starts the daemon. The plists point at the binary that ran
`--install`, so run it from `/Applications`, where the daemon expects to find
it.

```
sudo /Applications/Curfew.app/Contents/MacOS/Curfew --uninstall
```

stops both jobs, removes both plists and deletes the state file. The config and
the log stay behind in the support directory.

## Status and logs

```
/Applications/Curfew.app/Contents/MacOS/Curfew --status
```

asks the daemon over its socket and prints the period, whether the shield is
up and why, when it next rises, what a challenge buys and how many times it has
been unlocked. No `sudo` needed. If it cannot reach the daemon it says so, and
the agent will be showing the shield for the same reason.

Events are in `/Library/Application Support/Curfew/events.log`; the daemon's
stderr is in `daemon.log` next to it.

## Ways out

None of these is hidden, because pretending would buy nothing against someone
who knows where the process lives. Each one is deliberate and takes minutes.

- `sudo launchctl bootout system/com.michalramus.curfew.daemon` ends the
  daemon. This is also what `--uninstall` does.
- Recovery mode: remove the plists from there.
- Another machine over ssh, if Remote Login is on. The shield is a window and
  a set of presentation options; it has no opinion about sshd.
- A second admin account buys seconds rather than a session: the daemon
  follows whoever owns `/dev/console`, so switching users gets that session
  shielded too within about five seconds — enough time to run a command you
  already know, not enough to go looking for one.
- A script that talks to the daemon's socket before the curfew starts can
  unlock it, since the daemon cannot tell who is typing.

### If you are locked out right now

While the shield is up you cannot reach a terminal: process switching is off.
The two routes that do not depend on this app behaving are ssh from another
machine, and a restart into Recovery to delete

```
/Library/LaunchDaemons/com.michalramus.curfew.daemon.plist
/Library/LaunchAgents/com.michalramus.curfew.agent.plist
```

Turning Remote Login on *before* the first install is the cheap insurance, and
costs nothing if it is never needed.

Not a way out: `launchctl bootout gui/$UID/com.michalramus.curfew.agent`. It
needs no password, but the daemon bootstraps the agent again within seconds.

Force Quit and logging out stay enabled, as in
[ADR 0004](adr/0004-force-quit-stays-enabled.md).
