
Resolve `<source-anchor-id>` as described below: the root's stamped
`gc.source_anchor_id`, else the same rules as `prepare-worktree`. For a
synthetic drain-unit convoy, the source anchor is the original drain member in
`gc.drain_member_id`, not the synthetic convoy id. Read `work_dir` from the source anchor, never read `work_dir` from the synthetic drain-unit convoy,
validate that it is an absolute existing git worktree, set `WORKTREE` to that
path, then `cd "$WORKTREE"` before reading or editing source files. If
`work_dir` is missing, invalid, or points at the launcher checkout, fail this step before editing.

Do not infer the source anchor from dependency ids such as the
`prepare-worktree` step. Read the claimed step bead's `gc.root_bead_id`, read
that do-work root with `gc bd show <root-bead-id> --json`;
if the JSON output is a one-element list, unwrap the first element before
reading metadata. If the
root has `gc.source_anchor_id`, `prepare-worktree` already resolved the anchor
and stamped it there: use exactly that id and do not re-derive it. Only when
the root has no `gc.source_anchor_id` (a workflow started before the stamp
existed), read the root metadata `gc.input_convoy_id` and read that input
convoy with `gc bd show <input-convoy-id> --json`. If the input convoy has
`gc.synthetic_kind=drain-unit-convoy`, use its `gc.drain_member_id` as the
source anchor. Else if it has `gc.synthetic=true`, use its single tracked member
from `gc convoy status <input-convoy-id> --json`. Otherwise use the input
convoy id as the source anchor. Then read the source anchor and use only its
`work_dir` metadata as `WORKTREE`; for an unstamped root whose resolved member
has no `work_dir`, a pre-stamp `prepare-worktree` persisted it on the
`gc.synthetic=true` input convoy, so read `work_dir` from that convoy instead.

The launcher rig root is the registered path of the rig named by the workflow
root bead's `gc.root_store_ref` (`rig:<rig-name>`): `$GC_RIG_ROOT` when
`$GC_RIG` equals `<rig-name>`, otherwise the `path` of `<rig-name>` from `gc rig
list --json`. Do not read it from `gc.work_dir`, which gc may leave unset or
fill with an implementation worktree, and do not use `$(pwd)`. If
`gc.root_store_ref` is missing or not `rig:`-scoped, or the rig is not
registered, stop and report it instead of guessing a directory. The launcher rig
root is used only later to run the artifact validator. After resolving
`WORKTREE`, run `cd "$WORKTREE"` and verify `pwd -P` equals `$WORKTREE` before
any source read, source edit, test, file hash, `git add`, or `git commit`. If a
command uses the launcher checkout path for source edits, verification, hashes,
or commits, the step is invalid and must fail.

Do not edit files in the launcher checkout. Implement only the owned source
anchor boundary, run sandboxed verification from inside the worktree, and make a
focused commit in the worktree. Leave the source anchor open for
`close-source-anchor`; close only this implementation step when done.

Write or update the task summary with these schema-required body sections,
using the exact `##` headings below in this order:

- `## Summary`
- `## Intended Behavior`
- `## Changed Files`
- `## Verification`
- `## Remaining Risks`

The `## Verification` section must include both the first verification command
and the final proof command, with the observed pass/fail result.

Write the summary as a `gc.build.implementation-summary.v1` artifact and record
its absolute path on the workflow root bead as `gc.implementation.summary_path`
before closing.
Include a Markdown coverage table. The validator only recognizes a table with
an `ID` column and a `Status` column. Use this shape:

| ID | Status |
| --- | --- |
| REQ-001 | covered |

Use mapping objects for front matter; do not use scalar shortcuts such as
`workflow: build-basic`. The top-level YAML shape must be:

- `schema: gc.build.implementation-summary.v1`
- `workflow: {id: <workflow-root-id>, formula: <root-workflow-formula>}`
- `methodology: {pack: gascity, name: build-basic}`
- `producer: {formula: do-work, stage: implement, attempt: <positive integer>}`
- `status: approved` or another schema-allowed status
- `trace: {upstream: [...], coverage: [...]}`

Trace front matter must use the validator shape exactly:

- `trace.upstream[]` entries must include `path` and `hash`; do not use
  `id`/`title`/`type` entries as the upstream shape.
- For the source anchor bead, use `path: beads/<source-anchor-id>` and
  `hash: bead:<source-anchor-id>`. For changed files or upstream build
  artifacts, use repo-relative paths and scheme-qualified hashes such as
  `sha256:<digest>` or `git:<revision>`.
- If an upstream entry lists `ids`, every listed id must appear exactly once in
  `trace.coverage` and in the Markdown coverage table with the same status.
- Coverage statuses are not artifact statuses. Use `covered` for satisfied
  requirements; do not use `approved` in `trace.coverage[].status` or the
  Markdown coverage table.

Artifact validation: this step is gated by the pack-owned `build-artifact-valid.sh` check, which validates the summary recorded at `gc.implementation.summary_path` (fallbacks `gc.build.implementation_summary_path`, then `gc.var.summary_path`) against schema `gc.build.implementation-summary.v1`. Before closing this step, resolve the launcher rig root with this pack's resolver, `"$(dirname "<gc.check_path>")/../launcher-root.sh" <workflow-root-id>` (it reads the root's `gc.root_store_ref`, never `gc.work_dir`, and fails closed on exit 1 or 75: do not guess a directory, report the message). If a city or pack layer shadows the validator so that no `launcher-root.sh` sits beside `gc.check_path`, apply the same rule by hand: the launcher rig root is the registered path of the rig named by the workflow root bead's `gc.root_store_ref` (`rig:<rig-name>`): `$GC_RIG_ROOT` when `$GC_RIG` equals `<rig-name>`, otherwise the `path` of `<rig-name>` from `gc rig list --json`. Do not read it from `gc.work_dir` and do not use `$(pwd)`; if the reference is missing or not `rig:`-scoped, or the rig is not registered, stop and report it instead of guessing a directory. Then run the same validator locally from that rig root. The validator is the script recorded as `gc.check_path` on the validation loop control bead (the dependent of this step bead whose `gc.kind` is `ralph`); Gas City resolves it to this pack's own `build-artifact-valid.sh` asset, so nothing has to be copied into the rig. Run `GC_BEAD_ID=<claimed-step-id> GC_RIG_ROOT=<launcher-rig-root> "<gc.check_path>"`; fix every reported validation error before setting `gc.outcome=pass`. On repair attempts (`gc.attempt` greater than 1), read the validator errors from `gc.attempt_log` on the validation loop control bead (the dependent of this step bead) and repair the summary in place instead of rewriting it. Two bounded repair attempts follow the first failure; exhausting them closes this stage with `gc.outcome=fail` and machine-readable validation errors that block downstream stages. Never ask questions in headless mode; record unresolved ambiguity inside the summary.
