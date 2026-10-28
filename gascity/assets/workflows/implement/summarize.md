
Write the aggregate implementation summary, including selected anchors, drain
policy, item result classes, report paths, commit refs when available, and any
operator recovery instructions. Direct implement does not run gap-analysis or
review loops. Publish settings are push {{push}} and open_pr {{open_pr}}.

Write to summary_path {{summary_path}} when provided; otherwise use the default
implementation summary path for the workflow run. Update workflow root metadata
with `gc.implementation.summary_path=<absolute path>` so the optional publish
step has an explicit report path to consume. Write the summary as a
`gc.build.implementation-summary.v1` artifact.
The summary body must contain these exact schema-required `##` headings in this
order:

- `## Summary`
- `## Intended Behavior`
- `## Changed Files`
- `## Verification`
- `## Remaining Risks`

Include a Markdown coverage table. The validator only recognizes a table with
an `ID` column and a `Status` column. Use this shape:

| ID | Status |
| --- | --- |
| REQ-001 | covered |

Use mapping objects for front matter; do not use scalar shortcuts such as
`workflow: implement`. The top-level YAML shape must be:

- `schema: gc.build.implementation-summary.v1`
- `workflow: {id: <workflow-root-id>, formula: implement}`
- `methodology: {pack: gascity, name: implement}`
- `producer: {formula: implement, stage: summarize, attempt: <positive integer>}`
- `status: approved` or another schema-allowed status
- `trace: {upstream: [...], coverage: [...]}`

Trace front matter must use the validator shape exactly:

- `trace.upstream[]` entries must include `path` and `hash`; do not use
  `id`/`title`/`type` entries as the upstream shape.
- For source anchor beads, use `path: beads/<bead-id>` and `hash: bead:<bead-id>`.
  For changed files, item summaries, or upstream build artifacts, use
  repo-relative paths and scheme-qualified hashes such as `sha256:<digest>` or
  `git:<revision>`.
- If an upstream entry lists `ids`, every listed id must appear exactly once in
  `trace.coverage` and in the Markdown coverage table with the same status.
- Coverage statuses are not artifact statuses. Use `covered` for satisfied
  requirements; do not use `approved` in `trace.coverage[].status` or the
  Markdown coverage table.

Artifact validation: this step is gated by the pack-owned `build-artifact-valid.sh` check, which validates the summary recorded at `gc.implementation.summary_path` (fallback `gc.var.summary_path`) against schema `gc.build.implementation-summary.v1`. Before closing this step, resolve the launcher rig root with this pack's resolver, `"$(dirname "<gc.check_path>")/../launcher-root.sh" <workflow-root-id>` (it reads the root's `gc.root_store_ref`, never `gc.work_dir`, and fails closed on exit 1 or 75: do not guess a directory, report the message). If a city or pack layer shadows the validator so that no `launcher-root.sh` sits beside `gc.check_path`, apply the same rule by hand: the launcher rig root is the registered path of the rig named by the workflow root bead's `gc.root_store_ref` (`rig:<rig-name>`): `$GC_RIG_ROOT` when `$GC_RIG` equals `<rig-name>`, otherwise the `path` of `<rig-name>` from `gc rig list --json`. Do not read it from `gc.work_dir` and do not use `$(pwd)`; if the reference is missing or not `rig:`-scoped, or the rig is not registered, stop and report it instead of guessing a directory. Then run the same validator locally from that rig root. The validator is the script recorded as `gc.check_path` on the validation loop control bead (the dependent of this step bead whose `gc.kind` is `ralph`); Gas City resolves it to this pack's own `build-artifact-valid.sh` asset, so nothing has to be copied into the rig. Run `GC_BEAD_ID=<claimed-step-id> GC_RIG_ROOT=<launcher-rig-root> "<gc.check_path>"`; fix every reported validation error before setting `gc.outcome=pass`. On repair attempts (`gc.attempt` greater than 1), read the validator errors from `gc.attempt_log` on the validation loop control bead (the dependent of this step bead) and repair the summary in place instead of rewriting it. Two bounded repair attempts follow the first failure; exhausting them closes this stage with `gc.outcome=fail` and machine-readable validation errors that block downstream stages. Never ask questions in headless mode; record unresolved ambiguity inside the summary.
