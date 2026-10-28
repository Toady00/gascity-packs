"""End-to-end tests for assets/scripts/launcher-root.sh.

Stages that validate build artifacts need the launcher rig root: the registered
directory of the rig the workflow was slung into. gc does not promise that root
`gc.work_dir` holds it. A pooled worker never stamps the root (the pool
ownership guard, gascity#5026), so a top-level build-basic root and a
separate-drain do-work root reach the implement stage without the key; and
when a drain member already carries a worktree, the drain copies that
implementation worktree into the child root's `gc.work_dir` (gascity#5283).
The resolver reads the root's `gc.root_store_ref` instead, which gc stamps on
every graph.v2 root, and never falls back to `gc.work_dir` or to the process
working directory. These tests run the real script with a stub `gc` on PATH
and pin each resolution branch and each refusal.
"""
from __future__ import annotations

import json
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile
import textwrap
import unittest

PACK_ROOT = pathlib.Path(__file__).resolve().parents[1]
RESOLVER = PACK_ROOT / "assets" / "scripts" / "launcher-root.sh"
GATE = PACK_ROOT / "assets" / "scripts" / "checks" / "build-artifact-valid.sh"


@unittest.skipUnless(shutil.which("bash"), "bash is required to run the resolver")
class LauncherRootResolverTests(unittest.TestCase):
    RIG = "open-mardi-gras"

    def setUp(self) -> None:
        self.tmp = pathlib.Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp, ignore_errors=True)
        self.bin = self.tmp / "bin"
        self.bin.mkdir()
        self.city = self.tmp / "city"
        self.city.mkdir()
        self.rig_root = self.tmp / "repos" / self.RIG
        self.rig_root.mkdir(parents=True)
        self.other_rig_root = self.tmp / "repos" / "other-rig"
        self.other_rig_root.mkdir(parents=True)
        # A pool slot: where the executing session actually runs. The resolver
        # must never print this.
        self.slot = self.city / ".gc" / "worktrees" / self.RIG / "slot-1"
        self.slot.mkdir(parents=True)
        # The worktree a drain member's root inherits into gc.work_dir.
        self.member_worktree = self.rig_root / "worktrees" / "omg-4el"
        self.member_worktree.mkdir(parents=True)
        os.symlink(sys.executable, self.bin / "python3")

    def write_gc_stub(
        self,
        *,
        root_metadata: dict[str, str] | None,
        rigs: list[dict[str, str]] | None = None,
        list_shape: str = "object",
        fail_show: bool = False,
        fail_rig_list: bool = False,
    ) -> None:
        """A `gc` answering `gc bd show <id> --json` and `gc rig list --json`.

        The step bead carries gc.root_bead_id; the root carries whatever the
        test puts there. `list_shape` returns the root as a one-element list,
        the other shape `gc bd show --json` produces.
        """
        step = {"id": "step-1", "metadata": {"gc.root_bead_id": "root-1"}}
        root = {"id": "root-1", "metadata": root_metadata or {}}
        root_json = json.dumps([root] if list_shape == "list" else root)
        if rigs is None:
            rigs = [
                {"name": "houston", "path": str(self.city), "hq": True},
                {"name": self.RIG, "path": str(self.rig_root)},
                {"name": "other-rig", "path": str(self.other_rig_root)},
            ]
        rig_list = json.dumps({"ok": True, "rigs": rigs})
        show_body = (
            "echo 'Error 1045 (28000): Access denied for user' >&2; exit 1"
            if fail_show
            else textwrap.dedent(f"""\
                case "$3" in
                  step-1) printf '%s\\n' {json.dumps(json.dumps(step))} ;;
                  root-1) printf '%s\\n' {json.dumps(root_json)} ;;
                  *) echo "unknown bead $3" >&2; exit 1 ;;
                esac""")
        )
        rig_body = (
            "echo 'dial tcp: connection refused' >&2; exit 1"
            if fail_rig_list
            else f"printf '%s\\n' {json.dumps(rig_list)}"
        )
        stub = self.bin / "gc"
        stub.write_text(
            "#!/usr/bin/env bash\nset -eu\n"
            'printf "%s\\n" "$*" >> "$GC_STUB_LOG"\n'
            'case "$1 $2" in\n'
            f"  'bd show') {show_body} ;;\n"
            f"  'rig list') {rig_body} ;;\n"
            '  *) echo "unexpected gc $*" >&2; exit 2 ;;\n'
            "esac\n",
            encoding="utf-8",
        )
        stub.chmod(0o755)

    def run_resolver(self, *args: str, **extra_env: str) -> subprocess.CompletedProcess[str]:
        # Shaped like an agent session: a short PATH with the stub gc and the
        # pinned python3, HOME at the city, cwd at a pool slot (never the rig),
        # and only the GC_* variables the test sets.
        bash_dir = str(pathlib.Path(shutil.which("bash")).resolve().parent)
        self.stub_log = self.tmp / "gc-calls.log"
        env = {
            "PATH": os.pathsep.join([str(self.bin), bash_dir, "/usr/bin", "/bin"]),
            "HOME": str(self.city),
            "GC_STUB_LOG": str(self.stub_log),
        }
        env.update(extra_env)
        return subprocess.run(
            ["bash", str(RESOLVER), *args],
            env=env, capture_output=True, text=True, check=False, cwd=str(self.slot),
        )

    def gc_calls(self) -> list[str]:
        return self.stub_log.read_text(encoding="utf-8").splitlines()

    def canonical(self, path: pathlib.Path) -> str:
        return str(path.resolve())

    # --- resolution branches -------------------------------------------------

    def test_resolves_registered_rig_when_root_lacks_work_dir(self) -> None:
        """Case 1 and 2: the key is absent; the launcher comes from the registry."""
        self.write_gc_stub(root_metadata={"gc.root_store_ref": f"rig:{self.RIG}"})
        result = self.run_resolver("step-1")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), self.canonical(self.rig_root))
        self.assertIn("rig list --json", self.gc_calls())

    def test_ignores_root_work_dir_holding_a_worktree(self) -> None:
        """Case 3: a drain child root whose gc.work_dir is the member worktree."""
        self.write_gc_stub(root_metadata={
            "gc.root_store_ref": f"rig:{self.RIG}",
            "gc.work_dir": str(self.member_worktree),
            "work_dir": str(self.member_worktree),
        })
        result = self.run_resolver("step-1")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), self.canonical(self.rig_root))
        self.assertNotEqual(result.stdout.strip(), self.canonical(self.member_worktree))

    def test_uses_gc_rig_root_when_gc_rig_matches(self) -> None:
        """A rig-scoped session's own environment is used without a registry call."""
        self.write_gc_stub(root_metadata={"gc.root_store_ref": f"rig:{self.RIG}"})
        result = self.run_resolver(
            "step-1", GC_RIG=self.RIG, GC_RIG_ROOT=str(self.rig_root),
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), self.canonical(self.rig_root))
        self.assertNotIn("rig list --json", self.gc_calls())

    def test_executor_rig_differing_from_owner_is_not_used(self) -> None:
        """An agent in rig B executing rig A's workflow resolves A, not B."""
        self.write_gc_stub(root_metadata={"gc.root_store_ref": f"rig:{self.RIG}"})
        result = self.run_resolver(
            "step-1", GC_RIG="other-rig", GC_RIG_ROOT=str(self.other_rig_root),
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), self.canonical(self.rig_root))
        self.assertIn("rig list --json", self.gc_calls())

    def test_city_scoped_session_without_rig_env_resolves_registry(self) -> None:
        self.write_gc_stub(root_metadata={"gc.root_store_ref": f"rig:{self.RIG}"})
        result = self.run_resolver("step-1", GC_RIG="", GC_RIG_ROOT="")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), self.canonical(self.rig_root))

    def test_accepts_root_bead_and_list_shaped_show(self) -> None:
        self.write_gc_stub(
            root_metadata={"gc.root_store_ref": f"rig:{self.RIG}"}, list_shape="list",
        )
        result = self.run_resolver("root-1")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), self.canonical(self.rig_root))

    def test_reads_bead_id_from_environment(self) -> None:
        self.write_gc_stub(root_metadata={"gc.root_store_ref": f"rig:{self.RIG}"})
        result = self.run_resolver(GC_BEAD_ID="step-1")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), self.canonical(self.rig_root))

    def test_never_prints_the_working_directory(self) -> None:
        for metadata in (
            {"gc.root_store_ref": f"rig:{self.RIG}"},
            {"gc.root_store_ref": f"rig:{self.RIG}", "gc.work_dir": str(self.slot)},
            {},
        ):
            with self.subTest(metadata=metadata):
                self.write_gc_stub(root_metadata=metadata)
                result = self.run_resolver("step-1")
                self.assertNotEqual(result.stdout.strip(), self.canonical(self.slot))
                self.assertNotIn(str(self.slot), result.stdout)

    # --- refusals -------------------------------------------------------------

    def test_missing_store_ref_fails_closed_even_with_work_dir(self) -> None:
        self.write_gc_stub(root_metadata={"gc.work_dir": str(self.rig_root)})
        result = self.run_resolver("step-1", GC_RIG=self.RIG, GC_RIG_ROOT=str(self.rig_root))
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertEqual(result.stdout, "")
        self.assertIn("no gc.root_store_ref", result.stderr)

    def test_city_and_class_scopes_fail_closed(self) -> None:
        for store_ref in ("city:houston", "class:houston/control"):
            with self.subTest(store_ref=store_ref):
                self.write_gc_stub(root_metadata={"gc.root_store_ref": store_ref})
                result = self.run_resolver("step-1")
                self.assertEqual(result.returncode, 1, result.stderr)
                self.assertEqual(result.stdout, "")
                self.assertIn("not a rig", result.stderr)

    def test_unregistered_rig_fails_closed(self) -> None:
        self.write_gc_stub(root_metadata={"gc.root_store_ref": "rig:ghost"})
        result = self.run_resolver("step-1")
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertEqual(result.stdout, "")
        self.assertIn("rig ghost", result.stderr)
        self.assertIn("not registered", result.stderr)

    def test_matching_gc_rig_root_that_is_not_a_directory_fails(self) -> None:
        self.write_gc_stub(root_metadata={"gc.root_store_ref": f"rig:{self.RIG}"})
        result = self.run_resolver(
            "step-1", GC_RIG=self.RIG, GC_RIG_ROOT=str(self.tmp / "missing"),
        )
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertEqual(result.stdout, "")
        self.assertIn("not a directory", result.stderr)

    def test_registered_path_that_is_not_a_directory_fails(self) -> None:
        self.write_gc_stub(
            root_metadata={"gc.root_store_ref": f"rig:{self.RIG}"},
            rigs=[{"name": self.RIG, "path": str(self.tmp / "gone")}],
        )
        result = self.run_resolver("step-1")
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertEqual(result.stdout, "")
        self.assertIn("not a directory", result.stderr)

    def test_missing_bead_id_is_a_usage_error(self) -> None:
        self.write_gc_stub(root_metadata={"gc.root_store_ref": f"rig:{self.RIG}"})
        result = self.run_resolver()
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn("usage", result.stderr)

    def test_unreachable_gc_exits_75(self) -> None:
        self.write_gc_stub(root_metadata=None, fail_show=True)
        result = self.run_resolver("step-1")
        self.assertEqual(result.returncode, 75, result.stderr)
        self.assertIn("gc bd show step-1 failed", result.stderr)

        self.write_gc_stub(
            root_metadata={"gc.root_store_ref": f"rig:{self.RIG}"}, fail_rig_list=True,
        )
        result = self.run_resolver("step-1")
        self.assertEqual(result.returncode, 75, result.stderr)
        self.assertIn("gc rig list --json failed", result.stderr)

    # --- layout ----------------------------------------------------------------

    def test_resolver_is_the_sibling_the_prompts_name(self) -> None:
        """Prompts locate the resolver from the validator's gc.check_path."""
        self.assertTrue(RESOLVER.is_file())
        self.assertTrue(os.access(RESOLVER, os.X_OK), "launcher-root.sh must be executable")
        named = (GATE.parent / ".." / "launcher-root.sh").resolve()
        self.assertEqual(named, RESOLVER)


if __name__ == "__main__":
    unittest.main()
