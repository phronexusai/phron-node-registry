# phron-node-registry

Public index and GitHub Release assets for prebuilt **Phron** node binaries (`phron`) on supported platforms. This tree is the catalog plus published archives, not the node source.

## Install

Linux (detects the platform, verifies the archive, seeds Phron’s folders):

```bash
curl -fsSL https://raw.githubusercontent.com/phronexusai/phron-node-registry/main/scripts/install.sh | bash
```

## Index

[`versions.json`](./versions.json) — version list (`os`, `arch`, `filename`, `sha256`).

```
https://raw.githubusercontent.com/phronexusai/phron-node-registry/main/versions.json
```

Releases: https://github.com/phronexusai/phron-node-registry/releases

## Current packages

| Name | Version | OS | Arch | Asset |
|------|---------|----|------|-------|
| `phron` | `0.1.0` | linux | x86_64 | `phron-linux-x86_64.tar.gz` |

```bash
tar -xzf phron-linux-x86_64.tar.gz
./phron --help
```
