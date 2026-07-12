from __future__ import annotations

import unittest
from pathlib import Path
import tempfile

from scripts.split_cr_plan import parse_master, write_split_plan


def master(*, second_id: str = "CR-002", second_phase: str = "Phase 2 — iOS Workspace and Shared Platform") -> str:
    return f"""# Ecommerce CR Execution Plan

Intro.

## Phase 1 — Repository and Local Infrastructure

### CR-001

**Objective:** First.

**Files:** `one.md`

**Steps:**

1. First step.

**Duration:** 5m

**Dependencies:** None

**Parallel:** Yes

**Definition of Done:** First done.

## {second_phase}

### {second_id}

**Objective:** Second.

**Files:** `two.md`

**Steps:**

1. Second step.

**Duration:** 10m

**Dependencies:** CR-001

**Parallel:** No

**Definition of Done:** Second done.

## Summary

- **Total number of tasks:** 2

## Duration Verification

All 2 tasks are at most 15m.
"""


class ParseMasterTests(unittest.TestCase):
    def test_parses_phases_tasks_and_summary_in_order(self) -> None:
        phases, summary = parse_master(master())

        self.assertEqual([phase.directory for phase in phases], ["phase-01-foundation", "phase-02-ios-platform"])
        self.assertEqual([task.identifier for phase in phases for task in phase.tasks], ["CR-001", "CR-002"])
        self.assertIn("## Summary", summary)
        self.assertIn("## Duration Verification", summary)

    def test_preserves_task_body_exactly_with_one_trailing_newline(self) -> None:
        phases, _ = parse_master(master())

        self.assertEqual(
            phases[0].tasks[0].body,
            "**Objective:** First.\n\n**Files:** `one.md`\n\n**Steps:**\n\n1. First step.\n\n"
            "**Duration:** 5m\n\n**Dependencies:** None\n\n**Parallel:** Yes\n\n"
            "**Definition of Done:** First done.\n",
        )

    def test_rejects_unknown_phase(self) -> None:
        with self.assertRaisesRegex(ValueError, "unknown phase"):
            parse_master(master(second_phase="Phase 9 — Unknown"))

    def test_rejects_duplicate_identifier(self) -> None:
        with self.assertRaisesRegex(ValueError, "duplicate CR identifier"):
            parse_master(master(second_id="CR-001"))

    def test_rejects_non_sequential_identifier(self) -> None:
        with self.assertRaisesRegex(ValueError, "expected CR-002"):
            parse_master(master(second_id="CR-003"))


class WriteSplitPlanTests(unittest.TestCase):
    def test_writes_phase_files_index_and_pointer(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            source = root / "master.md"
            target = root / "ecommerce-cr"
            source.write_text(master())

            write_split_plan(source, target)

            first = target / "phase-01-foundation" / "CR-001.md"
            second = target / "phase-02-ios-platform" / "CR-002.md"
            self.assertTrue(first.is_file())
            self.assertTrue(second.is_file())
            self.assertTrue(first.read_text().startswith("# CR-001\n\n<!-- phase: phase-01-foundation -->\n\n**Objective:** First."))
            index = (target / "README.md").read_text()
            self.assertIn("[CR-001](phase-01-foundation/CR-001.md)", index)
            self.assertIn("[CR-002](phase-02-ios-platform/CR-002.md)", index)
            self.assertIn("## Summary", index)
            self.assertEqual(
                source.read_text(),
                "# Ecommerce CR Execution Plan\n\n"
                "The execution backlog has moved to [ecommerce-cr/README.md](ecommerce-cr/README.md).\n\n"
                "Individual CR files are the source of truth.\n",
            )

    def test_second_run_is_idempotent_and_removes_stale_cr_files(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            source = root / "master.md"
            target = root / "ecommerce-cr"
            original = master()
            source.write_text(original)
            write_split_plan(source, target)
            snapshot = {path.relative_to(root): path.read_bytes() for path in root.rglob("*.md")}
            stale = target / "phase-01-foundation" / "CR-999.md"
            stale.write_text("stale")

            source.write_text(original)
            write_split_plan(source, target)

            self.assertFalse(stale.exists())
            self.assertEqual(snapshot, {path.relative_to(root): path.read_bytes() for path in root.rglob("*.md")})


if __name__ == "__main__":
    unittest.main()
