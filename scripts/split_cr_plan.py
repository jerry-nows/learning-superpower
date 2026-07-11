from __future__ import annotations

from dataclasses import dataclass
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
