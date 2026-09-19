# quickshell app launcher abandoned; wofi restored

### Summary

On 2026-09-19 the wofi → quickshell launcher migration on cucamelon (Hyprland 0.55.4) was abandoned after repeated rounds of "the launcher opens but shows no results" that could not be reproduced from the testing machine. wofi is restored as the `$mainMod + d` launcher. This issue records the full saga, the verified facts, and the open contradictions, so a future attempt doesn't repeat it.

### Environment

- quickshell 0.3.0 (pinned nixpkgs 26.05; store path `fzk0q2plg3r8c5nrvwihs96vkvwpakx6-quickshell-0.3.0`, source `zcr5219wvflsqn1hyn78lpabxfcsgi6b-source`).
- cucamelon: Hyprland 0.55.4 via ly, single monitor eDP-1 2560×1440 @ 2× scale (logical 1280×720 — layer surfaces are logical; grim captures the physical buffer), one Wayland session on `wayland-1`.
- onion (the machine Claude Code runs on) has a niri session used as the test harness (`WAYLAND_DISPLAY=wayland-1 XDG_RUNTIME_DIR=/run/user/1000`, grim screenshots, wtype works there but **not** on hyprland — virtual-keyboard keys never reach it, verified by `wtype -M logo -k t` not spawning the terminal).
- Deploy flow: user commits/pulls/switches themselves; the running bar keeps its old config after a switch (quickshell config is a store symlink, no hot-reload; `exec-once` only runs at hyprland start; ly never activates `graphical-session.target` so the HM unit is inert). In-place bar restart is possible: signature = the dir name under `/run/user/1000/hypr/`, then `HYPRLAND_INSTANCE_SIGNATURE=<sig> hyprctl dispatch exec "quickshell --config main"` after `kill <pid>` (not `pkill -x quickshell` — the nix wrapper renames comm to `.quickshell-wra`).

### Attempt 1: in-bar launcher (hidden window + IPC) — failed

Design: `home/quickshell/Launcher.qml`, a full-screen overlay `PanelWindow` per screen inside the bar's config, hidden until toggled; `IpcHandler { target: "launcher"; function toggle(): void }` in `shell.qml`; keybind `quickshell ipc -c main call launcher toggle` (note: `-c` must precede the `call` subcommand or CLI11 rejects it).

Verified quickshell 0.3.0 API ground truth from the pinned source/built qmltypes: `DesktopEntries` singleton (async scan of XDG application dirs, populates ~2s after config load, ~15 entries on cucamelon), `DesktopEntry` (name/icon/command/runInTerminal/execute()), `Quickshell.iconPath(icon, true)`, `ScriptModel`, `IpcHandler` (CLI `ipc call`/`show`/`list`/`kill`), `PanelWindow.focusable` (→ `keyboard_interactivity_on_demand`), no native TextField (QtQuick.Controls works), `IconImage` widget.

Failure modes, in order:
1. **Stale bar process**: first user test did nothing because the running bar predated the switch (no IpcHandler registered) — `ipc show` returned no targets; "Target not found" from `ipc call`. Fixed by the in-place restart.
2. **ScriptModel deferred diff**: with `ListView { model: ScriptModel { values: matches } }`, the first frames after opening showed empty row shells; content appeared 1–2s later. Switched to a plain JS array model (≤25 rows, cheap churn).
3. **Lazy first-show content** (the killer): with the plain-array model and the window hidden at config load, the user's *first* open after each bar start showed a results area **sized for rows but with zero delegates** — no QML errors in the bar's log (`/run/user/1000/quickshell/by-id/*/log.log`), `hyprctl layers` showed the surface mapped. A model bump (`list.model = null; list.model = matches`) in the show handler and a 120ms fade both masked the issue in some states but never fixed the user's first press. Forced-visible-at-startup copies of the config rendered rows immediately. Conclusion: quickshell lazily builds hidden-window content and the ListView can skip delegate creation on the first show frame.

All of this was invisible from the test machine: every screenshot taken on cucamelon via ssh (both my IPC toggles and `hyprctl dispatch exec` equivalents of the keybind) showed filled rows, because those were never the *first* open of a fresh bar process, or were of the fade-masked version.

### Attempt 2: separate always-visible process (MVP) — still "not working"

Design: `home/quickshell/launcher/shell.qml`, its own config, window `visible: true` from startup (no hidden state at all, so the lazy-content class of bugs is architecturally impossible), name-only rows, no icons, no IPC; keybind `quickshell kill -c launcher || quickshell --config launcher` (verified: `kill` exits 0 when it kills a live instance, 255 when none matches); Esc/click-out/launch → `Qt.quit()`.

Two data-layer fixes were needed:
1. A one-shot read of `DesktopEntries.applications.values` at `Component.onCompleted` is always empty (the scan is async) → made it a **reactive binding** (`property var allEntries: {...}`), which demonstrably re-evaluates as the scan populates; `matches` likewise binds on `query`.
2. "Loading…" vs "No matches" distinction based on `DesktopEntries.applications.values.length === 0`.

**Pre-deploy verification on cucamelon itself** (real binary, live session, `quickshell -p /tmp/launcher-test`): screenshot at ~1s shows the card with "Loading…"; at ~5s the full list (nnn, Dolphin, NixOS Manual, GVim, Signal, Discord, Vim…). Zero errors in the log. `quickshell kill -p` semantics confirmed. The user then deployed, rebooted, and still reported failure (last report: "always showing No matches", i.e. the pre-reactivity symptom — though the reactive version had not yet been deployed at that point; the final reactive build was never user-confirmed before abandonment).

### Open contradictions / unverified (would need resolution for a retry)

- Every automated observation said the launcher worked; every user observation said it didn't. Never explained. Possibly meaningful differences: the physical keypress vs ssh-spawned toggles (unlikely to differ — both exec the same command), and observation timing (the ~2s scan window plus cold wrapper/engine startup ~300–500ms).
- **Keyboard focus on hyprland was never verified**: `focusable: true` requests `keyboard_interactivity_on_demand`; whether hyprland gives a just-mapped overlay layer surface keyboard focus without a click is unknown (works on niri; wtype cannot inject keys into hyprland sessions to test remotely). If a retry ever gets the list rendering, check whether typing needs a click first.
- `hyprctl layers` is the ground truth for whether a layer surface is mapped; grim captures the physical framebuffer. Screenshots and the user's display can disagree only if sessions diverge — one session was verified via `who`/sockets, so this stays unexplained.

### Current state / rollback

- wofi restored: package in `home/hypr.nix`, `$menu = wofi --show drun` + `bind = $mainMod, d, exec, $menu` in `home/hyprland/hyprland.conf`.
- Deleted: `home/quickshell/launcher/`, `home/quickshell/Launcher.qml`, the IpcHandler/launcher bits from `home/quickshell/shell.qml` + `Ui.qml` + `Theme.qml` (all recoverable from git history: the migration commits on the `hypr-laptop` branch).
- The quickshell **bar** (main config: bar, OSD, power menu) is unaffected and works.

### Lessons

- quickshell windows that must render on demand: prefer a separate process whose window is visible from startup over a toggled-hidden window (lazy content build can skip ListView delegate creation on first show, silently — no errors, `hyprctl layers` shows the surface mapped).
- `DesktopEntries` populates asynchronously (~2s); data must be a reactive binding, never a one-shot read.
- Debug recipes that worked: `quickshell -p /tmp/...` scratch instances in the live session (config copies from the store are read-only until `chmod -R u+w`); console.log diagnostics into stderr; grim + ImageMagick crop/zoom for instant screenshots; `pkill -f 'quickshell-0.3[.]0'` (bracket trick to avoid matching the invoking shell).
