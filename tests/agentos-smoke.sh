#!/bin/sh
# agentos-smoke.sh IMAGE: checks a built agentos image in a container — its
# settings are in place, nothing is setuid, and both MCP servers work the
# desktop as the sandbox user, through a real MCP client: the desktop server
# starts the desktop, takes a screenshot, types into a window, finds and starts
# applications, and uses the clipboard; the browser server opens a page.
# Last, an ACP client (tests/acp-client.py) opens a session with the agent.
#
# What it cannot check here: the agent itself, which needs a login. See
# docs/agentos.md, "Checking on a real host".
#
#   ENGINE   docker or podman (default: whichever is installed, docker first)
set -eu

image=${1:?usage: agentos-smoke.sh IMAGE}
engine=${ENGINE:-$(command -v docker >/dev/null 2>&1 && echo docker || echo podman)}
name=sandbox-agentos-smoke-$$

fail() { echo "smoke: FAIL: $*" >&2; exit 1; }
cleanup() { "$engine" rm -f "$name" >/dev/null 2>&1 || true; }
trap cleanup EXIT

echo "smoke: programs and settings"
"$engine" run --rm --user 1001:1001 "$image" sh -c '
  for p in agentos-desktop-mcp agentos-browser-mcp agentos-acp claude sandbox-desktop xdotool wmctrl xclip chromium; do
    command -v "$p" >/dev/null || { echo "missing: $p"; exit 1; }
  done
  for f in managed-settings.json managed-mcp.json CLAUDE.md; do
    test -r "/etc/claude-code/$f" || { echo "missing: /etc/claude-code/$f"; exit 1; }
  done
  /opt/agentos/venv/bin/python -I -c "
import json
s = json.load(open(\"/etc/claude-code/managed-settings.json\"))
assert s[\"permissions\"][\"defaultMode\"] == \"bypassPermissions\", s
m = json.load(open(\"/etc/claude-code/managed-mcp.json\"))
assert set(m[\"mcpServers\"]) == {\"desktop\", \"browser\"}, m
"
' || fail "a program or a setting is missing"

echo "smoke: the manifest a client reads"
label=$("$engine" image inspect -f '{{index .Config.Labels "io.sandbox.agentos.contract"}}' "$image")
"$engine" run --rm --user 1001:1001 "$image" /opt/agentos/venv/bin/python -I -c "
import json, shutil
m = json.load(open('/etc/agentos/manifest.json'))
assert str(m['contract']) == '$label', ('label', '$label', 'manifest', m['contract'])
assert m['agents'] and len({a['id'] for a in m['agents']}) == len(m['agents']), m['agents']
for a in m['agents']:
    assert {'id', 'name', 'acp', 'login', 'defaultMode'} <= set(a), a
    assert shutil.which(a['acp'][0]), ('no ACP command', a)
assert shutil.which(m['desktop']['start'][0]), m['desktop']
assert m['desktop']['vncPort'] == 5900, m['desktop']
" || fail "the manifest does not match the label or the image"

echo "smoke: no setuid or setgid files"
n=$("$engine" run --rm "$image" sh -c 'find / -xdev -type f -perm /6000 2>/dev/null | wc -l')
[ "$n" -eq 0 ] || fail "$n setuid or setgid files"

echo "smoke: the MCP servers work the desktop"
"$engine" run -d --name "$name" --user 1001:1001 "$image" sleep infinity >/dev/null
# The agent starts both servers at once; together they make one desktop.
"$engine" exec "$name" sh -c '
  agentos-desktop-mcp --ensure-desktop & agentos-desktop-mcp --ensure-desktop & wait
  sleep 3
  n=$(pgrep -u 1001 -c -x xfce4-session)
  [ "$n" -eq 1 ] || { echo "$n desktop sessions"; exit 1; }
' || fail "starting the desktop twice at once is not right"
"$engine" exec -i "$name" /opt/agentos/venv/bin/python -I - <<'EOF' || { "$engine" exec "$name" sh -c 'cat /tmp/agentos-desktop-*.log' >&2 || true; fail "the MCP servers are not right"; }
import asyncio, base64, json, os, subprocess, sys
from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client

def check(cond, what):
    if not cond:
        print(f"not right: {what}", file=sys.stderr)
        sys.exit(1)
    print(f"  ok: {what}")

def text(result):
    if result.isError:
        check(False, f"no error: {[c.text for c in result.content if c.type == 'text']}")
    return "".join(c.text for c in result.content if c.type == "text")

async def desktop():
    params = StdioServerParameters(command="/usr/local/bin/agentos-desktop-mcp", env=dict(os.environ))
    async with stdio_client(params) as (r, w), ClientSession(r, w) as s:
        await s.initialize()
        names = {t.name for t in (await s.list_tools()).tools}
        check({"screenshot", "click", "type_text", "key", "list_windows", "open_app", "clipboard_set"} <= names, "desktop tools listed")

        shot = await s.call_tool("screenshot", {})
        imgs = [c for c in shot.content if c.type == "image"]
        check(imgs and base64.b64decode(imgs[0].data)[:8] == b"\x89PNG\r\n\x1a\n", "screenshot is a PNG")
        await s.call_tool("screenshot", {"save_to": "~/agentos-output/screen.png"})
        check(open(os.path.expanduser("~/agentos-output/screen.png"), "rb").read(8) == b"\x89PNG\r\n\x1a\n", "screenshot saved to a file")

        text(await s.call_tool("move_mouse", {"x": 200, "y": 150}))
        pos = json.loads(text(await s.call_tool("cursor_position", {})))
        check(pos == {"x": 200, "y": 150}, f"the pointer moved ({pos})")

        # A window that writes what it is typed to a file.
        subprocess.Popen(["xterm", "-T", "agentos-typing", "-e", "sh", "-c", "cat > /tmp/typed"],
                         env=dict(os.environ, DISPLAY=":1"), start_new_session=True)
        text(await s.call_tool("wait_for_window", {"title": "agentos-typing", "timeout": 30}))
        text(await s.call_tool("focus_window", {"window": "agentos-typing"}))
        text(await s.call_tool("type_text", {"text": "hello agentos\n"}))
        text(await s.call_tool("key", {"keys": "ctrl+d"}))
        for _ in range(20):
            if os.path.exists("/tmp/typed") and open("/tmp/typed").read() == "hello agentos\n":
                break
            await asyncio.sleep(0.25)
        check(open("/tmp/typed").read() == "hello agentos\n", "typing reached the window")

        apps = text(await s.call_tool("list_apps", {}))
        check("Pinta" in apps and "Mousepad" in apps, "applications listed, Flatpak ones too")
        text(await s.call_tool("open_app", {"app": "Mousepad"}))
        text(await s.call_tool("wait_for_window", {"title": "Mousepad", "timeout": 30}))
        check("Mousepad" in text(await s.call_tool("list_windows", {})), "an application started")

        text(await s.call_tool("clipboard_set", {"text": "from agentos"}))
        check(text(await s.call_tool("clipboard_get", {})) == "from agentos", "the clipboard round-trips")

async def browser():
    # Playwright's server refuses file: URLs, so the page is served on loopback.
    os.makedirs("/tmp/agentos-site", exist_ok=True)
    open("/tmp/agentos-site/index.html", "w").write("<title>agentos smoke</title><h1>It works</h1>")
    subprocess.Popen([sys.executable, "-m", "http.server", "-b", "127.0.0.1", "-d", "/tmp/agentos-site", "8123"],
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
    await asyncio.sleep(1)
    params = StdioServerParameters(command="/usr/local/bin/agentos-browser-mcp", env=dict(os.environ))
    async with stdio_client(params) as (r, w), ClientSession(r, w) as s:
        await s.initialize()
        names = {t.name for t in (await s.list_tools()).tools}
        check({"browser_navigate", "browser_snapshot", "browser_click"} <= names, "browser tools listed")
        out = text(await s.call_tool("browser_navigate", {"url": "http://127.0.0.1:8123/"}))
        check("It works" in out or "agentos smoke" in out, "the browser opened a page")

asyncio.run(desktop())
asyncio.run(browser())
EOF

"$engine" exec "$name" sh -c '
  for p in Xvnc xfwm4 xfce4-panel; do
    pgrep -u 1001 -x "$p" >/dev/null || { echo "not running: $p"; exit 1; }
  done
' || fail "the desktop the MCP server started is not right"

echo "smoke: the agent answers over ACP"
# A handshake only: initialize and a new session, which starts the image's
# own Claude Code; a prompt would need a login. The session must start in
# the managed settings' mode.
out=$(python3 -I "$(dirname "$0")/acp-client.py" --handshake --timeout 90 -- \
        "$engine" exec -i "$name" agentos-acp 2>/dev/null) || fail "no ACP handshake: $out"
echo "$out" | sed 's/^/  /'
echo "$out" | grep -q "mode bypassPermissions" || fail "the ACP session is not in bypassPermissions"

# An editor sends its own project path and its own MCP servers; neither is
# here, and Claude Code refuses extra servers. agentos-acp drops them.
out=$(python3 -I "$(dirname "$0")/acp-client.py" --handshake --timeout 90 \
        --cwd /Users/someone/project --client-mcp "editor-tools=/usr/bin/true" -- \
        "$engine" exec -i "$name" agentos-acp 2>/dev/null) || fail "an editor's session request was refused: $out"
echo "  ok: an editor's path and MCP servers are handled"

echo "smoke: ok"
