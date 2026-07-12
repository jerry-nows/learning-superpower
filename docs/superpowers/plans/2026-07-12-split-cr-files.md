# Split CR Files Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Convert the approved 113-task ecommerce master backlog into one Markdown file per CR with a linked phase index and no duplicated task content.

**Architecture:** A repository script parses the current master plan by phase and CR heading, maps the seven approved phase headings to stable directories, writes individual task files, and replaces the master with a pointer. A validator independently checks count, IDs, fields, durations, backward dependencies, index links, and a normalized content digest.

**Tech Stack:** Python 3 standard library, Markdown, unittest, Git

## Global Constraints

- Preserve CR identifiers `CR-001` through `CR-113` exactly.
- Preserve Objective, Files, Steps, Duration, Dependencies, Parallel, and Definition of Done text exactly.
- Individual CR files are the only source of task content after migration.
- `ecommerce-cr/README.md` is the navigation index.
- The legacy master file becomes a pointer and must not retain duplicated CR bodies.
- Generated ordering is deterministic and rerunning the tool is idempotent.

---

### Task 1: Splitter Parser and Phase Mapping

**Files:**
- Create: `scripts/split_cr_plan.py`
- Create: `scripts/tests/test_split_cr_plan.py`

**Interfaces:**
- Consumes: `Path` to the approved master Markdown.
- Produces: `parse_master(text) -> tuple[list[Phase], str]`, where each `Phase` owns ordered `CRTask` values and the second value is the original Summary section.

- [ ] **Step 1: Write parser tests**

Test a two-phase fixture, exact CR body preservation, summary extraction, unknown phase rejection, duplicate-ID rejection, and non-sequential-ID rejection using `unittest` and `tempfile`.

- [ ] **Step 2: Run the focused test and verify failure**

Run: `python3 -m unittest scripts.tests.test_split_cr_plan -v`

Expected: FAIL because `scripts.split_cr_plan` does not exist.

- [ ] **Step 3: Implement immutable parser models and parser**

Implement frozen `CRTask` and `Phase` dataclasses, the exact phase-to-directory map below, and regex-based heading boundaries:

```python
PHASE_DIRECTORIES = {
    "Phase 1 — Repository and Local Infrastructure": "phase-01-foundation",
    "Phase 2 — iOS Workspace and Shared Platform": "phase-02-ios-platform",
    "Phase 3 — Authentication End to End": "phase-03-authentication",
    "Phase 4 — Catalog, Search and Cache": "phase-04-catalog",
    "Phase 5 — Product Detail and Connectivity": "phase-05-product-detail",
    "Phase 6 — Cart, COD Orders and Kafka": "phase-06-cart-checkout",
    "Phase 7 — Contracts, Hardening, Tests and CI": "phase-07-quality-ci",
}
```

The parser must retain each CR block byte-for-byte after normalizing only a single trailing newline.

- [ ] **Step 4: Run parser tests**

Run: `python3 -m unittest scripts.tests.test_split_cr_plan -v`

Expected: all parser cases pass.

- [ ] **Step 5: Commit**

```bash
git add scripts/split_cr_plan.py scripts/tests/test_split_cr_plan.py
git commit -m "test: add CR plan parser"
```

### Task 2: Deterministic File and Index Generation

**Files:**
- Modify: `scripts/split_cr_plan.py`
- Modify: `scripts/tests/test_split_cr_plan.py`

**Interfaces:**
- Consumes: parser output from Task 1.
- Produces: `write_split_plan(source: Path, target: Path) -> None`, 113 `CR-NNN.md` files, `README.md`, and a legacy pointer.

- [ ] **Step 1: Write generation tests**

Using a temporary directory, assert exact phase paths, task filenames, relative README links, summary preservation, legacy pointer content, idempotent second run, and removal of stale generated `CR-*.md` files.

- [ ] **Step 2: Run tests and verify generation assertions fail**

Run: `python3 -m unittest scripts.tests.test_split_cr_plan -v`

Expected: FAIL because `write_split_plan` is undefined.

- [ ] **Step 3: Implement generation**

Each CR file must have this exact envelope:

```markdown
# CR-NNN

<!-- phase: phase-NN-name -->

[Preserved fields and body without the former `### CR-NNN` heading]
```

Generate the index using relative links grouped under the original phase headings. Append the preserved Summary and Duration Verification sections. Replace the source file with:

```markdown
# Ecommerce CR Execution Plan

The execution backlog has moved to [ecommerce-cr/README.md](ecommerce-cr/README.md).

Individual CR files are the source of truth.
```

- [ ] **Step 4: Run generation tests twice**

Run: `python3 -m unittest scripts.tests.test_split_cr_plan -v && python3 -m unittest scripts.tests.test_split_cr_plan -v`

Expected: both runs pass and produce identical trees.

- [ ] **Step 5: Commit**

```bash
git add scripts/split_cr_plan.py scripts/tests/test_split_cr_plan.py
git commit -m "feat: generate individual CR files"
```

### Task 3: Independent CR Tree Validator

**Files:**
- Create: `scripts/validate_cr_plan.py`
- Create: `scripts/tests/test_validate_cr_plan.py`

**Interfaces:**
- Consumes: `docs/superpowers/plans/ecommerce-cr`.
- Produces: exit 0 and `validated 113 CR files` only when every approved invariant holds.

- [ ] **Step 1: Write validator failure tests**

Create valid temporary trees, then independently mutate them to test missing ID, duplicate heading, missing field, invalid duration, forward dependency, broken README link, and non-contiguous IDs.

- [ ] **Step 2: Run tests and verify failure**

Run: `python3 -m unittest scripts.tests.test_validate_cr_plan -v`

Expected: FAIL because the validator module does not exist.

- [ ] **Step 3: Implement validator**

Use only `pathlib`, `re`, and `sys`. Validate exactly 113 files, filenames/headings `CR-001...CR-113`, all seven bold field labels, durations in `{5m, 10m, 15m}`, dependencies lower than the current ID, and every Markdown link target in README. Aggregate all violations before returning non-zero.

- [ ] **Step 4: Run validator tests**

Run: `python3 -m unittest scripts.tests.test_validate_cr_plan -v`

Expected: every isolated corruption case is rejected with a descriptive message.

- [ ] **Step 5: Commit**

```bash
git add scripts/validate_cr_plan.py scripts/tests/test_validate_cr_plan.py
git commit -m "test: validate split CR plan"
```

### Task 4: Execute Migration and Verify Content Preservation

**Files:**
- Modify: `docs/superpowers/plans/2026-07-12-ecommerce-cr-execution-plan.md`
- Create: `docs/superpowers/plans/ecommerce-cr/README.md`
- Create: `docs/superpowers/plans/ecommerce-cr/phase-*/CR-*.md`

**Interfaces:**
- Consumes: Tasks 1-3 and the committed approved master plan.
- Produces: the approved split documentation tree.

- [ ] **Step 1: Capture source invariants**

Run a read-only script that records the ordered CR IDs, each normalized CR body SHA-256, summary text, total count, and total duration from `HEAD:docs/superpowers/plans/2026-07-12-ecommerce-cr-execution-plan.md`.

- [ ] **Step 2: Run the splitter**

Run:

```bash
python3 scripts/split_cr_plan.py \
  docs/superpowers/plans/2026-07-12-ecommerce-cr-execution-plan.md \
  docs/superpowers/plans/ecommerce-cr
```

Expected: seven phase directories, one README, and 113 CR files are written.

- [ ] **Step 3: Run independent validation**

Run: `python3 scripts/validate_cr_plan.py docs/superpowers/plans/ecommerce-cr`

Expected: `validated 113 CR files`.

- [ ] **Step 4: Verify source-to-target digest equality and idempotence**

Reconstruct ordered normalized CR bodies from the split files, compare every SHA-256 with the captured source values, rerun the splitter, and assert `git diff` is unchanged after the second run.

- [ ] **Step 5: Commit the split tree**

```bash
git add docs/superpowers/plans/2026-07-12-ecommerce-cr-execution-plan.md docs/superpowers/plans/ecommerce-cr
git commit -m "docs: split ecommerce backlog into CR files"
```

## Completion Gate

Run:

```bash
python3 -m unittest discover -s scripts/tests -v
python3 scripts/validate_cr_plan.py docs/superpowers/plans/ecommerce-cr
find docs/superpowers/plans/ecommerce-cr -name 'CR-*.md' | wc -l
git diff --check
git status --short
```

Expected: all tests pass, validator reports 113 files, count is 113, whitespace check is clean, and no unintended file remains.
