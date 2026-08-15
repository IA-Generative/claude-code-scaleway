#!/usr/bin/env bash
# Diagnostic de la chaîne Scaleway -> LiteLLM -> Claude Code.
#
#   ./scripts/check.sh            toutes les étapes
#   ./scripts/check.sh models     liste les IDs de modèles Scaleway
#   ./scripts/check.sh tools      teste uniquement le tool calling
#   ./scripts/check.sh proxy      teste uniquement le proxy Anthropic

set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

. ./scripts/lib.sh
load_env

SCW_URL="https://api.scaleway.ai/v1"
MODEL="${MODEL:-glm-5.2}"
PROXY_PORT="${PROXY_PORT:-4000}"
PROXY_URL="${PROXY_URL:-http://127.0.0.1:$PROXY_PORT}"
PROXY_KEY="${PROXY_KEY:-sk-local-dev-1234}"

if [ -z "${SCW_SECRET_KEY:-}" ]; then
  bad "SCW_SECRET_KEY non défini. Copie .env.example en .env et remplis-le."
  exit 1
fi

# 1 — Quels modèles Scaleway sert-il réellement ?
step_models() {
  hr "1. Modèles disponibles chez Scaleway"
  local body
  body=$(curl -s --max-time 20 "$SCW_URL/models" -H "Authorization: Bearer $SCW_SECRET_KEY")
  if ! printf '%s' "$body" | python3 -c 'import sys,json; json.load(sys.stdin)["data"]' 2>/dev/null; then
    bad "Réponse inattendue — clé invalide ou projet sans accès aux Generative APIs :"
    printf '%s\n' "$body" | head -c 500; echo
    return 1
  fi
  printf '%s' "$body" | python3 -c '
import sys, json
ids = sorted(m["id"] for m in json.load(sys.stdin)["data"])
for i in ids: print("     -", i)
'
  if printf '%s' "$body" | grep -q "\"$MODEL\""; then
    ok "\"$MODEL\" est bien servi."
  else
    bad "\"$MODEL\" est absent de la liste. Corrige MODEL dans .env et config.yaml."
    return 1
  fi
}

# 2 — Le modèle répond-il en format OpenAI ?
step_chat() {
  hr "2. Appel direct Scaleway (format OpenAI)"
  local body
  body=$(curl -s --max-time 60 "$SCW_URL/chat/completions" \
    -H "Authorization: Bearer $SCW_SECRET_KEY" -H "Content-Type: application/json" \
    -d "{\"model\":\"$MODEL\",\"messages\":[{\"role\":\"user\",\"content\":\"Réponds uniquement: OK\"}],\"max_tokens\":500}")
  local txt
  txt=$(printf '%s' "$body" | python3 -c '
import sys, json
try: print(json.load(sys.stdin)["choices"][0]["message"]["content"].strip())
except Exception: pass' 2>/dev/null)
  if [ -n "$txt" ]; then ok "Réponse du modèle : $txt"
  else bad "Pas de réponse exploitable :"; printf '%s\n' "$body" | head -c 500; echo; return 1; fi
}

# 3 — LE test qui compte. Claude Code ne fait rien sans tool calling.
step_tools() {
  hr "3. Tool calling — déterminant pour Claude Code"
  local body
  body=$(curl -s --max-time 60 "$SCW_URL/chat/completions" \
    -H "Authorization: Bearer $SCW_SECRET_KEY" -H "Content-Type: application/json" \
    -d "{
      \"model\": \"$MODEL\",
      \"messages\": [{\"role\":\"user\",\"content\":\"Quelle heure est-il à Paris ? Utilise l outil.\"}],
      \"tools\": [{\"type\":\"function\",\"function\":{
        \"name\":\"get_time\",
        \"description\":\"Donne l heure courante d une ville\",
        \"parameters\":{\"type\":\"object\",\"properties\":{\"city\":{\"type\":\"string\"}},\"required\":[\"city\"]}}}],
      \"tool_choice\": \"auto\",
      \"max_tokens\": 200
    }")
  printf '%s' "$body" | python3 -c '
import sys, json
try:
    msg = json.load(sys.stdin)["choices"][0]["message"]
except Exception:
    print("PARSE_ERROR"); sys.exit()
calls = msg.get("tool_calls") or []
if calls:
    fn = calls[0]["function"]
    print("TOOLCALL", fn.get("name"), fn.get("arguments"))
else:
    print("NOCALL", (msg.get("content") or "")[:120])
' | {
    read -r verdict rest
    case "$verdict" in
      TOOLCALL) ok "tool_calls présent → $rest" ;;
      NOCALL)   bad "Aucun tool_calls. Claude Code discutera mais n'éditera aucun fichier."
                warn "Réponse texte : $rest" ; return 1 ;;
      *)        bad "Réponse illisible."; printf '%s\n' "$body" | head -c 500; echo; return 1 ;;
    esac
  }
}

# 4 — La traduction Anthropic fonctionne-t-elle ?
step_proxy() {
  hr "4. Proxy LiteLLM au format Anthropic"
  if ! curl -s --max-time 5 -o /dev/null "$PROXY_URL/health/liveliness"; then
    bad "Proxy injoignable sur $PROXY_URL"
    # Distinguer "pas demarre" de "mauvaise adresse de connexion"
    if command -v lsof >/dev/null 2>&1 && lsof -nP -iTCP:"$PROXY_PORT" -sTCP:LISTEN >/dev/null 2>&1; then
      warn "Quelque chose ecoute pourtant sur le port $PROXY_PORT :"
      lsof -nP -iTCP:"$PROXY_PORT" -sTCP:LISTEN 2>/dev/null | sed 's/^/       /'
      warn "Verifie que ANTHROPIC_BASE_URL cible 127.0.0.1 et non 0.0.0.0."
    else
      warn "Rien n'ecoute sur le port $PROXY_PORT. Lance 'make proxy' dans un autre terminal."
    fi
    return 1
  fi
  local body
  body=$(curl -s --max-time 60 -X POST "$PROXY_URL/v1/messages" \
    -H "content-type: application/json" -H "x-api-key: $PROXY_KEY" \
    -H "anthropic-version: 2023-06-01" \
    -d "{\"model\":\"$MODEL\",\"messages\":[{\"role\":\"user\",\"content\":\"Réponds uniquement: OK\"}],\"max_tokens\":500}")
  local txt
  txt=$(printf '%s' "$body" | python3 -c '
import sys, json
try:
    d = json.load(sys.stdin)
    assert d.get("type") == "message"
    print("".join(b.get("text","") for b in d.get("content",[])).strip())
except Exception: pass' 2>/dev/null)
  if [ -n "$txt" ]; then ok "Format Anthropic valide. Réponse : $txt"
  else bad "Traduction Anthropic en échec :"; printf '%s\n' "$body" | head -c 500; echo; return 1; fi

  hr "5. Endpoint count_tokens"
  local code
  code=$(curl -s --max-time 20 -o /dev/null -w "%{http_code}" -X POST "$PROXY_URL/v1/messages/count_tokens" \
    -H "content-type: application/json" -H "x-api-key: $PROXY_KEY" \
    -H "anthropic-version: 2023-06-01" \
    -d "{\"model\":\"$MODEL\",\"messages\":[{\"role\":\"user\",\"content\":\"test\"}]}")
  if [ "$code" = "200" ]; then ok "count_tokens répond 200."
  else warn "count_tokens renvoie $code — /context sera approximatif, sans gravité."; fi
}

case "${1:-all}" in
  models) step_models ;;
  chat)   step_chat ;;
  tools)  step_tools ;;
  proxy)  step_proxy ;;
  all)    step_models && step_chat; step_tools; step_proxy
          hr "Terminé"
          echo "   Si l'étape 3 est en échec, ce modèle ne convient pas à Claude Code." ;;
  *)      echo "Usage: $0 [all|models|chat|tools|proxy]"; exit 1 ;;
esac
