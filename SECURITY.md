# Security Policy

## Scope

This repository is an observability and diagnostics toolkit. It is not a privileged agent by default, but many deployment environments will run it as `root` to read host telemetry.

## Reporting

Please report security issues privately through GitHub security advisories or direct maintainer contact rather than opening a public issue.

## Operational Guidance

- Review scripts before running them on production hosts
- Limit write access to the textfile collector directory
- Avoid exposing raw host telemetry endpoints directly to untrusted networks

