"""Repro auto-contenue et SANS DONNEES PRIVEES du bug tool-call DeepSeek V4.

Envoie DIRECTEMENT a l'API Scaleway (/v1/chat/completions, format OpenAI natif,
pas de LiteLLM) un payload volumineux : beaucoup d'outils + longue conversation
avec appels d'outils anterieurs. Compte les tours ou le modele emet son appel
d'outil EN TEXTE (markup ｜DSML｜ / <invoke) au lieu d'un tool_calls structure.
"""
import json
import os
import sys
import urllib.request

SCW = "https://api.scaleway.ai/v1/chat/completions"
KEY = os.environ["SCW_SECRET_KEY"]
MODEL = "deepseek-v4-flash-0731"
N = int(sys.argv[1]) if len(sys.argv) > 1 else 15

# ~24 outils generiques + un outil shell, schemas realistes.
tools = [{
    "type": "function",
    "function": {
        "name": "run_shell",
        "description": "Execute a shell command and return stdout/stderr/exit code.",
        "parameters": {"type": "object", "properties": {
            "command": {"type": "string", "description": "The command to run"},
            "timeout_s": {"type": "integer", "description": "Timeout in seconds"},
        }, "required": ["command"]},
    },
}]
for i in range(24):
    tools.append({"type": "function", "function": {
        "name": f"tool_{i:02d}",
        "description": f"Utility number {i} that processes structured records for step {i}.",
        "parameters": {"type": "object", "properties": {
            "path": {"type": "string", "description": "target path"},
            "options": {"type": "array", "items": {"type": "string"}, "description": "flags"},
            "limit": {"type": "integer", "description": "max items"},
        }, "required": ["path"]},
    }})

# Longue conversation avec appels d'outils anterieurs (contexte qui declenche).
messages = [{"role": "system", "content":
             "You are an autonomous coding agent. For every system action you MUST call a "
             "tool; never write the tool call as plain text. Keep going until the task is done."}]
for turn in range(28):
    messages.append({"role": "user", "content":
                     f"Step {turn}: inspect the repository state and record progress in the log."})
    call_id = f"call_{turn:03d}"
    messages.append({"role": "assistant", "content": None, "tool_calls": [{
        "id": call_id, "type": "function",
        "function": {"name": "run_shell",
                     "arguments": json.dumps({"command": f"git status --short && echo step-{turn}"})}}]})
    messages.append({"role": "tool", "tool_call_id": call_id,
                     "content": f"On branch feature/work\n M file_{turn}.py\nstep-{turn}"})
messages.append({"role": "user", "content":
                 "Now freeze the work: call run_shell to commit everything with a multi-line "
                 "message, then verify the commit landed. Use the tool, one call."})

body = {"model": MODEL, "max_tokens": 700, "temperature": 0.7, "stream": False,
        "tools": tools, "tool_choice": "auto", "messages": messages}

payload = json.dumps(body).encode()
print(f"payload: {len(tools)} outils, {len(messages)} messages, {len(payload)} octets\n")

MARK = ("DSML", "｜", "<invoke", "invoke name=")
leaks = tool_ok = other = 0
sample = None
for i in range(N):
    try:
        req = urllib.request.Request(SCW, data=payload, headers={
            "Authorization": f"Bearer {KEY}", "Content-Type": "application/json"})
        with urllib.request.urlopen(req, timeout=120) as r:
            msg = json.load(r)["choices"][0]["message"]
        content = msg.get("content") or ""
        if any(m in content for m in MARK):
            leaks += 1
            verdict = "FUITE (tool-call en texte)"
            if sample is None:
                sample = content
        elif msg.get("tool_calls"):
            tool_ok += 1
            verdict = "tool_calls OK"
        else:
            other += 1
            verdict = "texte pur"
        print(f"  tir {i+1:2d}: {verdict}")
    except Exception as e:
        other += 1
        print(f"  tir {i+1:2d}: ERREUR {e}")

print(f"\n=== {leaks}/{N} FUITES, {tool_ok} tool_calls OK, {other} autres ===")
if sample:
    print("\n--- echantillon de contenu fuite (repr, tronque) ---")
    print(repr(sample[:400]))
