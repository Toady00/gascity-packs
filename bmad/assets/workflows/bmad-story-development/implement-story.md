Implement the BMAD story with the installed `bmad-quick-dev` and
`bmad-dev-story` skills.

Treat BMAD's "hand to a sub-agent/task" instruction as this Gas City lane.

Resolve the source anchor as the workflow root's stamped `gc.source_anchor_id`;
only when the root has none, use the same rules as the do-work
`prepare-worktree` step (for a shared-drain item, the drain member in
`gc.drain_member_id`), read `work_dir` from the source anchor, validate that it
is an absolute existing git worktree, set `WORKTREE` to that path, and `cd
"$WORKTREE"` before reading or editing source files. If `work_dir` is missing,
invalid, or points at the launcher checkout, fail before editing. The launcher
rig root is the registered path of the rig named by the workflow root bead's
`gc.root_store_ref` (`rig:<rig-name>`): `$GC_RIG_ROOT` when `$GC_RIG` equals
`<rig-name>`, otherwise the `path` of `<rig-name>` from `gc rig list --json`. Do
not read it from `gc.work_dir`, which gc may leave unset or fill with an
implementation worktree, and do not use `$(pwd)`. If `gc.root_store_ref` is
missing or not `rig:`-scoped, or the rig is not registered, stop and report it
instead of guessing a directory. It is not the implementation worktree; do not
edit, test, or commit in the launcher checkout.

Implement the story, run focused tests from inside the worktree, update task
completion evidence, then make a focused commit in the worktree (`git add` the
changed files and `git commit`). Do-work's `close-source-anchor` step fails
closed when the worktree has no implementation commit, so uncommitted edits are
a failed implementation, not a pass. Commit only when `git status --porcelain`
shows changes, and never use `git commit --allow-empty`. This step re-runs on
every story loop iteration: if the story is already committed and nothing
changed, do not commit again; record the existing `HEAD` commit hash instead.
Write an implementation summary to
`{{artifact_root}}/task-<source-anchor-id>-summary.md` after resolving the
source anchor. Record the summary path, focused commit hash, changed files, and
verification result on the story-development step before closing it. Leave the
source anchor open; later workflow steps close it.

Close with `gc.outcome=pass` only after the story is implemented, verified, and
committed.

Do not invoke provider-native subagents. You are the implementation lane.
