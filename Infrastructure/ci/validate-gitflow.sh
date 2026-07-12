#!/usr/bin/env bash
set -u

if [[ -z "${BASE_REF:-}" || -z "${HEAD_REF:-}" || -z "${PR_DRAFT:-}" || -z "${PR_TITLE:-}" ]]; then
  printf 'GitFlow policy error: BASE_REF, HEAD_REF, PR_DRAFT, and PR_TITLE must all be set and non-empty.\n' >&2
  exit 1
fi

if [[ "$PR_DRAFT" == "true" ]]; then
  printf 'GitFlow policy error: mark the pull request ready for review before merging.\n' >&2
  exit 1
fi

case "$BASE_REF:$HEAD_REF" in
  develop:feature/?* | main:release/?* | main:hotfix/?*)
    ;;
  *)
    printf 'GitFlow policy error: pull request route %s -> %s is not allowed. Use feature/* -> develop, release/* -> main, or hotfix/* -> main.\n' \
      "$HEAD_REF" "$BASE_REF" >&2
    exit 1
    ;;
esac

readonly conventional_title='^(feat|fix|chore|docs|test|refactor|perf|build|ci|revert)(\([a-z0-9._-]+\))?!?: .+'
if [[ ! "$PR_TITLE" =~ $conventional_title ]]; then
  printf 'GitFlow policy error: pull request title must use Conventional Commits (for example, "feat(cart): add checkout").\n' >&2
  exit 1
fi

printf 'GitFlow policy passed for %s -> %s.\n' "$HEAD_REF" "$BASE_REF"
