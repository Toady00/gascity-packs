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
#   2. $GC_RIG_ROOT, only when $GC_RIG equals <name>. Rig-scoped sessions get
#      both from gc, but the executing rig may legitimately differ from the
#      rig that owns the workflow, and a city-scoped session has neither.
#   3. The `path` registered for <name> in `gc rig list --json`.
#
# Exit status: 0 resolved; 1 unresolvable (the message on stderr says why);
# 75 when gc could not answer.

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

SHOW_JSON="$(gc bd show "$BEAD_ID" --json 2>"$GC_ERR")" \
  || fail_infra "gc bd show $BEAD_ID failed: $(tail -c 400 "$GC_ERR" | tr '\n' ' ')"
ROOT_ID="$(metadata_value "$SHOW_JSON" "gc.root_bead_id")"
ROOT_JSON="$SHOW_JSON"
if [ -n "$ROOT_ID" ] && [ "$ROOT_ID" != "$BEAD_ID" ]; then
  ROOT_JSON="$(gc bd show "$ROOT_ID" --json 2>"$GC_ERR")" \
    || fail_infra "gc bd show $ROOT_ID failed: $(tail -c 400 "$GC_ERR" | tr '\n' ' ')"
else
  ROOT_ID="$BEAD_ID"
fi

STORE_REF="$(metadata_value "$ROOT_JSON" "gc.root_store_ref")"
[ -n "$STORE_REF" ] || fail "workflow root $ROOT_ID has no gc.root_store_ref; cannot identify the launcher rig"
case "$STORE_REF" in
  rig:?*) RIG_NAME="${STORE_REF#rig:}" ;;
  *) fail "workflow root $ROOT_ID is scoped to '$STORE_REF', not a rig; there is no single launcher rig root" ;;
esac

canonical_dir() {
  # canonical_dir <path> -> prints the symlink-resolved absolute path, or fails
  [ -d "$1" ] || return 1
  (cd "$1" 2>/dev/null && pwd -P)
}

if [ "${GC_RIG:-}" = "$RIG_NAME" ] && [ -n "${GC_RIG_ROOT:-}" ]; then
  canonical_dir "$GC_RIG_ROOT" \
    || fail "GC_RIG_ROOT=$GC_RIG_ROOT for rig $RIG_NAME is not a directory"
  exit 0
fi

RIG_LIST="$(gc rig list --json 2>"$GC_ERR")" \
  || fail_infra "gc rig list --json failed: $(tail -c 400 "$GC_ERR" | tr '\n' ' ')"
RIG_PATH="$(printf '%s' "$RIG_LIST" | python3 -c '
import json
import sys

name = sys.argv[1]
try:
    data = json.load(sys.stdin)
except Exception:
    print("")
    raise SystemExit(0)
rigs = data.get("rigs") if isinstance(data, dict) else None
for rig in rigs or []:
    if isinstance(rig, dict) and rig.get("name") == name:
        path = rig.get("path", "")
        print(path if isinstance(path, str) else "")
        raise SystemExit(0)
print("")
' "$RIG_NAME")"
[ -n "$RIG_PATH" ] || fail "rig $RIG_NAME from gc.root_store_ref on $ROOT_ID is not registered in this city (gc rig list --json)"
canonical_dir "$RIG_PATH" \
  || fail "registered path $RIG_PATH for rig $RIG_NAME is not a directory"
