#!/usr/bin/env python3
"""acp-client.py: a small Agent Client Protocol client, for checking agentos-acp.

It starts an ACP agent as a subprocess, speaks JSON-RPC to it over stdin and
stdout (one message a line), and prints what the agent sends back: its plan,
its tool calls, its messages, and any permission it asks for.

  acp-client.py [--handshake] [--prompt TEXT] [--deny] [--timeout S] -- COMMAND...

  --handshake   initialize and open a session, then stop (no model call)
  --prompt      the task to send (default: a short one)
  --deny        refuse permission requests (default: allow once)
  --mode        switch the session to this mode first (e.g. default: ask)
  --client-mcp  NAME=COMMAND: an MCP server the client offers the session

Examples:
  acp-client.py --handshake -- docker exec -i box agentos-acp
  acp-client.py --prompt "Open example.com" -- sandbox-cli exec ws -- agentos-acp

Exits 0 when the handshake (or the prompt) ends normally, 1 otherwise.
Standard library only.
"""
import argparse
import json
import queue
import subprocess
import sys
import threading
import time


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--handshake", action="store_true")
    ap.add_argument("--prompt", default="Say hello, then list the windows open on the desktop.")
    ap.add_argument("--deny", action="store_true")
    ap.add_argument("--timeout", type=float, default=600)
    ap.add_argument("--cwd", default="/sandbox/home")
    ap.add_argument("--mode", help="switch the session to this mode first, e.g. default")
    ap.add_argument("--client-mcp", metavar="NAME=COMMAND", action="append", default=[],
                    help="an MCP server (stdio) the client offers the session")
    ap.add_argument("command", nargs="+")
    a = ap.parse_args()

    p = subprocess.Popen(a.command, stdin=subprocess.PIPE, stdout=subprocess.PIPE, bufsize=0)
    inbox = queue.Queue()

    def reader():
        for line in p.stdout:
            line = line.strip()
            if not line:
                continue
            try:
                inbox.put(json.loads(line))
            except json.JSONDecodeError:
                inbox.put({"_garbage": line.decode(errors="replace")})
        inbox.put(None)

    threading.Thread(target=reader, daemon=True).start()
    next_id = [0]
    deadline = time.time() + a.timeout

    def send(msg):
        p.stdin.write((json.dumps(msg) + "\n").encode())
        p.stdin.flush()

    def call(method, params):
        next_id[0] += 1
        rid = next_id[0]
        send({"jsonrpc": "2.0", "id": rid, "method": method, "params": params})
        while True:
            try:
                msg = inbox.get(timeout=max(0.1, deadline - time.time()))
            except queue.Empty:
                sys.exit(f"acp: no answer to {method} in time")
            if msg is None:
                sys.exit(f"acp: the agent exited during {method}")
            if "_garbage" in msg:
                sys.exit(f"acp: not JSON-RPC on stdout: {msg['_garbage'][:200]}")
            if msg.get("id") == rid and "method" not in msg:
                if "error" in msg:
                    sys.exit(f"acp: {method} failed: {json.dumps(msg['error'])[:500]}")
                return msg["result"]
            handle(msg)

    def handle(msg):
        method = msg.get("method")
        params = msg.get("params", {})
        if method == "session/update":
            u = params.get("update", {})
            kind = u.get("sessionUpdate")
            if kind == "plan":
                print("plan:")
                for e in u.get("entries", []):
                    print(f"  [{e.get('status')}] {e.get('content')}")
            elif kind == "tool_call":
                print(f"tool: {u.get('title')} ({u.get('kind')})")
            elif kind == "tool_call_update" and u.get("status") in ("completed", "failed"):
                print(f"  -> {u.get('status')}")
            elif kind == "agent_message_chunk":
                c = u.get("content", {})
                if c.get("type") == "text":
                    print(c.get("text", ""), end="", flush=True)
        elif method == "session/request_permission":
            opts = params.get("options", [])
            want = ("reject_once", "reject_always") if a.deny else ("allow_once", "allow_always")
            choice = next((o for o in opts if o.get("kind") in want), opts[0] if opts else None)
            title = params.get("toolCall", {}).get("title")
            print(f"permission asked: {title} -> {choice and choice.get('name')}")
            send({"jsonrpc": "2.0", "id": msg["id"],
                  "result": {"outcome": {"outcome": "selected", "optionId": choice["optionId"]}}})
        elif "id" in msg and method:
            # A request this client does not offer (it declares no fs or terminal).
            send({"jsonrpc": "2.0", "id": msg["id"],
                  "error": {"code": -32601, "message": f"{method} not supported"}})

    init = call("initialize", {"protocolVersion": 1, "clientCapabilities": {
        "fs": {"readTextFile": False, "writeTextFile": False}, "terminal": False}})
    print(f"initialize: protocol {init.get('protocolVersion')}, "
          f"agent {json.dumps(init.get('agentInfo', {}))}, "
          f"auth methods {[m.get('id') for m in init.get('authMethods', [])]}")
    servers = [{"name": n, "command": c, "args": [], "env": []}
               for n, c in (m.split("=", 1) for m in a.client_mcp)]
    sess = call("session/new", {"cwd": a.cwd, "mcpServers": servers})
    sid = sess["sessionId"]
    modes = sess.get("modes") or {}
    print(f"session: {sid}, mode {modes.get('currentModeId')}, "
          f"modes {[m.get('id') for m in modes.get('availableModes', [])]}")
    if a.mode:
        call("session/set_mode", {"sessionId": sid, "modeId": a.mode})
        print(f"mode set: {a.mode}")
    if a.handshake:
        p.stdin.close()
        p.wait(timeout=30)
        return
    res = call("session/prompt", {"sessionId": sid, "prompt": [{"type": "text", "text": a.prompt}]})
    print(f"\nstop reason: {res.get('stopReason')}")
    p.stdin.close()
    try:
        p.wait(timeout=30)
    except subprocess.TimeoutExpired:
        p.kill()
    sys.exit(0 if res.get("stopReason") == "end_turn" else 1)


if __name__ == "__main__":
    main()
