#!/usr/bin/env bash
set -euo pipefail

# Resolve the launcher rig root of a workflow: the registered directory of the
# rig the workflow was slung into, where build artifacts live and where the
# artifact validator runs.
#
#   launcher-root.sh <bead-id>
#
# <bead-id> is any bead of the workflow (a claimed step or the root itself);
# the script walks gc.root_bead_id to the workflow root and reads the root's
# gc.root_store_ref, which gc stamps on every graph.v2 root as `rig:<name>`.
# It prints the rig's absolute, symlink-resolved path on stdout.
#
# The launcher is deliberately NOT read from the root's gc.work_dir. gc treats
# that key as executor/artifact metadata: a pooled worker never stamps it on
# the root (pool ownership guard, gascity#5026) and a separate-drain child root
# inherits the drain member's implementation worktree into it (gascity#5283).
# It is absent or wrong exactly when a stage needs the launcher. The process
# working directory is not used either: a pool slot is not the rig.
#
# Resolution order:
#   1. `rig:<name>` from the root's gc.root_store_ref. city:/class: scopes and
#      a missing reference fail closed; there is no single launcher rig.
#   2. $GC_RIG_ROOT, only when $GC_RIG equals <name> and the value is an
#      absolute directory. Rig-scoped sessions get both from gc, but the
#      executing rig may legitimately differ from the rig that owns the
#      workflow, and a city-scoped session has neither.
#   3. The `path` registered for <name> in `gc rig list --json`, skipping the
#      city's own `hq` entry, which that command lists first under the city
#      name.
#
# Exit status: 0 resolved; 1 unresolvable (the message on stderr says why,
# including a bead gc reports as not found); 75 when gc could not answer.

fail() {
  echo "launcher-root: $*" >&2
  exit 1
}

fail_infra() {
  echo "launcher-root: $* [infrastructure unreachable, exit 75]" >&2
  exit 75
}

BEAD_ID="${1:-${GC_BEAD_ID:-}}"
[ -n "$BEAD_ID" ] || fail "usage: launcher-root.sh <bead-id> (or set GC_BEAD_ID)"
command -v gc >/dev/null 2>&1 || fail "gc is required on PATH"
command -v python3 >/dev/null 2>&1 || fail "python3 is required on PATH"

metadata_value() {
  # metadata_value <json> <key> -> prints metadata[key] or empty; accepts the
  # object and one-element-list shapes of `gc bd show --json`.
  printf '%s' "$1" | python3 -c '
import json
import sys

key = sys.argv[1]
try:
    data = json.load(sys.stdin)
except Exception:
    print("")
    raise SystemExit(0)
if isinstance(data, list):
    data = data[0] if data else {}
if not isinstance(data, dict):
    print("")
    raise SystemExit(0)
metadata = data.get("metadata") or {}
value = metadata.get(key, "") if isinstance(metadata, dict) else ""
print(value if isinstance(value, str) else "")
' "$2"
}

GC_ERR="$(mktemp)"
trap 'rm -f "$GC_ERR"' EXIT INT TERM HUP

show_bead() {
  # show_bead <id> -> prints `gc bd show <id> --json`. A wrong id is a verdict,
  # not an outage: bd answers it with exit 1, "Issue <id> not found" on stderr
  # and a JSON error body on stdout, and that exits 1 here. Any other failure
  # (store unreachable, bd missing, a database "not found") exits 75.
  local out status=0
  out="$(gc bd show "$1" --json 2>"$GC_ERR")" || status=$?
  if [ "$status" -eq 0 ]; then
    [ -n "$out" ] || fail_infra "gc bd show $1 printed nothing"
    printf '%s' "$out"
    return 0
  fi
  # bd prints the same "no issues found" body after a fetch error too, so the
  # body alone is not a verdict when stderr reports one.
  if grep -qF "Issue $1 not found" "$GC_ERR" \
    || { printf '%s' "$out" | grep -qF '"error": "no issues found matching' \
         && ! grep -qF "Error fetching $1:" "$GC_ERR"; }; then
    fail "bead $1 not found: $(tail -c 400 "$GC_ERR" | tr '\n' ' ')"
  fi
  fail_infra "gc bd show $1 failed: $(tail -c 400 "$GC_ERR" | tr '\n' ' ')"
}

SHOW_JSON="$(show_bead "$BEAD_ID")"
ROOT_ID="$(metadata_value "$SHOW_JSON" "gc.root_bead_id")"
ROOT_JSON="$SHOW_JSON"
if [ -n "$ROOT_ID" ] && [ "$ROOT_ID" != "$BEAD_ID" ]; then
  ROOT_JSON="$(show_bead "$ROOT_ID")"
else
  ROOT_ID="$BEAD_ID"
fi

# Trim only the ends: an interior character is part of the rig's identity.
STORE_REF="$(metadata_value "$ROOT_JSON" "gc.root_store_ref" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
[ -n "$STORE_REF" ] || fail "workflow root $ROOT_ID has no gc.root_store_ref; cannot identify the launcher rig"
case "$STORE_REF" in
  rig:?*) RIG_NAME="${STORE_REF#rig:}" ;;
  *) fail "workflow root $ROOT_ID is scoped to '$STORE_REF', not a rig; there is no single launcher rig root" ;;
esac

canonical_dir() {
  # canonical_dir <path> -> prints the symlink-resolved absolute path of an
  # absolute directory, or fails. A relative value would resolve against the
  # session's working directory, which is a pool slot, not the rig.
  case "$1" in /*) ;; *) return 1 ;; esac
  [ -d "$1" ] || return 1
  (CDPATH= cd -- "$1" 2>/dev/null && pwd -P)
}

if [ "${GC_RIG:-}" = "$RIG_NAME" ]; then
  [ -n "${GC_RIG_ROOT:-}" ] \
    || fail "GC_RIG is $RIG_NAME but GC_RIG_ROOT is empty"
  canonical_dir "$GC_RIG_ROOT" \
    || fail "GC_RIG_ROOT=$GC_RIG_ROOT for rig $RIG_NAME is not an absolute existing directory"
  exit 0
fi

RIG_LIST="$(gc rig list --json 2>"$GC_ERR")" \
  || fail_infra "gc rig list --json failed: $(tail -c 400 "$GC_ERR" | tr '\n' ' ')"
RIG_LOOKUP="$(printf '%s' "$RIG_LIST" | python3 -c '
import json
import sys

# Prints "<status>\t<path>": registered, unbound (registered without a path),
# or missing. The city itself is listed first with hq=true under the city
# name; it is not a rig and never a launcher.
name = sys.argv[1]
try:
    data = json.load(sys.stdin)
except Exception:
    print("missing\t")
    raise SystemExit(0)
rigs = data.get("rigs") if isinstance(data, dict) else None
for rig in rigs or []:
    if not isinstance(rig, dict) or rig.get("hq") or rig.get("name") != name:
        continue
    # The registered path is used exactly as recorded; trimming it could
    # name a different directory.
    path = rig.get("path", "")
    if isinstance(path, str) and path.strip():
        print("registered\t" + path)
    else:
        print("unbound\t")
    raise SystemExit(0)
print("missing\t")
' "$RIG_NAME")"
RIG_STATUS="${RIG_LOOKUP%%	*}"
RIG_PATH="${RIG_LOOKUP#*	}"
case "$RIG_STATUS" in
  registered) ;;
  unbound) fail "rig $RIG_NAME from gc.root_store_ref on $ROOT_ID has no registered path (gc rig list --json)" ;;
  *) fail "rig $RIG_NAME from gc.root_store_ref on $ROOT_ID is not registered in this city (gc rig list --json)" ;;
esac
canonical_dir "$RIG_PATH" \
  || fail "registered path $RIG_PATH for rig $RIG_NAME is not an absolute existing directory"
