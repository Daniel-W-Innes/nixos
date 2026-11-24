#!/usr/bin/env bash
# Convenience runner for the VM switch tests (see docs/testing.md).
# Runs the requested modes for the requested hosts sequentially and saves each
# test's full output to ~/vm-test-logs/<timestamp>/<test>.log plus a
# SUMMARY.md index — share the summary (or any log) with an AI via @<path>.
set -uo pipefail

# Resolve through symlinks (the script is linked into ~/.local/bin/vm-test)
# so the flake below is always the real repo checkout, then run from its
# root so `vmtest` works from any directory.
repo_root=$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)
cd "$repo_root"

usage() {
  cat <<'EOF'
Usage: tests/run-vm-tests.sh [options] [MODE ...]

Modes (default: all permitted):
  smoke             boot the new config, run switch-to-configuration test
  transition        boot the new config, switch to master and back
  state             live /var/lib + real agenix secrets (root only)
  transition-state  transition test on live state (root only)

State modes share the machine's own /var/lib and /etc/ssh, so they only run
for the local host, and only as root (or with --with-state, which uses sudo).

Options:
  --hosts h1,h2     hosts to test (default: melon,onion)
  --with-state      force the root-only state modes via sudo
  --no-state        skip state modes even when running as root
  --out DIR         output directory (default: ~/vm-test-logs/<timestamp>)
  -h, --help        show this help

Progress is one line per test; watch a run with:
  tail -f ~/vm-test-logs/latest/<test>.log
EOF
}

hosts=(melon onion)
state=auto # auto | yes | no
out=
modes=()

while (($#)); do
  case "$1" in
    --hosts)
      [[ -n ${2:-} ]] || { echo "error: --hosts needs a comma-separated list" >&2; exit 2; }
      IFS=',' read -r -a hosts <<<"$2"
      shift 2
      ;;
    --with-state) state=yes; shift ;;
    --no-state) state=no; shift ;;
    --out)
      [[ -n ${2:-} ]] || { echo "error: --out needs a directory" >&2; exit 2; }
      out=$2
      shift 2
      ;;
    -h | --help) usage; exit 0 ;;
    --*) echo "error: unknown option: $1" >&2; usage >&2; exit 2 ;;
    *) modes+=("$1"); shift ;;
  esac
done

explicit_modes=0
((${#modes[@]} > 0)) && explicit_modes=1

known_modes=(smoke transition state transition-state)
if ((!explicit_modes)); then
  modes=("${known_modes[@]}")
fi
for m in "${modes[@]}"; do
  ok=0
  for k in "${known_modes[@]}"; do
    [[ $m == "$k" ]] && ok=1
  done
  ((ok)) || { echo "error: unknown mode: $m (known: ${known_modes[*]})" >&2; exit 2; }
done

local_host=$(hostname)
euid=$(id -u)

run_state=0
case "$state" in
  yes) run_state=1 ;;
  no) run_state=0 ;;
  auto) ((euid == 0)) && run_state=1 ;;
esac

# onion's /tmp is tmpfs; the driver puts sparse disk images in TMPDIR, which
# need a real filesystem.
export TMPDIR=/var/tmp

sudo_prefix=()
if ((run_state && euid != 0)); then
  command -v sudo >/dev/null 2>&1 || { echo "error: --with-state needs sudo, which is not installed" >&2; exit 2; }
  sudo_prefix=(sudo env TMPDIR=/var/tmp)
fi

outdir=${out:-$HOME/vm-test-logs/$(date +%Y%m%d-%H%M%S)}
mkdir -p "$outdir"

trap 'echo; echo "interrupted — partial logs in $outdir" >&2; exit 130' INT

results=()
skipped=()
passed=0
failed=0

for h in "${hosts[@]}"; do
  for m in "${modes[@]}"; do
    is_state=0
    [[ $m == state || $m == transition-state ]] && is_state=1

    if ((is_state)); then
      if [[ $h != "$local_host" ]]; then
        if ((explicit_modes)); then
          echo "error: $h-$m cannot run here — state modes share $local_host's /var/lib and /etc/ssh" >&2
          exit 2
        fi
        continue
      fi
      if ((!run_state)); then
        if ((explicit_modes)); then
          echo "error: $m needs root — run as root or pass --with-state" >&2
          exit 2
        fi
        skipped+=("$h-$m|needs root — run as root or pass --with-state")
        continue
      fi
    fi

    name="$h-$m"
    log="$outdir/$name.log"

    case "$m" in
      smoke)
        # The driver, not `nix build` of the check: building a cached check
        # derivation is a silent no-op (the test does not re-run), so the
        # driver always executes it. CI's `nix build` keeps its own
        # cache-hit semantics on purpose.
        cmd=(nix run --print-build-logs ".#packages.x86_64-linux.$h-vm-test-driver")
        ;;
      transition)
        cmd=(nix run --print-build-logs ".#packages.x86_64-linux.$h-vm-test-transition")
        ;;
      state)
        cmd=("${sudo_prefix[@]}" nix run --print-build-logs ".#packages.x86_64-linux.$h-vm-test-state")
        ;;
      transition-state)
        cmd=("${sudo_prefix[@]}" nix run --print-build-logs ".#packages.x86_64-linux.$h-vm-test-transition-state")
        ;;
    esac

    printf '==> %-26s ' "$name"
    {
      echo "# test:     $name"
      echo "# command:  ${cmd[*]}"
      echo "# started:  $(date '+%F %T')"
    } >"$log"

    t0=$SECONDS
    "${cmd[@]}" >>"$log" 2>&1
    rc=$?
    dur=$((SECONDS - t0))

    status=PASS
    ((rc)) && status=FAIL

    {
      echo "# ended:    $(date '+%F %T')"
      echo "# result:   $status (${dur}s, exit $rc)"
    } >>"$log"

    if ((rc == 0)); then
      printf 'PASS (%ds)\n' "$dur"
      passed=$((passed + 1))
    else
      printf 'FAIL (%ds, exit %d)\n' "$dur" "$rc"
      failed=$((failed + 1))
    fi
    results+=("$name|$rc|$dur|$name.log")
  done
done

{
  echo "# VM test run — $(date '+%F %T')"
  echo
  echo "- machine: **$local_host** (user: $(whoami), euid $euid)"
  echo "- hosts tested: ${hosts[*]}"
  echo "- repo: $(git rev-parse --abbrev-ref HEAD) @ $(git rev-parse --short HEAD)"
  if git status --short | grep -q .; then
    echo "- working tree (uncommitted changes affect what is tested):"
    git status --short | sed 's/^/    /' | head -n 12
  else
    echo "- working tree: clean"
  fi
  echo "- log directory: $outdir"
  echo
  echo "| Test | Result | Duration | Log |"
  echo "|---|---|---|---|"
  for r in "${results[@]}"; do
    IFS='|' read -r name rc dur file <<<"$r"
    if ((rc == 0)); then status=PASS; else status=FAIL; fi
    echo "| $name | $status | ${dur}s | [$file]($file) |"
  done
  for s in "${skipped[@]}"; do
    IFS='|' read -r name reason <<<"$s"
    echo "| $name | skipped | — | $reason |"
  done
  if ((failed)); then
    echo
    echo "## Failures (last 60 lines of each log)"
    for r in "${results[@]}"; do
      IFS='|' read -r name rc dur file <<<"$r"
      ((rc == 0)) && continue
      echo
      echo "### $name"
      echo
      echo '```'
      tail -n 60 "$outdir/$file"
      echo '```'
    done
  fi
} >"$outdir/SUMMARY.md"

if [[ -z $out ]]; then
  ln -sfn "$outdir" "$HOME/vm-test-logs/latest"
fi

echo
echo "Summary: $outdir/SUMMARY.md"
if [[ -z $out ]]; then
  echo "Latest:  $HOME/vm-test-logs/latest/SUMMARY.md"
fi
echo "Share with an AI:  @$outdir/SUMMARY.md"

if ((failed)); then
  echo
  echo "Result: $failed of $((passed + failed)) tests FAILED"
  exit 1
fi
echo
echo "Result: all $passed tests passed"
if ((${#skipped[@]})); then
  echo "Skipped: ${#skipped[@]} (see SUMMARY.md)"
fi
