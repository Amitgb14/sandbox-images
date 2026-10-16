# The agentos image: the workstation image, with agents that use its desktop.
# Claude Code, Gemini CLI, opencode and Codex are already in the image (from
# the base image); this adds what lets them see and work the desktop, and the
# settings that let them work on their own:
#
#   agentos-desktop-mcp   an MCP server for the desktop: screenshots, mouse,
#                         keyboard, windows, applications, the clipboard
#   agentos-browser-mcp   Playwright's MCP server, driving the image's Chromium
#                         on that same desktop
#   agentos-acp           an agent over the Agent Client Protocol, for Studio,
#                         editors and other ACP clients outside the sandbox
#   /etc/agentos/         AGENTS.md, the agents' instructions; manifest.json,
#                         what a client such as Studio may rely on (the agents
#                         and their ACP commands, the desktop, the output
#                         directory); see docs/agentos.md
#   each agent's system-wide settings: both MCP servers, the instructions, no
#   permission prompts
#     /etc/claude-code/   managed settings, with a few deny rules
#     /etc/gemini-cli/    system settings (over the user's)
#     /etc/codex/         system config, below the user's
#     /etc/opencode/      the config OPENCODE_CONFIG names, merged over the user's
#
# The settings live in /etc, not in HOME, because `sandbox-cli agent` restores
# the agent's own login into HOME at the start of a run, and for Gemini that
# includes ~/.gemini/settings.json. No key or login is
# ever in the image.
#
# Built in CI only, on top of the workstation image from this repository.
ARG BASE=ghcr.io/amitgb14/sandbox-workstation:edge
FROM ${BASE}

# The version of the contract in /etc/agentos/manifest.json, readable from the
# image config before any sandbox exists. Raised only when something a client
# depends on changes incompatibly; keep it equal to the manifest's "contract".
LABEL io.sandbox.agentos.contract="1"

RUN apt-get update && apt-get install -y --no-install-recommends \
      # Input and windows on the X display.
      xdotool \
      wmctrl \
      xclip \
      # A virtual environment for the desktop MCP server: Debian keeps venv
      # apart from Python itself.
      python3-venv \
      # Chinese, Japanese and Korean text, which the agent meets on the web:
      # without it, those pages are rows of empty boxes in its screenshots.
      fonts-noto-cjk \
    && rm -rf /var/lib/apt/lists/*

# The desktop MCP server's Python, in its own environment, pinned.
COPY requirements.txt /opt/agentos/requirements.txt
RUN python3 -m venv /opt/agentos/venv \
    && /opt/agentos/venv/bin/pip install --no-cache-dir --disable-pip-version-check \
         -r /opt/agentos/requirements.txt

# Playwright's MCP server, pinned. It drives the image's own Chromium
# (--executable-path), so no browser is downloaded.
ARG PLAYWRIGHT_MCP=0.0.83
ENV PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1
RUN npm install --prefix /opt/agentos/browser --omit=dev --no-audit --no-fund \
      "@playwright/mcp@${PLAYWRIGHT_MCP}" \
    && /opt/agentos/browser/node_modules/.bin/playwright-mcp --help >/dev/null

# The ACP adapter (Zed's, now the ACP project's), pinned. It runs the image's
# own Claude Code (CLAUDE_CODE_EXECUTABLE, set by agentos-acp), so the copy of
# Claude Code its SDK would bring as an optional dependency is left out.
#
# The ACP project's Codex adapter, the same way: it runs the image's own codex
# (CODEX_PATH, set by agentos-acp), so the platform build of codex its
# dependency would bring is left out. Gemini CLI and opencode speak ACP
# themselves.
ARG CLAUDE_AGENT_ACP=0.84.0
ARG CODEX_ACP=2.1.1
RUN npm install --prefix /opt/agentos/acp --omit=dev --omit=optional --no-audit --no-fund \
      "@agentclientprotocol/claude-agent-acp@${CLAUDE_AGENT_ACP}" \
      "@agentclientprotocol/codex-acp@${CODEX_ACP}"

# opencode has no system-wide file of its own; this is the one it reads.
ENV OPENCODE_CONFIG=/etc/opencode/opencode.json

COPY agentos-desktop-mcp agentos-browser-mcp agentos-acp /usr/local/bin/
COPY agentos/AGENTS.md agentos/manifest.json /etc/agentos/
COPY claude/managed-settings.json claude/managed-mcp.json /etc/claude-code/
COPY gemini/settings.json /etc/gemini-cli/
COPY codex/config.toml.in /tmp/codex-config.toml.in
COPY opencode/opencode.json /etc/opencode/

# One set of instructions for every agent: Claude Code reads its CLAUDE.md,
# Gemini CLI a directory it loads context files from, opencode the path in its
# config, and Codex its config, which carries them inline.
RUN cp /etc/agentos/AGENTS.md /etc/claude-code/CLAUDE.md \
    && mkdir -p /etc/agentos/context /etc/codex \
    && cp /etc/agentos/AGENTS.md /etc/agentos/context/AGENTS.md \
    && /opt/agentos/venv/bin/python -I -c 'import json, sys; t = open(sys.argv[1]).read(); \
open(sys.argv[3], "w").write(t.replace("@INSTRUCTIONS@", json.dumps(open(sys.argv[2]).read())))' \
         /tmp/codex-config.toml.in /etc/agentos/AGENTS.md /etc/codex/config.toml \
    && rm /tmp/codex-config.toml.in

RUN chmod 0755 /usr/local/bin/agentos-desktop-mcp /usr/local/bin/agentos-browser-mcp \
      /usr/local/bin/agentos-acp \
    && chmod 0644 /etc/claude-code/* /etc/gemini-cli/* /etc/codex/* /etc/opencode/* \
         /etc/agentos/AGENTS.md /etc/agentos/manifest.json /etc/agentos/context/AGENTS.md \
    # As in the workstation image: nothing setuid or setgid, including what
    # the packages above brought.
    && find / -xdev -type f -perm /6000 -exec chmod ug-s {} +
