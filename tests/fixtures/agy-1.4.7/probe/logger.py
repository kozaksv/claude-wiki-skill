#!/usr/bin/env python3
"""Diagnostic hook logger used to capture the agy CLI 1.4.7 fixtures.

Register it from a throwaway test repository's `.agents/hooks.json` (see
`hooks.json` next to this file); never from the global user profile.
It records the stdin payload and only allowlisted environment variable
*names* -- never values: hook processes inherit the full user environment,
including unrelated tokens.
"""
import json
import os
import sys
import time

ALLOWED_ENV = ("ANTIGRAVITY_CONVERSATION_ID", "ANTIGRAVITY_TRAJECTORY_ID", "ANTIGRAVITY_PROJECT_ID")
LOG_DIR = os.environ.get("PROBE_LOG_DIR") or os.path.join(os.path.dirname(os.path.abspath(__file__)), "logs")

event = sys.argv[1]
raw = sys.stdin.read()
try:
    payload = json.loads(raw)
except ValueError:
    payload = {"_raw": raw}

record = {
    "event": event,
    "t": time.time(),
    "cwd": os.getcwd(),
    "env_names": sorted(name for name in ALLOWED_ENV if name in os.environ),
    "payload": payload,
}
if event == "Stop":
    # Is the final answer already in the transcript when Stop runs?
    try:
        with open(payload["transcriptPath"], encoding="utf-8") as stream:
            lines = stream.read().splitlines()
        last = json.loads(lines[-1])
        record["transcript_tail"] = {"n": len(lines), "type": last.get("type"), "source": last.get("source"),
                                     "content_head": (last.get("content") or "")[:200]}
    except (KeyError, OSError, ValueError, IndexError) as error:
        record["transcript_tail"] = {"error": repr(error)}

os.makedirs(LOG_DIR, exist_ok=True)
with open(os.path.join(LOG_DIR, "events.jsonl"), "a", encoding="utf-8") as stream:
    stream.write(json.dumps(record, ensure_ascii=False) + "\n")

output = {}
if event == "SessionStart":
    output = {"injectSteps": [{"ephemeralMessage": "PROBE-SESSIONSTART-TOKEN-7731"}]}
elif event == "PreInvocation":
    output = {"injectSteps": [{"ephemeralMessage": "PROBE-PREINV-TOKEN-%s" % payload.get("invocationNum")}]}
elif event == "Stop":
    guard = os.path.join(LOG_DIR, "stop_guard")
    if not os.path.exists(guard):
        open(guard, "w").close()
        output = {"decision": "continue",
                  "reason": "PROBE-STOP-CONTINUE: list verbatim every message containing PROBE you can currently see, then stop."}
    else:
        output = {"decision": "allow"}
print(json.dumps(output))
