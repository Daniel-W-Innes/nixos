---
name: hyprland-quickshell
description: Edit or debug the Hyprland + quickshell desktop on cucamelon (bar, OSD, power menu, widgets, keybinds, theming, new windows). Use when the user asks for DE changes or reports rendering bugs. Contains the verified quickshell 0.3.0 API facts, the hard architectural lessons (hidden-window lazy content, async DesktopEntries, ly/systemd traps), and the live-testing harness that actually works on onion/cucamelon.
---

# Editing the Hyprland + quickshell desktop (cucamelon)

Everything here is hard-won from the 2026-09 waybar/wofi → quickshell migration. Read `docs/issues/08-quickshell-launcher-abandoned.md` before touching anything launcher-shaped. The bar itself works; the launcher attempt failed.

## Architecture map

| Concern | File |
|---|---|
| HM module (laptop home) | `home/hypr.nix` — `programs.quickshell.configs.main = ./quickshell`, packages (alacritty, wofi, playerctl, brightnessctl, pavucontrol, dolphin) |
| Hyprland config | `home/hyprland/hyprland.conf` — classic (non-Lua) syntax; `$menu = wofi --show drun` is the launcher (quickshell launcher was abandoned) |
| Shell entry | `home/quickshell/shell.qml` — `ShellRoot` with one `Variants { model: Quickshell.screens }` per window type (Bar, Osd, PowerMenu). Windows cannot nest; per-screen state flows through the `Ui` singleton |
| Lockscreen | `home/quickshell-lock/` — its own `lock` config (replaces swaylock), spawned on demand as `quickshell --config lock` by the hyprland keybind and the power menu |
| Design tokens | `home/quickshell/Theme.qml` (pragma Singleton) — colors, metrics, fonts, motion |
| Cross-window state | `home/quickshell/Ui.qml` (pragma Singleton) — OSD + power-menu state and functions |
| Widgets | `home/quickshell/widgets/*.qml` — Workspaces, SystemStats, Network, Audio, Brightness, Battery, Clock, Tray |
| System bits | `generic/laptop.nix` (`services.upower.enable` — off by default, battery widget needs it), `generic/min.nix` (fonts: `nerd-fonts.symbols-only` for glyphs) |

quickshell 0.3.0 is pinned in nixpkgs 26.05. Pinned binary: `/nix/store/fzk0q2plg3r8c5nrvwihs96vkvwpakx6-quickshell-0.3.0/bin/quickshell`; pinned source: `/nix/store/zcr5219wvflsqn1hyn78lpabxfcsgi6b-source`. There is no `--check` flag — stderr is the validator. The deployed config is a store symlink: **no hot-reload**.

## Verified API facts (0.3.0, from the pinned source — do not guess beyond these)

- **No native TextField** — use `import QtQuick.Controls` `TextField` (QtQuick/Controls is in qtdeclarative, quickshell's own dep).
- **`DesktopEntries`** (singleton): `applications` ObjectModel (always access `.values`), async scan of XDG app dirs that populates ~2 s after config load. `DesktopEntry`: `name`, `genericName`, `icon`, `keywords`, `command` (argv, field codes already parsed), `runInTerminal`, `execute()` (ignores Terminal=true — wrap in `alacritty -e` yourself). Icons: `Quickshell.iconPath(icon, true)` (empty string when unresolvable).
- **`ScriptModel`** diffs a JS expression asynchronously — fine for long lists, but it caused empty-first-frame bugs; for short lists a plain JS array as the `ListView` model is simpler and immediate.
- **`IpcHandler`** (`Quickshell.Io`): functions declared on it are callable via `quickshell ipc -c <config> call <target> <fn>` — **`-c` must come before the `call` subcommand** (CLI11 rejects it after). `quickshell kill -c <config>` exits 0 when it kills a live instance, 255 when none matches (`||` relaunch pattern). `ipc show` lists targets.
- **`PanelWindow`**: `anchors`/`margins`/`exclusiveZone`, `color: "transparent"` + `surfaceFormat.opaque: false`, `WlrLayershell.layer: WlrLayer.Overlay`, `focusable: true` → `keyboard_interactivity_on_demand` on the layer surface.
- **`Variants`** sets a plain `modelData` property on delegates: declare `property var modelData: null` in the window root — `required` breaks.
- **QML gotchas**: `color` type needs `import QtQuick`; `Component`/`Qt.quit()` need `import QtQml`; `Behavior { enabled: ... }`, never `NumberAnimation { enabled: ... }`; inline `component Foo:` names must start uppercase; write glyphs as `String.fromCodePoint(0x...)` (ASCII-safe) and verify codepoints with a fontTools cmap dump — never invent them (one fabricated codepoint shipped a fork-and-knife as a CPU icon).

## The hard lessons (architecture rules)

1. **Never build on-demand UI as a hidden window in the bar config.** quickshell lazily builds hidden-window content; a `ListView` can skip creating its delegates on the first show — silently: no QML errors, and `hyprctl layers` shows the surface mapped, but the results area renders empty. Screenshots of later opens look fine, which is how this stayed hidden. Windows that are visible from config load work. If on-demand UI is truly needed, run it as a **separate process with a visible-from-startup window**.
2. **`DesktopEntries` data must be reactive bindings** (`property var allEntries: { ... }`), never a one-shot read at `Component.onCompleted` — the async scan makes one-shots permanently empty.
3. **ly never activates `graphical-session.target`**: never use the HM quickshell systemd unit (`programs.quickshell.systemd.enable`) or any `WantedBy=graphical-session.target` unit on cucamelon. `exec-once` in hyprland.conf is the startup mechanism.
4. **After `nixos-rebuild switch`, the running bar keeps its old config** (store symlink, no reload, exec-once only runs at hyprland start). Restart in place: `kill <bar pid>`, then `HYPRLAND_INSTANCE_SIGNATURE=<sig> hyprctl dispatch exec "quickshell --config main"` where `<sig>` is the directory name under `/run/user/1000/hypr/` (reading `/proc/<pid>/environ` over ssh is permission-denied). Or the user re-logs in.
5. **HiDPI**: eDP-1 is 2560×1440 @ 2× → logical 1280×720. `hyprctl layers` reports logical units; grim captures the physical buffer. Don't mix them up when cropping screenshots.

## Lockscreen (`quickshell --config lock`) — rules are life-or-death here

- **NEVER test the lock on onion.** A 2026-09-19 smoke test left onion's niri session locked with no working unlock path and forced a hard shutdown. Lock acquisition tests happen on cucamelon only, with the user physically present. Auth-plumbing tests (Process + unix_chkpwd in a plain FloatingWindow, no `WlSessionLock`) are safe on onion.
- **`unix_chkpwd` reads until a NUL byte, not a newline** (linux-pam 1.7.2 `pam_read_passwords`). Write `password + String.fromCharCode(0)`; a newline-terminated write blocks the helper forever — symptom: user types, dots appear, Enter does nothing, no error, session stuck (the onion incident). Shell-test convention: `printf 'pw\0' | unix_chkpwd daniel nonull` (exit 0 = correct, 7 = wrong; syslog confirms real verification).
- **`WlSessionLock`'s default property is `surface`** (a `QQmlComponent`) — any other child (IpcHandler, Timer, Process) becomes the component root and silently breaks lock acquisition. Helpers go under `ShellRoot`, as siblings.
- **`Process`**: `write()` is a no-op until the process object exists — write in `onStarted`, never right after `exec()`/`running = true`. Prefer `command` + `running = true` over `exec()`. `exited(exitCode, exitStatus)`; `exitStatus === 0` means NormalExit (1 = CrashExit, incl. failed-to-start).
- **Recovery hatch**: the real config carries `IpcHandler { target: "lock"; function unlock() }` → `quickshell ipc -c lock call lock unlock` releases a stuck lock from a shell. Trade-off: any process running as daniel can unlock. **Unlock-before-kill**: killing the lock client while locked keeps the session locked forever (compositor restart is the only recovery) — that's the secure-by-design property of ext-session-lock.
- **After a switch**, restart the bar (rule 4) or the power menu's Lock row still points at the now-removed `swaylock` binary. The hyprland keybind needs a hyprland config reload (`hyprctl reload`) or re-login.

## Testing harness (the part that works — use it, don't improvise)

Onion is the machine Claude Code runs on (niri session): `WAYLAND_DISPLAY=wayland-1 XDG_RUNTIME_DIR=/run/user/1000`. Run the pinned binary against the repo config directly (`quickshell -p /home/daniel/repos/nixos/home/quickshell`, or `-c main` with `XDG_CONFIG_HOME` pointed at a symlink tree). Screenshot with `nix shell nixpkgs#grim nixpkgs#imagemagick -c ...` and upscale/crop to a 3840×1080 canvas for image delivery (`magick shot.png -resize 50% -background "#202020" -gravity center -extent 3840x1080 out.png`). `wtype` works on niri for typing tests.

**But onion is not proof for cucamelon.** Always finish with a pre-deploy smoke test on the real machine:

```bash
# copy config to cucamelon, run in the live session, screenshot back
scp -r home/quickshell/<part> cucamelon:/tmp/<part>-test
ssh cucamelon 'chmod -R u+w /tmp/<part>-test; cd /tmp && \
  setsid nohup env WAYLAND_DISPLAY=wayland-1 XDG_RUNTIME_DIR=/run/user/1000 \
  /etc/profiles/per-user/daniel/bin/quickshell -p /tmp/<part>-test \
  > /tmp/<part>-test.log 2>&1 < /dev/null &'
# ... screenshot, verify, then:
ssh cucamelon 'WAYLAND_DISPLAY=wayland-1 XDG_RUNTIME_DIR=/run/user/1000 quickshell kill -p /tmp/<part>-test'
```

Ground truths: `hyprctl layers` says whether a surface is really mapped; the bar's own log is `/run/user/1000/quickshell/by-id/*/log.log` (text; `log.qslog` is binary). `hyprctl` over ssh needs `HYPRLAND_INSTANCE_SIGNATURE` (see rule 4) — grim/quickshell CLIs only need `WAYLAND_DISPLAY` + `XDG_RUNTIME_DIR`.

pkill footguns: the nix wrapper renames comm to `.quickshell-wra` (`pkill -x quickshell` matches nothing; kill by pid). Any `pkill -f` pattern that literally appears in your own command line kills your own shell — use a bracket regex (`pkill -f 'quickshell-0.3[.]0'`).

Keyboard input on hyprland **cannot** be tested remotely (wtype's virtual keyboard never reaches hyprland — verified). Hand typing/Esc/Enter off to the user.

Always test the **first open after a fresh process start** — lazy-content bugs only appear there; later opens look correct.

## Workflow

1. Check `docs/issues/` for known problems (08 is the launcher saga) and CLAUDE.md gotchas.
2. Edit QML/nix. QML changes only affect the bar after an in-place restart or re-login (rule 4).
3. `nix fmt` + `nix build .#nixosConfigurations.cucamelon.config.system.build.toplevel` + `git add` the changes (nix flakes need tracked/staged files).
4. Smoke test on onion for iteration, then **pre-deploy smoke test on cucamelon** (above).
5. Hand off: user commits/pulls/switches. State which changes need a bar restart vs just a re-login vs neither. Never commit; leave the diff staged for the user.
