# Contributing

## Development Loop

1. Run `make lint`
2. Run `make test`
3. Run `make smoke`
4. Update `docs/metrics.md` if you add or rename metrics
5. Update `CHANGELOG.md` for user-visible changes

## Style

- Keep shell scripts Bash-only and dependency-light
- Prefer fixture-backed tests over hardware assumptions
- Do not remove metric labels without documenting the change

## Pull Requests

- Explain why a metric or alert was added
- Include before/after examples for any output-format changes
- Keep alerts conservative unless there is strong production evidence

