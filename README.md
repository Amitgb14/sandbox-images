# sandbox-images

Sandbox images built on top of the ones [sandbox-cli](https://github.com/Amitgb14/sandbox-cli)
publishes, kept apart from it so they can be larger and change on their own.

| Image | Built on | What it is |
|---|---|---|
| `ghcr.io/<owner>/sandbox-workstation` | `sandbox-desktop` | A full XFCE desktop: files, browser, Pinta, Flatpak; OpenGL on the GPU in a sandbox given one — [docs/workstation.md](docs/workstation.md) |
| `ghcr.io/<owner>/sandbox-agentos` | `sandbox-workstation` | The workstation, with agents (Claude Code, Gemini CLI, opencode, Codex) that work its desktop on their own, Google Chrome (amd64) and passwordless sudo — [docs/agentos.md](docs/agentos.md) |
| `ghcr.io/<owner>/sandbox-cuda` | `sandbox-base` | The base image with the CUDA 13.3 compiler and runtime, for a sandbox given a GPU (`--gpus`); amd64 only — [docs/cuda.md](docs/cuda.md) |

Tags follow sandbox-cli's: `:edge` from `main` (and rebuilt weekly), `:<version>`
and `:latest` from a version tag.

```sh
podman build -t localhost/sandbox-workstation:dev images/workstation
sh tests/smoke.sh localhost/sandbox-workstation:dev

podman build --build-arg BASE=localhost/sandbox-workstation:dev \
  -t localhost/sandbox-agentos:dev images/agentos
sh tests/agentos-smoke.sh localhost/sandbox-agentos:dev

podman build -t localhost/sandbox-cuda:dev images/cuda
sh tests/cuda-smoke.sh localhost/sandbox-cuda:dev
```
