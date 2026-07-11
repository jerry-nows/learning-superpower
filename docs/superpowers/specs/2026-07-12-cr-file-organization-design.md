# CR File Organization Design

Date: 2026-07-12
Status: approved for implementation planning

## Objective

Split the ecommerce execution backlog into one Markdown file per CR so individual tasks are easier to navigate, review, assign, and update.

## Target Structure

```text
docs/superpowers/plans/ecommerce-cr/
├── README.md
├── phase-01-foundation/
├── phase-02-ios-platform/
├── phase-03-authentication/
├── phase-04-catalog/
├── phase-05-product-detail/
├── phase-06-cart-checkout/
└── phase-07-quality-ci/
```

Each phase directory contains its CR files named with the stable identifier, for example `CR-001.md`. Every CR file preserves the original Objective, Files, Steps, Duration, Dependencies, Parallel marker, and Definition of Done.

## Index and Source of Truth

`ecommerce-cr/README.md` becomes the navigation index. It lists phases and CR links in execution order, then retains the total task count, estimated duration, critical path, parallelizable tasks, and duration verification.

The existing `2026-07-12-ecommerce-cr-execution-plan.md` becomes a short pointer to the new index. CR content exists only in individual files, preventing duplicated sources from drifting.

## Validation

The split is complete only when automated checks confirm:

- exactly 113 CR files exist;
- filenames and headings cover `CR-001` through `CR-113` with no gaps or duplicates;
- every file contains all seven required fields;
- every duration remains 5m, 10m, or 15m;
- dependencies refer only to earlier CRs;
- every index link resolves;
- no CR content is lost compared with the approved master plan.
