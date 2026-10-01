#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const menu = requireFromRoot('shell/plugins/menu/MenuModel.js')
const menuQml = fs.readFileSync(path.join(root, 'shell/plugins/menu/Menu.qml'), 'utf8')

assertEqual(menu.calcEvaluate('10+2'), 12, 'calculator adds')
assertEqual(menu.calcEvaluate('10 + 2'), 12, 'calculator skips spaces')
assertEqual(menu.calcEvaluate('(2+3)*4'), 20, 'calculator groups with parentheses')
assertEqual(menu.calcEvaluate('2^10'), 1024, 'calculator raises to a power')
assertEqual(menu.calcEvaluate('-5+3'), -2, 'calculator applies a leading minus')
assertEqual(menu.calcEvaluate('--5'), 5, 'calculator stacks unary minus')
assertEqual(menu.calcEvaluate('-2^2'), -4, 'calculator binds unary minus looser than power')
assertEqual(menu.calcEvaluate('10%3'), 1, 'calculator takes the remainder')
assertEqual(menu.calcEvaluate('3.5*2'), 7, 'calculator multiplies decimals')
assertEqual(menu.calcEvaluate('.5+.5'), 1, 'calculator adds dot-prefixed decimals')
assertEqual(menu.calcEvaluate('5.+1'), 6, 'calculator accepts a trailing decimal point')
assertEqual(menu.calcEvaluate('2×3'), 6, 'calculator accepts × as typed')
assertEqual(menu.calcEvaluate('1.5^2'), 2.25, 'calculator raises decimals to a power')

assertEqual(menu.calcEvaluate('10+'), null, 'calculator rejects a trailing operator')
assertEqual(menu.calcEvaluate('2*(3+4/(2-2))'), null, 'calculator rejects division by zero')
assertEqual(menu.calcEvaluate('1.2.3'), null, 'calculator rejects a malformed decimal')
assertEqual(menu.calcEvaluate('sqrt(4)'), null, 'calculator rejects what is not arithmetic')
assertEqual(menu.calcEvaluate('abc'), null, 'calculator rejects words')
assertEqual(menu.calcEvaluate(''), null, 'calculator rejects an empty expression')
assertEqual(menu.calcEvaluate('10 20'), null, 'calculator rejects a trailing operand')
assertEqual(menu.calcEvaluate('2*(3+4'), null, 'calculator rejects an unbalanced parenthesis')

assertEqual(menu.calcFormat(menu.calcEvaluate('0.1+0.2')), '0.3', 'calculator drops float noise')
assertEqual(menu.calcFormat(menu.calcEvaluate('100/3')), '33.3333333333', 'calculator rounds through 12 significant digits')
assertEqual(menu.calcFormat(menu.calcEvaluate('1000000*1000000')), '1000000000000', 'calculator keeps large products plain')
assertEqual(menu.calcFormat(menu.calcEvaluate('1234567890123456')), '1234567890120000', 'calculator keeps every significant digit it promises')
assertEqual(menu.calcFormat(menu.calcEvaluate('2^100')), '1.26765060023e+30', 'calculator switches huge values to exponent notation')
assertEqual(menu.calcFormat(menu.calcEvaluate('-0.1-0.2')), '-0.3', 'calculator formats negative results without noise')
assertEqual(menu.calcFormat(1e-12), '1e-12', 'calculator switches small values to exponent notation')
assertEqual(menu.calcFormat(Infinity), '', 'calculator formats what cannot be shown as nothing')

assert(
  /function calcEvaluate\(expr\) \{\s*\n\s*return MenuModel\.calcEvaluate\(expr\)\s*\n\s*\}/.test(menuQml)
    && /function calcFormat\(value\) \{\s*\n\s*return MenuModel\.calcFormat\(value\)\s*\n\s*\}/.test(menuQml),
  'menu delegates calculator evaluation to the shared model'
)
assert(
  /if \(query\.charAt\(0\) === "="\) \{[\s\S]*?var calcValue = root\.calcEvaluate\(calcExpr\)/.test(menuQml),
  'menu evaluates a query that starts with = instead of searching it'
)
assert(
  /action: "wl-copy -- " \+ Util\.shellQuote\(calcText\)/.test(menuQml),
  'menu copies the result to the clipboard behind --, so a negative result never reads as an option'
)
JS

pass "menu calculator answers =-prefixed queries"

# ---------------------------------------------------------------- runtime pass
#
# The node pass covers the evaluator; this one drives the whole path — summon,
# type, Enter, clipboard — against a throwaway quickshell instance running the
# checkout's own shell, the way screenshot-sanity-test.sh does.

require_compositor "menu calculator runtime test"

if ! command -v quickshell >/dev/null 2>&1; then
  skip "quickshell not installed; skipping menu calculator runtime test"
  exit 0
fi
if ! command -v wtype >/dev/null 2>&1; then
  skip "wtype not installed; skipping menu calculator runtime test"
  exit 0
fi
if pgrep -x omasnap >/dev/null 2>&1; then
  skip "omasnap is already running; skipping menu calculator runtime test"
  exit 0
fi

require_command jq
require_command wl-copy
require_command wl-paste

TMPDIR=$(mktemp -d)
QS_PID=""

cleanup() {
  if [[ -n $QS_PID ]] && kill -0 "$QS_PID" 2>/dev/null; then
    kill "$QS_PID" 2>/dev/null || true
    wait "$QS_PID" 2>/dev/null || true
  fi
  [[ -n ${test_root:-} ]] && rm -f "$(shell_ipc_socket "$test_root")"
  if [[ -n $TMPDIR && -d $TMPDIR ]]; then
    rm -rf "$TMPDIR"
  fi
}
trap cleanup EXIT

test_root="$TMPDIR/omarchy"
test_home="$TMPDIR/home"
log="$TMPDIR/quickshell.log"
mkdir -p "$test_root" "$test_home"
cp -a "$ROOT/shell" "$test_root/shell"
ln -s "$ROOT/config" "$test_root/config"
ln -s "$ROOT/bin" "$test_root/bin"
ln -s "$ROOT/default" "$test_root/default"

shell_ipc() {
  OMARCHY_PATH="$test_root" "$ROOT/bin/omarchy-shell" "$@"
}

OMARCHY_PATH="$test_root" \
HOME="$test_home" \
XDG_CONFIG_HOME="$test_home/.config" \
XDG_CACHE_HOME="$test_home/.cache" \
XDG_STATE_HOME="$test_home/.local/state" \
  quickshell -p "$test_root/shell" --no-color >"$log" 2>&1 &
QS_PID=$!

for _ in {1..80}; do
  if shell_ipc -q shell ping >/dev/null 2>&1; then
    break
  fi
  if ! kill -0 "$QS_PID" 2>/dev/null; then
    sed -n '1,120p' "$log" >&2
    fail "menu calculator test shell exited before IPC became available"
  fi
  sleep 0.1
done

# Best-effort clipboard save: the calculator copies plain text, so only the
# text content can be preserved and restored.
saved_clipboard=$(wl-paste -n 2>/dev/null || true)

shell_ipc -q shell summon omarchy.menu '{"menu":"root"}' >/dev/null
sleep 1
wtype "=6*7"
sleep 0.5
wtype -k Return
sleep 0.5

copied=""
for _ in {1..20}; do
  copied=$(wl-paste -n 2>/dev/null || true)
  [[ $copied == "42" ]] && break
  sleep 0.2
done

shell_ipc -q shell hide omarchy.menu >/dev/null 2>&1 || true
[[ -n $saved_clipboard ]] && wl-copy -n -- "$saved_clipboard" 2>/dev/null || true

[[ $copied == "42" ]] || fail "menu calculator copies the result to the clipboard: got '$copied'"
pass "menu calculator copies the result to the clipboard"
