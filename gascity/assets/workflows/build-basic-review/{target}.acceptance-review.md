Run the starter factory acceptance review lane.

Review the implementation against the requirements, acceptance criteria,
implementation plan, decomposition, and task summaries. Focus on correctness:
did the factory build the requested behavior, and did it avoid out-of-scope
changes?

Read the review context first and evaluate the implementation source
anchor/worktree recorded there. The launcher rig root is not the review target
for build-basic; it may still contain the original fixture until publish. Do not
mark acceptance as `iterate` merely because the root checkout is unchanged when
the recorded source anchor/worktree implements the requested behavior and its
proof commands pass.

Before inspecting files or running tests, read `gc.build.code_review_context_path`
from the workflow root bead and use its `## Implementation Worktrees` section as
the authority for code under review. The launcher rig root is not the
implementation worktree. Do not inspect or edit the launcher checkout when
deciding whether the implementation passes. Resolve every relative source path
and proof command from the review context against the listed implementation
worktree, run `cd "$WORKTREE"`, and verify `pwd -P` equals that worktree before
executing commands. If the context is missing a usable implementation worktree,
write an iterate finding against review setup instead of reviewing the launcher
checkout.

Contract: the launcher rig root is the registered path of the rig named by the
workflow root bead's `gc.root_store_ref` (`rig:<rig-name>`): `$GC_RIG_ROOT` when
`$GC_RIG` equals `<rig-name>`, otherwise the `path` of the `<rig-name>` entry in
`gc rig list --json` that is not the city's own `hq` entry; the result must be
an absolute existing directory. Do not read it from `gc.work_dir`, which gc may
leave unset or fill with an implementation worktree, and do not use `$(pwd)`. If
`gc.root_store_ref` is missing or not `rig:`-scoped, or the rig is not
registered, stop and report it instead of guessing a directory.

Write findings under the build artifact root. Required findings must include
the relevant requirement or task reference plus the file, command, or artifact
that proves the issue.

Close with `gc.outcome=pass`,
`code_review.acceptance_verdict=approve|iterate`, and
`code_review.output_path=<acceptance review report path>`.

Use explicit close metadata so the review loop can detect the lane result:

```bash
gc bd update "$CLAIMED_BEAD_ID" \
  --set-metadata 'gc.outcome=pass' \
  --set-metadata 'code_review.acceptance_verdict=approve' \
  --set-metadata 'code_review.output_path=<acceptance review report path>'
gc bd close "$CLAIMED_BEAD_ID" --reason 'Build-basic acceptance review approved.'
```

If you find required fixes, set
`code_review.acceptance_verdict=iterate` instead of `approve` and explain the
smallest required fix in the report and close reason.

Do not set `code_review.verdict` or `code_review.report_path`; synthesis and
fix application own the final review verdict.

Do not invoke provider-native subagents. You are the starter factory acceptance
review lane.
