# sandbox-images

Sandbox images built on top of the ones [sandbox-cli](https://github.com/Amitgb14/sandbox-cli)
publishes, kept apart from it so they can be larger and change on their own.

| Image | Built on | What it is |
|---|---|---|
| `ghcr.io/<owner>/sandbox-workstation` | `sandbox-desktop` | A full XFCE desktop: files, browser, Pinta, Flatpak — [docs/workstation.md](docs/workstation.md) |
| `ghcr.io/<owner>/sandbox-agentos` | `sandbox-workstation` | The workstation, with agents (Claude Code, Gemini CLI, opencode, Codex) that work its desktop on their own, Google Chrome (amd64) and passwordless sudo — [docs/agentos.md](docs/agentos.md) |

Tags follow sandbox-cli's: `:edge` from `main` (and rebuilt weekly), `:<version>`
and `:latest` from a version tag.

```sh
podman build -t localhost/sandbox-workstation:dev images/workstation
sh tests/smoke.sh localhost/sandbox-workstation:dev

podman build --build-arg BASE=localhost/sandbox-workstation:dev \
  -t localhost/sandbox-agentos:dev images/agentos
sh tests/agentos-smoke.sh localhost/sandbox-agentos:dev
```
