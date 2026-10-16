# The agentos image

The workstation image with agents that use its desktop. Give it a goal —
"open the browser, install GIMP, resize photo.png, run the tests" — and it
plans the steps, carries them out on the desktop and in the shell, checks each
one, and reports back, without stopping to ask. You can watch it work in
Studio's **Desktop** tab.

The agents are those every sandbox image already has: Claude Code, Gemini CLI,
opencode and Codex. What this image adds is what lets them see and work a
desktop, and the settings that let them work on their own:

| | What | Where |
|---|---|---|
| Desktop | An MCP server: screenshots, mouse, keyboard, windows, applications, clipboard | `agentos-desktop-mcp` |
| Browser | Playwright's MCP server, driving the image's Chromium on the same desktop | `agentos-browser-mcp` |
| ACP | Each agent over the Agent Client Protocol, for Studio, editors and other clients outside the sandbox | `agentos-acp [--agent NAME]` |
| Instructions | One set for every agent: plan, act, verify, report | `/etc/agentos/AGENTS.md` |
| Settings | Per agent: both MCP servers, the instructions, no permission prompts | see [The agents](#the-agents) |
| Manifest | What a client such as Studio may rely on: agents, ACP commands, desktop, output directory | `/etc/agentos/manifest.json` |

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

## The agents

Each agent gets the same desktop and browser tools and the same instructions,
from its own system-wide settings: `sandbox-cli agent` restores each agent's
login into HOME, and Gemini's includes its user settings file, so nothing the
image sets lives there.

| Agent | Run a task | No prompts by | Settings | Over ACP |
|---|---|---|---|---|
| Claude Code | `sandbox-cli agent claude … -- -p "…"` | `bypassPermissions`, managed | `/etc/claude-code/` (managed: wins over the user's) | `agentos-acp` (the ACP project's adapter) |
| Gemini CLI | `sandbox-cli agent gemini … -- --yolo -p "…"` | `--yolo` on its command line (agentos-acp passes it); settings cannot set it | `/etc/gemini-cli/settings.json` (wins over the user's) | `agentos-acp --agent gemini` (its own `--acp` mode) |
| opencode | `sandbox-cli agent opencode … -- run "…"` | its permissions, set to allow | `/etc/opencode/opencode.json`, named by `OPENCODE_CONFIG` (over the user's) | `agentos-acp --agent opencode` (its own `acp` mode) |
| Codex | `sandbox-cli agent codex … -- exec "…"` | `approval_policy = "never"`, `sandbox_mode = "danger-full-access"` | `/etc/codex/config.toml` (below the user's `~/.codex/config.toml`) | `agentos-acp --agent codex` (the ACP project's adapter, on the image's `codex`) |

Logins are each agent's own: `sandbox-cli agent gemini --keep … -- --version`
restores Gemini's as `… claude …` does Claude's. opencode works without one, on
its free models; Gemini CLI and Codex refuse a session until they have one or
an API key (`GEMINI_API_KEY`, `OPENAI_API_KEY`).

Codex's instructions are inlined into its config at build time
(`developer_instructions`), since it reads none from a path; Gemini CLI loads
them from `/etc/agentos/context`, one of its include directories.

## From an editor, over ACP

`agentos-acp` speaks the [Agent Client Protocol](https://agentclientprotocol.com)
on stdin and stdout, so Studio's **Agent** tab, an editor such as Zed, or any
ACP client can drive an agent in a sandbox: send it a task, watch its plan and
tool calls stream back, and answer its permission requests. Without `--agent`
it is Claude Code, through the ACP project's adapter
(`@agentclientprotocol/claude-agent-acp`) on the image's own Claude Code;
`--agent gemini`, `--agent opencode` and `--agent codex` start the others
([The agents](#the-agents)). Each has the same settings, tools and instructions
as under `sandbox-cli agent`.

First make a sandbox with your login in it. `-- --version` asks the model
nothing; it only lets `sandbox-cli agent` restore the login and keep the
sandbox:

```sh
sandbox-cli agent claude --image ghcr.io/amitgb14/sandbox-agentos:edge \
  --network open --cpus 2 --memory 4096 --keep --name ws -- --version
```

Then give the client this as the agent's command:

```sh
sandbox-cli exec ws -- agentos-acp
```

In Zed, that is a custom agent in `settings.json`; it then appears under
**External Agents** in the agent panel's new-thread menu:

```json
{
  "agent_servers": {
    "AgentOS": {
      "type": "custom",
      "command": "sandbox-cli",
      "args": ["exec", "ws", "--", "agentos-acp"],
      "env": {}
    }
  }
}
```

The session starts with no permission prompts, as the managed settings say;
the client can switch it to `default` (ask), `acceptEdits`, `plan` or `auto`,
and in `default` the agent's requests come to the client to answer.

Two things in the client's session request are changed, and each is said on
stderr:

- **The client's MCP servers are dropped.** Claude Code here may use only the
  image's servers, and refuses a session that offers more; and a client's
  stdio servers are programs on the client's machine, which are not in the
  sandbox.
- **A working directory the sandbox does not have** (an editor sends its own
  project's path) becomes HOME. Clone the project into the sandbox, or ask the
  agent to.

## For clients: the manifest

A client such as Studio should not recognise an agentos sandbox by its image
name, which forks, mirrors and local builds change. Two things say what the
image offers instead:

- **The label** `io.sandbox.agentos.contract` on the image config: the contract
  version, readable before any sandbox exists.
- **`/etc/agentos/manifest.json`** in the image, read with
  `sandbox-cli exec <name> -- cat /etc/agentos/manifest.json`:

```json
{
  "contract": 1,
  "agents": [
    {"id": "claude", "name": "Claude Code", "acp": ["agentos-acp"],
     "login": "claude", "defaultMode": "bypassPermissions"},
    {"id": "gemini", "name": "Gemini CLI", "acp": ["agentos-acp", "--agent", "gemini"],
     "login": "gemini", "defaultMode": "yolo"},
    …
  ],
  "desktop": {"vncPort": 5900, "start": ["sandbox-desktop"]},
  "outputDir": "~/agentos-output"
}
```

| Field | Meaning |
|---|---|
| `contract` | The contract version, equal to the label |
| `agents[].id` | A stable id for the agent |
| `agents[].acp` | The command to `exec` for an ACP session over stdio |
| `agents[].login` | The agent name `sandbox-cli agent` restores the login for |
| `agents[].defaultMode` | The ACP session mode a new session starts in |
| `desktop.vncPort` | VNC, on the sandbox's loopback only, no password |
| `desktop.start` | Starts the desktop, or reuses a running one |
| `outputDir` | Where the agent saves files for the person, under HOME |

The contract version goes up only when something a client relies on changes
incompatibly: an entry point renamed or removed, the VNC port, the output
directory, or what `agentos-acp` does to a session. Adding an agent to the list
does not raise it; a client reads the list and shows what is there.

## How it works on its own

The agents' instructions (`/etc/agentos/AGENTS.md`) have them plan the task
as a checklist, carry it out a step at a time, check each step — an exit status,
a file, a page, a fresh screenshot — and finish with a summary. Files it makes
for you go to `~/agentos-output/`.

Each runs with no permission prompts ([The agents](#the-agents)). What limits it:

- **The VM.** Nothing outside the sandbox can be reached, and there is no root
  inside it: no sudo, nothing setuid.
- **The network** you give the sandbox. The command above uses `--network open`
  so the agent can install anything and browse anywhere; `--network allowlist`
  with `--allow <host>` narrows that.
- **Deny rules**, Claude Code's only (`/etc/claude-code/managed-settings.json`),
  which hold in every mode: its tools may not read or change its own login
  (`~/.claude`) or remove the whole of HOME. The other agents have the
  instructions' rule against reading credentials, and no enforced one. They cover the agent's own tools, not every program
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

- **Only these MCP servers, for Claude Code.** `/etc/claude-code/managed-mcp.json`
  decides which MCP servers Claude Code loads, and a managed list is exclusive:
  servers added with `claude mcp add` or a project's `.mcp.json` are not loaded.
  The other agents add the user's and a project's servers to the image's.
- **Modes in Studio.** opencode's mode (build or plan) is a session option, not
  an ACP mode, so Studio's mode menu does not offer it; it starts in build.
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
starting applications, the clipboard, opening a page in the browser — and that
an ACP client (`tests/acp-client.py`) can open a session with the agent, an
editor's kind of request included. It cannot give the agent a task, which needs
a login.

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
| Over ACP (`sandbox-cli exec ws -- agentos-acp`, `tests/acp-client.py`): open example.com, save a screenshot, give its title | Done; the plan, tool calls and answer streamed to the client. |
| Over ACP, the session switched to `default` | The agent's command came to the client as a permission request; allowed, it ran. |
| Over ACP, with an editor's project path and an MCP server of its own | The session opened in HOME with the image's two servers; without agentos-acp's changes Claude Code refused it ("You cannot dynamically configure MCP servers when an enterprise MCP config is present"). |
| Zed 1.24.2 as the ACP client: an AgentOS thread, a task reading a project file, opening example.com and saving a screenshot | Done; Zed showed each tool call and the answer. The thread opened in Bypass permissions, from the managed settings. Zed ran inside the guest for this check (on its desktop, with `agentos-acp` as the command), so the `sandbox-cli exec` hop was the one checked above. |
| The same thread switched to Manual | Zed showed the command with Yes / No; Yes, and it ran. |

Studio's Desktop tab on a desktop the agent started: the tab used to start a
second session on it; the workstation image's `sandbox-desktop` now reuses the
running desktop (docs/workstation.md).

Checked on 2026-10-16 in a container (podman), the other agents:

| Check | Result |
|---|---|
| `codex mcp list`, `gemini mcp list`, `opencode mcp list` | Each lists `desktop` and `browser` from the image's settings; Gemini and opencode connected to both. |
| `opencode debug config` | The instructions are `/etc/agentos/AGENTS.md`, edit, bash and webfetch allowed. |
| opencode over ACP, no login (its free model): open example.com, give its title, save a desktop screenshot | Done: it used the browser and desktop tools and saved the screenshot to `~/agentos-output/`. |
| Gemini CLI and Codex over ACP, no login | Both start and answer `initialize`; a session is refused until there is a login ("Gemini API key is missing or not configured", "Authentication required"). |

Not yet checked: a Gemini CLI or Codex task with a login; Zed on another
machine through `sandbox-cli exec`; arm64.
