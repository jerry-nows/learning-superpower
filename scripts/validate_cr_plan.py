from __future__ import annotations

import argparse
from pathlib import Path
import re


REQUIRED_FIELDS = (
    "**Objective:**",
    "**Files:**",
    "**Steps:**",
    "**Duration:**",
    "**Dependencies:**",
    "**Parallel:**",
    "**Definition of Done:**",
)
IDENTIFIER_PATTERN = re.compile(r"CR-(\d{3})")
HEADING_PATTERN = re.compile(r"^# (CR-\d{3})$", re.MULTILINE)
DURATION_PATTERN = re.compile(r"^\*\*Duration:\*\* (\d+)m$", re.MULTILINE)
DEPENDENCY_PATTERN = re.compile(r"^\*\*Dependencies:\*\* ([^\n]+)$", re.MULTILINE)
LINK_PATTERN = re.compile(r"\[[^]]+]\(([^)]+)\)")


def validate_tree(root: Path) -> list[str]:
    errors: list[str] = []
    task_files = sorted(root.glob("phase-*/CR-*.md"))
    expected_identifiers = [f"CR-{number:03d}" for number in range(1, 114)]
    actual_identifiers = [path.stem for path in task_files]
    if len(task_files) != 113:
        errors.append(f"expected 113 CR files, found {len(task_files)}")
    if sorted(actual_identifiers) != expected_identifiers:
        errors.append("CR filenames are not contiguous from CR-001 through CR-113")

    for path in task_files:
        text = path.read_text()
        heading_match = HEADING_PATTERN.search(text)
        if heading_match is None:
            errors.append(f"{path}: missing CR heading")
        elif heading_match.group(1) != path.stem:
            errors.append(f"{path}: heading {heading_match.group(1)} does not match filename")

        for field in REQUIRED_FIELDS:
            if field not in text:
                errors.append(f"{path}: missing field {field}")

        duration_match = DURATION_PATTERN.search(text)
        if duration_match is None or int(duration_match.group(1)) not in {5, 10, 15}:
            errors.append(f"{path}: duration must be 5m, 10m, or 15m")

        current_match = IDENTIFIER_PATTERN.fullmatch(path.stem)
        dependency_match = DEPENDENCY_PATTERN.search(text)
        if current_match is not None and dependency_match is not None:
            current_number = int(current_match.group(1))
            for dependency_number in map(int, IDENTIFIER_PATTERN.findall(dependency_match.group(1))):
                if dependency_number >= current_number:
                    errors.append(f"{path}: dependency CR-{dependency_number:03d} is not earlier")

    readme = root / "README.md"
    if not readme.is_file():
        errors.append(f"{readme}: missing index")
        return errors

    linked_tasks: set[Path] = set()
    for link in LINK_PATTERN.findall(readme.read_text()):
        target = (root / link).resolve()
        if not target.is_file():
            errors.append(f"{readme}: broken link {link}")
        elif target.name.startswith("CR-"):
            linked_tasks.add(target)
    if linked_tasks != {path.resolve() for path in task_files}:
        errors.append(f"{readme}: index does not link every CR file exactly once")

    return errors


def main() -> None:
    parser = argparse.ArgumentParser(description="Validate the split ecommerce CR plan.")
    parser.add_argument("root", type=Path)
    arguments = parser.parse_args()
    errors = validate_tree(arguments.root)
    if errors:
        for error in errors:
            print(error)
        raise SystemExit(1)
    print("validated 113 CR files")


if __name__ == "__main__":
    main()
