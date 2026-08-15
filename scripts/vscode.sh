#!/usr/bin/env bash
# Ouvre une fenetre VS Code sur un projet bascule vers le proxy Scaleway.
#
#   ./scripts/vscode.sh                  ouvre le dossier courant
#   ./scripts/vscode.sh ~/dev/mon-projet
#   ./scripts/vscode.sh --isolated ~/dev/mon-projet
#
# L'isolation vient du fichier .claude/settings.local.json ecrit dans le
# projet cible : il ne concerne que ce projet. Les autres projets et le CLI
# restent sur le compte Anthropic.
#
# --isolated ajoute un profil VS Code dedie. A n'utiliser qu'en connaissance
# de cause : VS Code memorise l'association dossier <-> profil, et un profil
# neuf n'a aucune extension installee, Claude Code compris.

set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
REPO="$PWD"

. ./scripts/lib.sh
load_env

MODEL="${MODEL:-glm-5.2}"
PROXY_PORT="${PROXY_PORT:-4000}"
PROXY_KEY="${PROXY_KEY:-sk-local-dev-1234}"
PROXY_URL="http://127.0.0.1:$PROXY_PORT"
PROFILE="${VSCODE_PROFILE:-Scaleway-GLM}"
MAX_OUTPUT_TOKENS="${MAX_OUTPUT_TOKENS:-$DEFAULT_MAX_OUTPUT_TOKENS}"

ISOLATED=0
ARGS=""
for a in "$@"; do
    case "$a" in
        --isolated) ISOLATED=1 ;;
        *) ARGS="$a" ;;
    esac
done

TARGET="$(cd "${ARGS:-$PWD}" 2>/dev/null && pwd)" \
    || { bad "Dossier introuvable : ${ARGS:-}"; exit 1; }

command -v code >/dev/null 2>&1 || {
    bad "La commande 'code' est absente du PATH."
    echo "     VS Code > Cmd+Shift+P > \"Shell Command: Install 'code' command in PATH\""
    exit 1
}

# ---- Le proxy doit tourner ------------------------------------------
if ! curl -s --max-time 3 -o /dev/null "$PROXY_URL/health/liveliness"; then
    warn "Proxy injoignable sur $PROXY_URL."
    printf '     Le lancer maintenant en arriere-plan ? [o/N] '
    read -r rep
    case "$rep" in
        [oOyY]*)
            if [ -x "$REPO/.venv/bin/litellm" ]; then
                LITELLM="$REPO/.venv/bin/litellm"
            elif command -v litellm >/dev/null 2>&1; then
                LITELLM="litellm"
            else
                bad "LiteLLM absent. Lance 'make install'."; exit 1
            fi
            ( cd "$REPO" && nohup "$LITELLM" --config config.yaml --port "$PROXY_PORT" \
                >"$REPO/litellm.log" 2>&1 & )
            printf '     demarrage'
            for _ in $(seq 1 20); do
                sleep 1; printf '.'
                curl -s --max-time 2 -o /dev/null "$PROXY_URL/health/liveliness" && break
            done
            echo
            curl -s --max-time 3 -o /dev/null "$PROXY_URL/health/liveliness" \
                && ok "Proxy demarre (logs : litellm.log)" \
                || { bad "Le proxy n'a pas demarre. Voir litellm.log"; exit 1; }
            ;;
        *) echo "     Lance 'make proxy' dans un autre terminal, puis recommence."; exit 1 ;;
    esac
else
    ok "Proxy actif sur $PROXY_URL"
fi

# ---- Reglages Claude Code au niveau du projet cible ------------------
# C'est ce fichier qui fait tout le travail d'isolation.
SETTINGS="$TARGET/.claude/settings.local.json"
mkdir -p "$TARGET/.claude"

if [ -f "$SETTINGS" ] && ! grep -q '"ANTHROPIC_BASE_URL"' "$SETTINGS"; then
    cp "$SETTINGS" "$SETTINGS.bak"
    warn "settings.local.json existant sauvegarde en settings.local.json.bak"
fi

cat > "$SETTINGS" <<EOF
{
  "env": {
    "ANTHROPIC_BASE_URL": "$PROXY_URL",
    "ANTHROPIC_AUTH_TOKEN": "$PROXY_KEY",
    "ANTHROPIC_API_KEY": "",
    "ANTHROPIC_MODEL": "$MODEL",
    "ANTHROPIC_DEFAULT_SONNET_MODEL": "$MODEL",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "$MODEL",
    "MAX_THINKING_TOKENS": "0",
    "DISABLE_PROMPT_CACHING": "1",
    "CLAUDE_CODE_MAX_OUTPUT_TOKENS": "$MAX_OUTPUT_TOKENS"
  }
}
EOF
ok "Reglages projet ecrits : $SETTINGS"

EXCLUDE="$TARGET/.git/info/exclude"
if [ -d "$TARGET/.git" ] && [ -f "$EXCLUDE" ] \
   && ! grep -q 'settings.local.json' "$EXCLUDE" 2>/dev/null; then
    echo ".claude/settings.local.json" >> "$EXCLUDE" 2>/dev/null \
        && ok "Ajoute a .git/info/exclude"
fi

# ---- Ouverture ------------------------------------------------------
if [ "$ISOLATED" = "1" ]; then
    DATA_DIR="$HOME/.vscode-$PROFILE"
    mkdir -p "$DATA_DIR"
    warn "Mode --isolated : profil « $PROFILE », instance separee."
    warn "Ce profil n'a aucune extension. Installe Claude Code dedans,"
    warn "et retiens que VS Code associera ce dossier a ce profil."
    ok "Ouverture de $TARGET"
    code --new-window --profile "$PROFILE" --user-data-dir "$DATA_DIR" \
         "$TARGET" >/dev/null 2>&1 &
else
    ok "Ouverture de $TARGET — modele $MODEL"
    code --new-window "$TARGET" >/dev/null 2>&1 &
fi

echo
echo "Dans la fenetre : /status doit indiquer $PROXY_URL"
