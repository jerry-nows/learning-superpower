from __future__ import annotations

from pathlib import Path
import tempfile
import unittest

from scripts.validate_cr_plan import validate_tree


def task_document(identifier: str, dependency: str) -> str:
    return f"""# {identifier}

<!-- phase: phase-01-foundation -->

**Objective:** Validate {identifier}.

**Files:** `file.md`

**Steps:**

1. Run validation.

**Duration:** 5m

**Dependencies:** {dependency}

**Parallel:** No

**Definition of Done:** {identifier} is valid.
"""


def create_valid_tree(root: Path) -> None:
    phase = root / "phase-01-foundation"
    phase.mkdir(parents=True)
    links: list[str] = []
    for number in range(1, 114):
        identifier = f"CR-{number:03d}"
        dependency = "None" if number == 1 else f"CR-{number - 1:03d}"
        (phase / f"{identifier}.md").write_text(task_document(identifier, dependency))
        links.append(f"- [{identifier}](phase-01-foundation/{identifier}.md)")
    (root / "README.md").write_text("# Index\n\n" + "\n".join(links) + "\n")


class ValidateTreeTests(unittest.TestCase):
    def test_accepts_valid_tree(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            create_valid_tree(root)

            self.assertEqual(validate_tree(root), [])

    def test_rejects_each_broken_invariant(self) -> None:
        mutations = {
            "missing ID": lambda root: (root / "phase-01-foundation" / "CR-113.md").unlink(),
            "duplicate heading": lambda root: (root / "phase-01-foundation" / "CR-002.md").write_text(
                task_document("CR-001", "CR-001")
            ),
            "missing field": lambda root: self._replace(root, "CR-003", "**Parallel:** No\n\n", ""),
            "invalid duration": lambda root: self._replace(root, "CR-004", "**Duration:** 5m", "**Duration:** 20m"),
            "forward dependency": lambda root: self._replace(root, "CR-005", "**Dependencies:** CR-004", "**Dependencies:** CR-006"),
            "broken README link": lambda root: self._replace_readme(root, "CR-006.md", "missing.md"),
            "non-contiguous filename": lambda root: (root / "phase-01-foundation" / "CR-007.md").rename(
                root / "phase-01-foundation" / "CR-999.md"
            ),
        }
        for expected, mutate in mutations.items():
            with self.subTest(expected), tempfile.TemporaryDirectory() as temporary_directory:
                root = Path(temporary_directory)
                create_valid_tree(root)
                mutate(root)

                self.assertTrue(validate_tree(root), expected)

    @staticmethod
    def _replace(root: Path, identifier: str, old: str, new: str) -> None:
        path = root / "phase-01-foundation" / f"{identifier}.md"
        path.write_text(path.read_text().replace(old, new))

    @staticmethod
    def _replace_readme(root: Path, old: str, new: str) -> None:
        path = root / "README.md"
        path.write_text(path.read_text().replace(old, new))


if __name__ == "__main__":
    unittest.main()
