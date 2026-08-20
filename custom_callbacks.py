"""Garde-fous cote proxy, independants du client.

Deux roles, sur une seule instance CustomLogger branchee via
``litellm_settings.callbacks`` dans config.yaml :

1. Ecretage de max_tokens a la limite Scaleway du modele (deepseek-v4-flash-0731
   = 32768, glm-5.2 = 16384). Scaleway renvoie un 400 au-dela ; certains appels
   internes de Claude Code ignorent CLAUDE_CODE_MAX_OUTPUT_TOKENS, donc on
   ecrete cote serveur, quel que soit le client.

2. Rattrapage des tool-calls fuites de DeepSeek V4 (contournement d'un bug
   Scaleway). ~15-30 % des tours, le modele emet son appel d'outil EN TEXTE au
   format ``<｜DSML｜invoke name="X"><｜DSML｜parameter ...>`` au lieu d'un
   tool-call structure : le parseur d'outils de Scaleway s'engage puis
   abandonne, et le markup passe en contenu (bloc ``text``, stop_reason
   ``end_turn``, aucun ``tool_use``). Claude Code voit du texte et n'execute
   rien. On detecte ce markup et on le reconstruit en vrai appel d'outil.
   Signale a Scaleway ; retirer quand leur parseur DeepSeek V4 sera corrige.

SCW_CAPTURE=1 : dump les requetes a outils sur stdout (docker logs) pour
rejouer un payload hors ligne. Off par defaut.
"""

import json
import os
import re
import uuid

from litellm.integrations.custom_logger import CustomLogger

# Garde-fou serveur, independant du client par conception. Defaut = limite
# Scaleway du modele servi (deepseek-v4-flash-0731 : 32768) ; surchargeable via
# SCW_MAX_COMPLETION_TOKENS (ex. si le modele ou le plafond change) sans code.
SCW_MAX_COMPLETION_TOKENS = int(os.getenv("SCW_MAX_COMPLETION_TOKENS", "32768"))

# ── Rattrapage DSML ─────────────────────────────────────────────────────────
# DeepSeek est INCOHERENT sur le format : le marqueur ｜DSML｜ (｜ = U+FF5C,
# token special DeepSeek) est present ou non, independamment, sur chaque balise
# ouvrante/fermante — p. ex. ouverture "<invoke name=..." mais fermeture
# "</｜DSML｜invoke>". On rend donc ｜DSML｜ optionnel partout.
_P = "｜"
_MARK = rf"(?:{_P}DSML{_P})?"  # marqueur ｜DSML｜ optionnel
_INVOKE_RE = re.compile(
    rf"<{_MARK}invoke name=\"([^\"]+)\">(.*?)</{_MARK}invoke>", re.S
)
_PARAM_RE = re.compile(
    rf"<{_MARK}parameter name=\"([^\"]+)\"[^>]*>(.*?)</{_MARK}parameter>", re.S
)
# Indice bon marche pour decider s'il faut tenter le parsing (les deux formes
# passent par 'invoke name="'). rescue_dsml() confirme ensuite la structure.
_LEAK_HINT = 'invoke name="'


def rescue_dsml(text):
    """Extrait les appels d'outils fuites d'un texte. -> [{name, input}] (vide si rien)."""
    calls = []
    for m in _INVOKE_RE.finditer(text or ""):
        params = {pm.group(1): pm.group(2) for pm in _PARAM_RE.finditer(m.group(2))}
        calls.append({"name": m.group(1), "input": params})
    return calls


def _sse(event, obj):
    """Serialise un evenement SSE Anthropic en octets (format wire /v1/messages)."""
    return f"event: {event}\ndata: {json.dumps(obj, ensure_ascii=False)}\n\n".encode()


def _parse_sse(chunk):
    """Extrait l'objet JSON de la ligne data: d'une frame SSE (bytes/str). None sinon."""
    if isinstance(chunk, (bytes, bytearray)):
        try:
            chunk = chunk.decode("utf-8")
        except Exception:  # noqa: BLE001
            return None
    if not isinstance(chunk, str):
        return None
    obj = None
    for line in chunk.split("\n"):
        if line.startswith("data:"):
            try:
                obj = json.loads(line[5:].strip())
            except Exception:  # noqa: BLE001
                pass
    return obj


def _tool_use_sse_frames(calls, message_start_raw, usage):
    """Reconstruit un flux SSE Anthropic de tool_use a partir des appels rattrapes."""
    if message_start_raw is not None:
        yield message_start_raw
    for i, c in enumerate(calls):
        block_id = f"toolu_{uuid.uuid4().hex[:24]}"
        yield _sse("content_block_start", {
            "type": "content_block_start", "index": i,
            "content_block": {"type": "tool_use", "id": block_id, "name": c["name"], "input": {}},
        })
        yield _sse("content_block_delta", {
            "type": "content_block_delta", "index": i,
            "delta": {"type": "input_json_delta",
                      "partial_json": json.dumps(c["input"], ensure_ascii=False)},
        })
        yield _sse("content_block_stop", {"type": "content_block_stop", "index": i})
    yield _sse("message_delta", {
        "type": "message_delta",
        "delta": {"stop_reason": "tool_use", "stop_sequence": None},
        "usage": usage or {"input_tokens": 0, "output_tokens": 0},
    })
    yield _sse("message_stop", {"type": "message_stop"})


class ScalewayGuards(CustomLogger):
    # ── 1. Ecretage max_tokens + capture optionnelle ────────────────────────
    async def async_pre_call_hook(self, user_api_key_dict, cache, data, call_type):
        for key in ("max_tokens", "max_completion_tokens"):
            value = data.get(key)
            if isinstance(value, int) and value > SCW_MAX_COMPLETION_TOKENS:
                data[key] = SCW_MAX_COMPLETION_TOKENS
        if os.getenv("SCW_CAPTURE") and data.get("tools"):
            try:
                safe = {k: v for k, v in data.items()
                        if k not in ("api_key", "litellm_api_key")}
                blob = json.dumps(safe, ensure_ascii=False, default=str)
                print(f"===SCW_CAPTURE_BEGIN tools={len(data.get('tools') or [])} "
                      f"msgs={len(data.get('messages') or [])} bytes={len(blob)}===", flush=True)
                print(blob, flush=True)
                print("===SCW_CAPTURE_END===", flush=True)
            except Exception as exc:  # noqa: BLE001
                print(f"===SCW_CAPTURE_ERROR {exc}===", flush=True)
        return data

    # ── 2a. Rattrapage DSML — flux (ce que Claude Code utilise) ──────────────
    async def async_post_call_streaming_iterator_hook(self, user_api_key_dict, response, request_data):
        # Sur le chemin /v1/messages, les chunks sont deja des frames SSE
        # Anthropic (bytes : "event: ...\ndata: {...}\n\n"). On bufferise le
        # tour, on accumule le texte, et si le markup DSML fuite (et qu'aucun
        # vrai tool_use n'a ete emis) on remplace le tout par un flux tool_use
        # reconstruit. Cout = latence sur le tour (tours sains rejoues tels quels).
        chunks = []
        text_parts = []
        saw_tool_use = False
        message_start_raw = None
        usage = None
        async for chunk in response:
            chunks.append(chunk)
            obj = _parse_sse(chunk)
            if not obj:
                continue
            t = obj.get("type")
            if t == "message_start":
                message_start_raw = chunk
            elif t == "content_block_start":
                if (obj.get("content_block") or {}).get("type") == "tool_use":
                    saw_tool_use = True
            elif t == "content_block_delta":
                d = obj.get("delta") or {}
                if d.get("type") == "text_delta":
                    text_parts.append(d.get("text", ""))
            elif t == "message_delta":
                usage = obj.get("usage") or usage

        text = "".join(text_parts)
        if not saw_tool_use and _LEAK_HINT in text:
            calls = rescue_dsml(text)
            if calls:
                print(f"[dsml-rescue] tour fuite rattrape -> {len(calls)} tool_use "
                      f"({', '.join(c['name'] for c in calls)})", flush=True)
                for frame in _tool_use_sse_frames(calls, message_start_raw, usage):
                    yield frame
                return
        for chunk in chunks:
            yield chunk

    # ── 2b. Rattrapage DSML — non-stream (secours) ──────────────────────────
    async def async_post_call_success_hook(self, data, user_api_key_dict, response):
        try:
            content = getattr(response, "content", None)
            if content is None and isinstance(response, dict):
                content = response.get("content")
            if not isinstance(content, list):
                return response
            leaked = "".join(
                b.get("text", "") for b in content
                if isinstance(b, dict) and b.get("type") == "text"
            )
            # blocs pydantic (type != dict)
            if not leaked:
                leaked = "".join(
                    getattr(b, "text", "") for b in content
                    if getattr(b, "type", None) == "text"
                )
            if _LEAK_HINT not in leaked:
                return response
            calls = rescue_dsml(leaked)
            if not calls:
                return response
            new_blocks = [
                {"type": "tool_use", "id": f"toolu_{uuid.uuid4().hex[:24]}",
                 "name": c["name"], "input": c["input"]}
                for c in calls
            ]
            if isinstance(response, dict):
                response["content"] = new_blocks
                response["stop_reason"] = "tool_use"
            else:
                response.content = new_blocks
                if hasattr(response, "stop_reason"):
                    response.stop_reason = "tool_use"
            print(f"[dsml-rescue] non-stream rattrape -> {len(calls)} tool_use", flush=True)
        except Exception as exc:  # noqa: BLE001 - jamais casser la reponse
            print(f"[dsml-rescue] erreur non-stream ignoree : {exc}", flush=True)
        return response


proxy_handler_instance = ScalewayGuards()
