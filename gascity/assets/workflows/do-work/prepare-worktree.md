
Resolve and publish the isolated worktree for this item. This is infrastructure
setup only. Do not edit source files in the launcher checkout.

1. Read current step bead metadata and get `gc.root_bead_id`; hard-fail if it is
   missing. Read that do-work root with `gc bd show <root-bead-id> --json`. If
   `gc bd show --json` returns a one-element list, unwrap the first element before
   reading metadata.
2. Resolve `<source-anchor-id>` from the do-work root:
   - read root metadata `gc.input_convoy_id`; hard-fail if it is missing
   - verify `gc.input_convoy_id` matches rendered runtime convoy `{{convoy_id}}`
   - read that input convoy with `gc bd show <input-convoy-id> --json`; unwrap a
     one-element list response before reading metadata
   - if input convoy metadata has `gc.synthetic_kind=drain-unit-convoy`, use
     input convoy metadata `gc.drain_member_id`
   - do not use the synthetic drain-unit convoy id as `<source-anchor-id>`;
     hard-fail if the selected source anchor id equals the synthetic input convoy id
   - else if it has `gc.synthetic=true` (the wrapper `gc sling <item>` makes),
     use its one tracked member from `gc convoy status <input-convoy-id> --json`
     `.children` (hard-fail unless exactly one). Never use the synthetic wrapper
     convoy id as `<source-anchor-id>`; that leaves the real item open
   - otherwise use `<input-convoy-id>` as the source anchor
   - if root metadata also has `gc.drain_member_id`, it must match the selected
     drain member
   - stamp it for later steps:
     `gc bd update <root-bead-id> --set-metadata gc.source_anchor_id=<source-anchor-id>`.
     If the root already has `gc.source_anchor_id` (a retry), it must equal the
     id resolved above; hard-fail on a mismatch instead of overwriting it
3. Validate context path {{context_path}}, files ownership, and verification
   policy for the resolved source anchor.
4. Resolve the launcher rig root: the registered path of the rig named by the
   do-work root's `gc.root_store_ref` (`rig:<rig-name>`), which is
   `$GC_RIG_ROOT` when `$GC_RIG` equals `<rig-name>`, otherwise the `path` of
   the `<rig-name>` entry in `gc rig list --json` that is not the city's own
   `hq` entry; the result must be an absolute existing directory. Hard-fail if
   `gc.root_store_ref` is missing or not `rig:`-scoped, or the rig is not
   registered. Do not read it from `gc.work_dir`, which gc may leave unset or
   fill with an implementation worktree, and do not use `$(pwd)`: the session's
   working directory is a pool slot, not the rig. Then create or reuse a
   deterministic git worktree at
   `<launcher-rig-root>/worktrees/<source-anchor-id>`, based on the up-to-date
   remote default branch — never the launcher's local `HEAD`, which may be
   behind `origin`. Run the git commands below from `<launcher-rig-root>`. If
   the path is missing:
   - Resolve the remote default branch (do not hardcode `main`). Read the
     local ref first, and only touch the network if it is missing:

     ```sh
     DEFAULT_BRANCH=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||')
     if [ -z "$DEFAULT_BRANCH" ]; then
       git remote set-head origin --auto >/dev/null 2>&1 || true
       DEFAULT_BRANCH=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||')
     fi
     ```

     `refs/remotes/origin/HEAD` is written by `git clone` and refreshed by
     `git remote set-head origin --auto`. It is NOT written by `git init` plus
     `git fetch`, which is how `actions/checkout` and several of our own
     checkouts are built, so the refresh branch is load-bearing rather than
     defensive. The fetch on the next line still guarantees the base is
     current, so a stale ref costs nothing.

     If it is still empty, fail closed — do not fall back to local `HEAD`.
   - Fetch it so the base is current:
     `git fetch --prune origin "$DEFAULT_BRANCH"`.
   - Create the worktree detached at the freshly fetched tip:
     `git worktree add "$WORKTREE" --detach "origin/$DEFAULT_BRANCH"`.
   If the path exists but is not the worktree for this repository, fail closed.
5. Persist the absolute path on the source anchor with
   `gc bd update <source-anchor-id> --set-metadata work_dir=<absolute worktree path>`.
   For synthetic drain-unit convoys, never persist `work_dir` on the synthetic drain-unit convoy; the original drain member/source anchor is authoritative.
   Verify the source anchor now has `work_dir` and the root now has
   `gc.source_anchor_id=<source-anchor-id>` before closing this step with
   `gc.outcome=pass`.
