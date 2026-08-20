# phron-node-registry

Public index and GitHub Release assets for prebuilt **Phron** node binaries (`phron`) on supported platforms. This tree is the catalog plus published archives, not the node source.

## Index

[`versions.json`](./versions.json) — version list (`os`, `arch`, `filename`, `sha256`).

```
https://raw.githubusercontent.com/phronexusai/phron-node-registry/main/versions.json
```

Releases: https://github.com/phronexusai/phron-node-registry/releases

One GitHub Release per version (`v0.1.0`, …). Platform is the **asset filename**, not the release title — later linux/darwin archives share the same tag.

## Current packages

| Name | Version | OS | Arch | Asset |
|------|---------|----|------|-------|
| `phron` | `0.1.0` | linux | x86_64 | `phron-linux-x86_64.tar.gz` |

```bash
tar -xzf phron-linux-x86_64.tar.gz
./phron --help
```
