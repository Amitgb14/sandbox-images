# The agentos image

The workstation image with an agent that uses its desktop. Give it a goal —
"open the browser, install GIMP, resize photo.png, run the tests" — and it
plans the steps, carries them out on the desktop and in the shell, checks each
one, and reports back, without stopping to ask. You can watch it work in
Studio's **Desktop** tab.

The agent is Claude Code, which every sandbox image already has. What this
image adds is what lets it see and work a desktop, and the settings that let it
work on its own:

| | What | Where |
|---|---|---|
| Desktop | An MCP server: screenshots, mouse, keyboard, windows, applications, clipboard | `agentos-desktop-mcp` |
| Browser | Playwright's MCP server, driving the image's Chromium on the same desktop | `agentos-browser-mcp` |
| Settings | No permission prompts, a few deny rules, both MCP servers, the agent's instructions | `/etc/claude-code/` |

Everything in the workstation image is here too: XFCE, Thunar, Chromium, Pinta,
Flatpak with Flathub.

## Running a task

```sh
sandbox-cli agent claude \
  --image ghcr.io/amitgb14/sandbox-agentos:edge \
  --network open --cpus 2 --memory 4096 --keep \
  -- -p "Install GIMP from Flathub, open ~/photo.png in it, scale it to 800 px wide and export it as ~/agentos-output/photo-800.png"
```

`sandbox-cli agent` restores your Claude login into the sandbox and saves it
again at the end, so the image holds no key or login. Leave out `-p "…"` to
talk to the agent instead of handing it one task. `--keep` keeps the sandbox,
and what the agent made in it, when the task ends.

To watch: `sandbox-cli studio`, the sandbox's **Desktop** tab. The agent
starts the desktop itself when it first needs it.

`sandbox-cli agent state` says whether the agent is working, waiting, idle,
done or failed; `sandbox-cli agent wait` waits for one of those.

## How it works on its own

The agent's instructions (`/etc/claude-code/CLAUDE.md`) have it plan the task
as a checklist, carry it out a step at a time, check each step — an exit status,
a file, a page, a fresh screenshot — and finish with a summary. Files it makes
for you go to `~/agentos-output/`.

It runs with no permission prompts (`bypassPermissions`). What limits it:

- **The VM.** Nothing outside the sandbox can be reached, and there is no root
  inside it: no sudo, nothing setuid.
- **The network** you give the sandbox. The command above uses `--network open`
  so the agent can install anything and browse anywhere; `--network allowlist`
  with `--allow <host>` narrows that.
- **Deny rules** (`/etc/claude-code/managed-settings.json`), which hold in every
  mode: the agent's tools may not read or change its own login (`~/.claude`) or
  remove the whole of HOME. They cover the agent's own tools, not every program
  it runs; they are a guard against mistakes and against instructions planted in
  web pages, not a security boundary — the VM is that.
- **Snapshots.** `--snapshot-every 10m` lets you go back to before a run that
  went wrong.

To approve each risky step yourself instead, start it in Claude Code's default
mode: `-- --permission-mode default` in place of `-- -p …`.

**Web pages are untrusted.** A page can contain text written to steer an
agent. The instructions tell the agent to treat page text as data, and its
login is out of its tools' reach, but with an open network it could still be
talked into sending what is in the sandbox somewhere. Keep secrets you do not
want exposed out of an agentos sandbox that browses the open web.

## The desktop tools

| Tool | |
|---|---|
| `screenshot` | the screen as a PNG, scaled to at most 1280 px wide (`AGENTOS_SCREENSHOT_WIDTH`); `save_to` also writes it, full size, to a file |
| `click`, `move_mouse`, `drag`, `scroll` | the mouse, at screenshot coordinates |
| `type_text`, `key` | the keyboard: text, and keys such as `ctrl+l` or `Return` |
| `cursor_position` | where the pointer is |
| `list_windows`, `focus_window`, `close_window`, `wait_for_window` | windows, by id or part of a title |
| `list_apps`, `open_app` | the menu's applications, Flatpak ones included |
| `open_url` | a URL or file in its default application |
| `clipboard_get`, `clipboard_set` | the clipboard's text |

They act on display `:1`, as the sandbox user. Whatever they start belongs to
the desktop session, as if started from its menu. The browser tools are
Playwright's (`browser_navigate`, `browser_snapshot`, `browser_click`, …); their
Chromium profile is in `~/.cache/agentos/browser`, so a login made in it lasts
as long as the sandbox. They refuse `file:` URLs.

## Limits

- **Only these MCP servers.** `/etc/claude-code/managed-mcp.json` decides which
  MCP servers Claude Code loads, and a managed list is exclusive: servers added
  with `claude mcp add` or a project's `.mcp.json` are not loaded.
- **Everything the workstation image cannot do,** this cannot either: no GPU, no
  sound, no FUSE ([docs/workstation.md](workstation.md#limits)).
- **Chromium says it is automated.** Pages the browser tools open carry a bar
  about an "unsupported command-line flag", which Playwright passes; it does not
  get in the way.
- **It keeps the sandbox up** while the desktop runs, as the workstation image
  does.

## Checking on a real host

`tests/agentos-smoke.sh IMAGE` checks a built image in a container: the
settings are in place, nothing is setuid, and both MCP servers work the desktop
through a real MCP client — a screenshot, the pointer, typing into a window,
starting applications, the clipboard, opening a page in the browser. It cannot
run the agent, which needs a login.

```sh
podman build --build-arg BASE=localhost/sandbox-workstation:dev \
  -t localhost/sandbox-agentos:dev images/agentos
sh tests/agentos-smoke.sh localhost/sandbox-agentos:dev
```

Checked on 2026-10-14 in a container (podman, on the workstation image): all of
the above passed.

Checked on 2026-10-15 in Firecracker guests (`--network open`, 2 CPUs, 4 GiB),
with `sandbox-cli agent claude -- -p "…"`, each task finished on its own:

| Task | Result |
|---|---|
| Open example.com, save a desktop screenshot and the page's heading | Done. Its description of the screenshot matched the image: screenshots reach the model as images. |
| Install GIMP from Flathub, open it from the desktop, save a screenshot | Done: GIMP 3.2.6, opened with `open_app`; the install needed the workstation image's `flatpak` wrapper (docs/workstation.md). |
| Clone pallets/itsdangerous, run its tests, show the report in Mousepad | Done: 297 passed; report and screenshot saved. |
| `-- --permission-mode default` | The agent's file-changing command waited for approval: the flag overrides the managed default. |

Studio's Desktop tab on a desktop the agent started: the tab used to start a
second session on it; the workstation image's `sandbox-desktop` now reuses the
running desktop (docs/workstation.md).

Not yet checked: arm64.
