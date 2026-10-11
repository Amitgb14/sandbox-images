# sandbox-images

Sandbox images built on top of the ones [sandbox-cli](https://github.com/Amitgb14/sandbox-cli)
publishes, kept apart from it so they can be larger and change on their own.

| Image | Built on | What it is |
|---|---|---|
| `ghcr.io/<owner>/sandbox-workstation` | `sandbox-desktop` | A full XFCE desktop: files, browser, Pinta, Flatpak — [docs/workstation.md](docs/workstation.md) |

Tags follow sandbox-cli's: `:edge` from `main` (and rebuilt weekly), `:<version>`
and `:latest` from a version tag.

```sh
podman build -t localhost/sandbox-workstation:dev images/workstation
sh tests/smoke.sh localhost/sandbox-workstation:dev
```
