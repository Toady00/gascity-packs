This is the `implementation-item-base` methodology contract shared-drain item
step.

Concrete methodology packs override this step to perform one single-lane item
of implementation work with optional context from `{{context_path}}`. Do not
create parallel work inside this shared-drain contract.

Default fallback behavior must still enforce the worktree contract: resolve the
source anchor from workflow metadata, read the authoritative worktree from the
source anchor, and `cd "$WORKTREE"` before source reads, edits, tests, hashes,
or commits. The launcher rig root is the registered path of the rig named by the
workflow root bead's `gc.root_store_ref` (`rig:<rig-name>`): `$GC_RIG_ROOT` when
`$GC_RIG` equals `<rig-name>`, otherwise the `path` of `<rig-name>` from `gc rig
list --json`. Do not read it from `gc.work_dir`, which gc may leave unset or
fill with an implementation worktree, and do not use `$(pwd)`. If
`gc.root_store_ref` is missing or not `rig:`-scoped, or the rig is not
registered, stop and report it instead of guessing a directory. When reading
beads with `gc bd show --json`, handle both an object and a one-element list
before reading metadata.

Write the per-item implementation summary as a `gc.build.implementation-summary.v1`
artifact and record its absolute path on the workflow root bead as
`gc.implementation.summary_path` before closing.

The summary body must contain these exact schema-required `##` headings in this
order:

- `## Summary`
- `## Intended Behavior`
- `## Changed Files`
- `## Verification`
- `## Remaining Risks`

Artifact validation: this step is gated by the pack-owned `build-artifact-valid.sh` check, which validates the summary recorded at `gc.implementation.summary_path` (fallbacks `gc.build.implementation_summary_path`, then `gc.var.summary_path`) against schema `gc.build.implementation-summary.v1`. Before closing this step, resolve the launcher rig root with this pack's resolver, `"$(dirname "<gc.check_path>")/../launcher-root.sh" <workflow-root-id>` (it reads the root's `gc.root_store_ref`, never `gc.work_dir`, and fails closed on exit 1 or 75: do not guess a directory, report the message). If a city or pack layer shadows the validator so that no `launcher-root.sh` sits beside `gc.check_path`, apply the same rule by hand: the launcher rig root is the registered path of the rig named by the workflow root bead's `gc.root_store_ref` (`rig:<rig-name>`): `$GC_RIG_ROOT` when `$GC_RIG` equals `<rig-name>`, otherwise the `path` of `<rig-name>` from `gc rig list --json`. Do not read it from `gc.work_dir` and do not use `$(pwd)`; if the reference is missing or not `rig:`-scoped, or the rig is not registered, stop and report it instead of guessing a directory. Then run the same validator locally from that rig root. The validator is the script recorded as `gc.check_path` on the validation loop control bead (the dependent of this step bead whose `gc.kind` is `ralph`); Gas City resolves it to this pack's own `build-artifact-valid.sh` asset, so nothing has to be copied into the rig. Run `GC_BEAD_ID=<claimed-step-id> GC_RIG_ROOT=<launcher-rig-root> "<gc.check_path>"`; fix every reported validation error before setting `gc.outcome=pass`. On repair attempts (`gc.attempt` greater than 1), read the validator errors from `gc.attempt_log` on the validation loop control bead (the dependent of this step bead) and repair the summary in place instead of rewriting it. Two bounded repair attempts follow the first failure; exhausting them closes this stage with `gc.outcome=fail` and machine-readable validation errors that block downstream stages. Never ask questions in headless mode; record unresolved ambiguity inside the summary.
