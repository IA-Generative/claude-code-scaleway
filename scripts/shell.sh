#!/usr/bin/env bash
# Ouvre un shell dont l'environnement pointe sur le proxy Scaleway.
# Le reste du systeme n'est pas touche : fermer ce shell suffit a revenir.
#
#   ./scripts/shell.sh                  shell dans le repo
#   ./scripts/shell.sh ~/dev/mon-projet shell dans un projet
#
# Puis, dans ce shell :  claude

set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
REPO="$PWD"

. ./scripts/lib.sh
load_env

MODEL="${MODEL:-glm-5.2}"
PROXY_PORT="${PROXY_PORT:-4000}"
PROXY_KEY="${PROXY_KEY:-sk-local-dev-1234}"
PROXY_URL="http://127.0.0.1:$PROXY_PORT"

TARGET="$(cd "${1:-$PWD}" 2>/dev/null && pwd)" \
    || { bad "Dossier introuvable : ${1:-}"; exit 1; }

if ! curl -s --max-time 3 -o /dev/null "$PROXY_URL/health/liveliness"; then
    bad "Proxy injoignable sur $PROXY_URL"
    echo "     Lance 'make proxy' dans un autre terminal."
    exit 1
fi
ok "Proxy actif sur $PROXY_URL"

export ANTHROPIC_BASE_URL="$PROXY_URL"
export ANTHROPIC_AUTH_TOKEN="$PROXY_KEY"
export ANTHROPIC_API_KEY=""
export ANTHROPIC_MODEL="$MODEL"
export ANTHROPIC_DEFAULT_SONNET_MODEL="$MODEL"
export ANTHROPIC_DEFAULT_HAIKU_MODEL="$MODEL"
export MAX_THINKING_TOKENS=0
export DISABLE_PROMPT_CACHING=1
# Scaleway plafonne max_completion_tokens a 16384 pour glm-5.2 ;
# au-dela, l'API renvoie un 400 "payload validation".
export CLAUDE_CODE_MAX_OUTPUT_TOKENS=16384

# Repere visuel pour ne pas confondre ce shell avec un shell normal
export PS1="[$MODEL] \w \$ "

ok "Shell $MODEL dans $TARGET — tape 'claude' pour demarrer, 'exit' pour sortir"
echo
cd "$TARGET" || exit 1
exec "${SHELL:-/bin/bash}" --norc -i
