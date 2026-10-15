# The agentos image: the workstation image, with an agent that uses its
# desktop. Claude Code is already in the image (from the base image); this adds
# what lets it see and work the desktop, and the settings that let it work on
# its own:
#
#   agentos-desktop-mcp   an MCP server for the desktop: screenshots, mouse,
#                         keyboard, windows, applications, the clipboard
#   agentos-browser-mcp   Playwright's MCP server, driving the image's Chromium
#                         on that same desktop
#   /etc/claude-code/     managed settings: no permission prompts, a few deny
#                         rules, both MCP servers, and the agent's instructions
#
# The settings live in /etc, not in HOME, because `sandbox-cli agent` restores
# the agent's own login into HOME at the start of a run. No key or login is
# ever in the image.
#
# Built in CI only, on top of the workstation image from this repository.
ARG BASE=ghcr.io/amitgb14/sandbox-workstation:edge
FROM ${BASE}

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

COPY agentos-desktop-mcp agentos-browser-mcp /usr/local/bin/
COPY claude/managed-settings.json claude/managed-mcp.json claude/CLAUDE.md /etc/claude-code/

RUN chmod 0755 /usr/local/bin/agentos-desktop-mcp /usr/local/bin/agentos-browser-mcp \
    && chmod 0644 /etc/claude-code/* \
    # As in the workstation image: nothing setuid or setgid, including what
    # the packages above brought.
    && find / -xdev -type f -perm /6000 -exec chmod ug-s {} +
