
Run inside an existing shared worktree lifecycle. Resolve reserved `convoy_id`,
read `gc.drain_member_id` and `gc.drain_item_index`, validate ownership and
verification policy, validate context path {{context_path}} when set, implement
the item, write an item summary, and close only the source anchor on success.

Do not infer the source anchor from dependency ids. Read the reserved convoy and
source anchor metadata directly; when `gc bd show --json` returns a one-element
list, unwrap the first element before reading metadata. The launcher rig root is
the registered path of the rig named by the workflow root bead's
`gc.root_store_ref` (`rig:<rig-name>`): `$GC_RIG_ROOT` when `$GC_RIG` equals
`<rig-name>`, otherwise the `path` of the `<rig-name>` entry in
`gc rig list --json` that is not the city's own `hq` entry; the result must be
an absolute existing directory. Do not read it from `gc.work_dir`, which gc may
leave unset or fill with an implementation worktree, and do not use `$(pwd)`. If
`gc.root_store_ref` is missing or not `rig:`-scoped, or the rig is not
registered, stop and report it instead of guessing a directory. Use the
authoritative worktree recorded on the source anchor, run `cd "$WORKTREE"`, and
verify `pwd -P` equals `$WORKTREE` before any source read, source edit, test,
file hash, `git add`, or `git commit`.

Write or update the item summary with these schema-required body sections,
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
- `producer: {formula: do-work-item, stage: implement-item, attempt: <positive integer>}`
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

Artifact validation: this step is gated by the pack-owned `build-artifact-valid.sh` check, which validates the summary recorded at `gc.implementation.summary_path` (fallbacks `gc.build.implementation_summary_path`, then `gc.var.summary_path`) against schema `gc.build.implementation-summary.v1`. Before closing this step, resolve the launcher rig root with this pack's resolver, `"$(dirname "<gc.check_path>")/../launcher-root.sh" <workflow-root-id>` (it reads the root's `gc.root_store_ref`, never `gc.work_dir`, and fails closed on exit 1 or 75: do not guess a directory, and do not set `gc.outcome=pass`; record its message on this step and close the step with `gc.outcome=fail`). If a city or pack layer shadows the validator so that no `launcher-root.sh` sits beside `gc.check_path`, apply the same rule by hand: the launcher rig root is the registered path of the rig named by the workflow root bead's `gc.root_store_ref` (`rig:<rig-name>`): `$GC_RIG_ROOT` when `$GC_RIG` equals `<rig-name>`, otherwise the `path` of the `<rig-name>` entry in `gc rig list --json` that is not the city's own `hq` entry; the result must be an absolute existing directory. Do not read it from `gc.work_dir` and do not use `$(pwd)`; if the reference is missing or not `rig:`-scoped, or the rig is not registered, stop and report it instead of guessing a directory, closing the step with `gc.outcome=fail`. Then run the same validator locally from that rig root. The validator is the script recorded as `gc.check_path` on the validation loop control bead (the dependent of this step bead whose `gc.kind` is `ralph`); Gas City resolves it to this pack's own `build-artifact-valid.sh` asset, so nothing has to be copied into the rig. Run `GC_BEAD_ID=<claimed-step-id> GC_RIG_ROOT=<launcher-rig-root> "<gc.check_path>"`; fix every reported validation error before setting `gc.outcome=pass`. On repair attempts (`gc.attempt` greater than 1), read the validator errors from `gc.attempt_log` on the validation loop control bead (the dependent of this step bead) and repair the summary in place instead of rewriting it. Two bounded repair attempts follow the first failure; exhausting them closes this stage with `gc.outcome=fail` and machine-readable validation errors that block downstream stages. Never ask questions in headless mode; record unresolved ambiguity inside the summary.