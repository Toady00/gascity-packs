Implement this Compound Engineering item with {{implementation_target}}.

Read `work_dir` from the source anchor, validate that it is an absolute existing
git worktree, set `WORKTREE` to that path, and `cd "$WORKTREE"` before reading
or editing source files. If `work_dir` is missing, invalid, or points at the
launcher checkout, fail before editing. The launcher rig root is the registered
path of the rig named by the workflow root bead's `gc.root_store_ref`
(`rig:<rig-name>`): `$GC_RIG_ROOT` when `$GC_RIG` equals `<rig-name>`, otherwise
the `path` of the `<rig-name>` entry in `gc rig list --json` that is not the
city's own `hq` entry; the result must be an absolute existing directory. Do not
read it from `gc.work_dir`, which gc may leave unset or fill with an
implementation worktree, and do not use `$(pwd)`. If `gc.root_store_ref` is
missing or not `rig:`-scoped, or the rig is not registered, stop and report it
instead of guessing a directory. The launcher rig root is not the implementation
worktree; do not edit, test, or commit in the launcher checkout.

Use the installed ce-work guidance as the implementation prompt for this Gas
City lane. Implement only the owned source anchor boundary, run focused
verification from inside the worktree, then make a focused commit in the
worktree (`git add` the changed files and `git commit`). The inherited
`close-source-anchor` step fails closed when the worktree has no implementation
commit, so uncommitted edits are a failed implementation, not a pass. Write an
implementation summary to `{{artifact_root}}/task-<source-anchor-id>-summary.md`
after resolving the source anchor. Record the summary path, focused commit
hash, changed files, and verification result on this implement step and on the
source anchor before closing this step.

Close with `gc.outcome=pass` only after the work is implemented, verified, and
committed.

Do not invoke provider-native subagents. Leave the source anchor open for the
close-source-anchor step.

Artifact validation: this step is gated by `.gc/scripts/checks/build-artifact-valid.sh`, which validates the summary recorded at `gc.implementation.summary_path` (fallbacks `gc.build.implementation_summary_path`, then `gc.var.summary_path`) against schema `gc.build.implementation-summary.v1`. On repair attempts (`gc.attempt` greater than 1), read the validator errors from `gc.attempt_log` on the validation loop control bead (the dependent of this step bead) and repair the summary in place instead of rewriting it. Two bounded repair attempts follow the first failure; exhausting them closes this stage with `gc.outcome=fail` and machine-readable validation errors that block downstream stages. Never ask questions in headless mode; record unresolved ambiguity inside the summary.
