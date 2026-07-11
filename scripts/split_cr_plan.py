from __future__ import annotations

from dataclasses import dataclass
import argparse
from pathlib import Path
import re


PHASE_DIRECTORIES = {
    "Phase 1 — Repository and Local Infrastructure": "phase-01-foundation",
    "Phase 2 — iOS Workspace and Shared Platform": "phase-02-ios-platform",
    "Phase 3 — Authentication End to End": "phase-03-authentication",
    "Phase 4 — Catalog, Search and Cache": "phase-04-catalog",
    "Phase 5 — Product Detail and Connectivity": "phase-05-product-detail",
    "Phase 6 — Cart, COD Orders and Kafka": "phase-06-cart-checkout",
    "Phase 7 — Contracts, Hardening, Tests and CI": "phase-07-quality-ci",
}

PHASE_PATTERN = re.compile(r"^## (Phase .+)$", re.MULTILINE)
TASK_PATTERN = re.compile(r"^### (CR-\d{3})$", re.MULTILINE)
SUMMARY_PATTERN = re.compile(r"^## Summary$", re.MULTILINE)
LEGACY_POINTER = (
    "# Ecommerce CR Execution Plan\n\n"
    "The execution backlog has moved to [ecommerce-cr/README.md](ecommerce-cr/README.md).\n\n"
    "Individual CR files are the source of truth.\n"
)


@dataclass(frozen=True)
class CRTask:
    identifier: str
    body: str


@dataclass(frozen=True)
class Phase:
    title: str
    directory: str
    tasks: tuple[CRTask, ...]


def _normalize_body(value: str) -> str:
    return value.strip("\n") + "\n"


def parse_master(text: str) -> tuple[list[Phase], str]:
    summary_match = SUMMARY_PATTERN.search(text)
    if summary_match is None:
        raise ValueError("missing Summary section")

    plan_text = text[: summary_match.start()]
    phase_matches = list(PHASE_PATTERN.finditer(plan_text))
    if not phase_matches:
        raise ValueError("missing phase headings")

    phases: list[Phase] = []
    identifiers: list[str] = []
    for index, phase_match in enumerate(phase_matches):
        title = phase_match.group(1)
        try:
            directory = PHASE_DIRECTORIES[title]
        except KeyError as error:
            raise ValueError(f"unknown phase: {title}") from error

        section_end = phase_matches[index + 1].start() if index + 1 < len(phase_matches) else len(plan_text)
        section = plan_text[phase_match.end() : section_end]
        task_matches = list(TASK_PATTERN.finditer(section))
        tasks: list[CRTask] = []
        for task_index, task_match in enumerate(task_matches):
            identifier = task_match.group(1)
            if identifier in identifiers:
                raise ValueError(f"duplicate CR identifier: {identifier}")
            expected = f"CR-{len(identifiers) + 1:03d}"
            if identifier != expected:
                raise ValueError(f"expected {expected}, found {identifier}")
            identifiers.append(identifier)
            body_end = task_matches[task_index + 1].start() if task_index + 1 < len(task_matches) else len(section)
            tasks.append(CRTask(identifier=identifier, body=_normalize_body(section[task_match.end() : body_end])))

        phases.append(Phase(title=title, directory=directory, tasks=tuple(tasks)))

    return phases, _normalize_body(text[summary_match.start() :])


def _task_document(phase: Phase, task: CRTask) -> str:
    return f"# {task.identifier}\n\n<!-- phase: {phase.directory} -->\n\n{task.body}"


def _index_document(phases: list[Phase], summary: str) -> str:
    lines = ["# Ecommerce CR Execution Plan", ""]
    for phase in phases:
        lines.extend((f"## {phase.title}", ""))
        for task in phase.tasks:
            lines.append(f"- [{task.identifier}]({phase.directory}/{task.identifier}.md)")
        lines.append("")
    return "\n".join(lines) + summary


def write_split_plan(source: Path, target: Path) -> None:
    source_text = source.read_text()
    if source_text == LEGACY_POINTER and (target / "README.md").is_file():
        return

    phases, summary = parse_master(source_text)
    target.mkdir(parents=True, exist_ok=True)
    for stale_file in target.glob("phase-*/CR-*.md"):
        stale_file.unlink()

    for phase in phases:
        phase_directory = target / phase.directory
        phase_directory.mkdir(parents=True, exist_ok=True)
        for task in phase.tasks:
            (phase_directory / f"{task.identifier}.md").write_text(_task_document(phase, task))

    (target / "README.md").write_text(_index_document(phases, summary))
    source.write_text(LEGACY_POINTER)


def main() -> None:
    parser = argparse.ArgumentParser(description="Split the ecommerce master CR plan into individual files.")
    parser.add_argument("source", type=Path)
    parser.add_argument("target", type=Path)
    arguments = parser.parse_args()
    write_split_plan(arguments.source, arguments.target)


if __name__ == "__main__":
    main()
