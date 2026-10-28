Apply required BMAD story findings.

Make the smallest implementation and test changes needed to resolve required self-check or acceptance-audit findings. If no required findings exist, record a no-op fix result and preserve the review artifact path.

Resolve the source anchor as the workflow root's stamped `gc.source_anchor_id`;
only when the root has none, use the same rules as the do-work
`prepare-worktree` step (for a shared-drain item, the drain member in
`gc.drain_member_id`), read `work_dir` from the source anchor, validate that it
is an absolute existing git worktree, set `WORKTREE` to that path, and `cd
"$WORKTREE"` before reading or editing source files. This step may run in a
different session from implement-story, so resolve the worktree here. If
`work_dir` is missing, invalid, or points at the launcher checkout, fail before
editing. The launcher rig root is the registered path of the rig named by the
workflow root bead's `gc.root_store_ref` (`rig:<rig-name>`): `$GC_RIG_ROOT` when
`$GC_RIG` equals `<rig-name>`, otherwise the `path` of `<rig-name>` from `gc rig
list --json`. Do not read it from `gc.work_dir`, which gc may leave unset or
fill with an implementation worktree, and do not use `$(pwd)`. If
`gc.root_store_ref` is missing or not `rig:`-scoped, or the rig is not
registered, stop and report it instead of guessing a directory. It is not the
implementation worktree; do not edit, test, or commit in the launcher checkout.

Read the BMAD story self-check and acceptance-audit reports from the current
attempt. Write the fix summary under
`{{artifact_root}}/bmad-story-development/`.

If there are no required findings, perform a no-op pass and close with
`gc.outcome=pass`, `bmad_story.verdict=done`, and
`bmad_story.report_path=<fix summary path>`. Also set
`code_review.verdict=done` and `code_review.report_path=<fix summary path>` so
the inherited implementation-review check can approve the BMAD story loop.

Make any code or test changes in `$WORKTREE`, the same source-anchor worktree
the implement-story step committed in, and commit them there as a focused
commit (`git add` the changed files and `git commit`) so `close-source-anchor`
verifies the fixed code, not only the first attempt. Commit only when
`git status --porcelain` shows changes; on the no-op path do not commit, and
never use `git commit --allow-empty`. Record the fix commit hash in the fix
summary.

If required findings were present and you changed and committed code or tests
to address them, close with `gc.outcome=pass`, `bmad_story.verdict=iterate`, and
`bmad_story.report_path=<fix summary path>`. Also set
`code_review.verdict=iterate` and `code_review.report_path=<fix summary path>`
so the Gas City loop reruns the BMAD self-check and acceptance audit on the
changed worktree. If required findings remain unresolved, close with
`gc.outcome=fail`.

Do not invoke provider-native subagents. This Gas City lane owns the story-fix pass.
