Synthesize the build-basic starter factory review.

Read the acceptance, test evidence, and simplicity review reports. Deduplicate
findings, preserve the source review lane for each finding, and classify each
item as required fix, missing evidence, or residual risk.

Also read `gc.build.code_review_context_path` from the workflow root bead. When
you carry a finding forward, include the source anchor and implementation
worktree from the context's `## Implementation Worktrees` section. If a finding
cites only a relative filename, resolve that filename relative to the
implementation worktree, never the launcher checkout. Required fixes must be
specific enough for the fix lane to act without guessing which worktree owns the
file.

Contract: the launcher rig root is the registered path of the rig named by the
workflow root bead's `gc.root_store_ref` (`rig:<rig-name>`): `$GC_RIG_ROOT` when
`$GC_RIG` equals `<rig-name>`, otherwise the `path` of the `<rig-name>` entry in
`gc rig list --json` that is not the city's own `hq` entry; the result must be
an absolute existing directory. Do not read it from `gc.work_dir`, which gc may
leave unset or fill with an implementation worktree, and do not use `$(pwd)`. If
`gc.root_store_ref` is missing or not `rig:`-scoped, or the rig is not
registered, stop and report it instead of guessing a directory.

Write one starter review synthesis under the build artifact root. The synthesis
must be short enough for a first-time factory user to scan, but concrete enough
for the fix lane to act without another planning pass.

Close with `gc.outcome=pass`,
`code_review.synthesis_path=<starter review synthesis path>`, and
`code_review.output_path=<starter review synthesis path>`.

Do not invoke provider-native subagents. Synthesis happens in this Gas City
fan-in lane.
