# Release Process

This repo publishes versioned source-install bundles from Git tags matching `v*.*.*`.

## Maintainer Flow

1. Make sure `main` is green.
2. Update `CHANGELOG.md`.
3. Create and push a tag:

```bash
git tag v0.2.0
git push origin v0.2.0
```

4. GitHub Actions will:

- run `make test`
- run `make lint`
- install into `dist/ai-host-observability-<version>`
- create `ai-host-observability-<version>.tar.gz`
- generate `SHA256SUMS`
- attach both files to the GitHub Release

## Local Dry Run

```bash
make test
make lint
make install PREFIX=dist/ai-host-observability-0.2.0
tar -C dist -czf ai-host-observability-0.2.0.tar.gz ai-host-observability-0.2.0
sha256sum ai-host-observability-0.2.0.tar.gz > SHA256SUMS
```

## GPG Signing

The workflow currently does not sign release artifacts automatically. If you want signed artifacts:

```bash
gpg --armor --detach-sign ai-host-observability-0.2.0.tar.gz
gpg --armor --detach-sign SHA256SUMS
```

You can also create a clearsigned checksum manifest:

```bash
gpg --clearsign --output SHA256SUMS.asc SHA256SUMS
```

Recommended publish set:

- `ai-host-observability-<version>.tar.gz`
- `SHA256SUMS`
- optional `ai-host-observability-<version>.tar.gz.asc`
- optional `SHA256SUMS.asc`

## Verification

Consumers can verify:

```bash
sha256sum -c SHA256SUMS
gpg --verify ai-host-observability-0.2.0.tar.gz.asc ai-host-observability-0.2.0.tar.gz
```

