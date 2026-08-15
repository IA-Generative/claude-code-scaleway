#!/usr/bin/env bash
# Ouvre une fenêtre VS Code isolée, câblée sur le proxy Scaleway.
#
#   ./scripts/vscode.sh                 ouvre le dossier courant
#   ./scripts/vscode.sh ~/dev/mon-projet
#
# Isolation obtenue :
#   - un profil VS Code dédié (extensions et réglages séparés)
#   - une instance séparée, donc un environnement propre
#   - un .claude/settings.local.json posé dans le projet ciblé
#
# Tes autres fenêtres VS Code et ton CLI `claude` continuent d'utiliser
# ton compte Anthropic normal.

set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
REPO="$PWD"

[ -f .env ] && set -a && . ./.env && set +a

MODEL="${MODEL:-glm-5.2}"
PROXY_PORT="${PROXY_PORT:-4000}"
PROXY_KEY="${PROXY_KEY:-sk-local-dev-1234}"
PROXY_URL="http://0.0.0.0:$PROXY_PORT"
PROFILE="${VSCODE_PROFILE:-Scaleway-GLM}"

TARGET="$(cd "${1:-$PWD}" 2>/dev/null && pwd)" || { echo "Dossier introuvable : ${1:-}" >&2; exit 1; }

BOLD=$'\033[1m'; RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; OFF=$'\033[0m'
ok()   { printf '%s  OK%s  %s\n' "$GREEN" "$OFF" "$1"; }
bad()  { printf '%s  KO%s  %s\n' "$RED" "$OFF" "$1"; }
warn() { printf '%s  !!%s  %s\n' "$YELLOW" "$OFF" "$1"; }

command -v code >/dev/null 2>&1 || {
  bad "La commande 'code' est absente du PATH."
  echo "     VS Code > Cmd+Shift+P > \"Shell Command: Install 'code' command in PATH\""
  exit 1
}

# ── Le proxy doit tourner ────────────────────────────────────────────
if ! curl -s --max-time 3 -o /dev/null "$PROXY_URL/health/liveliness"; then
  warn "Proxy injoignable sur $PROXY_URL."
  printf '     Le lancer maintenant en arrière-plan ? [o/N] '
  read -r rep
  case "$rep" in
    [oOyY]*)
      ( cd "$REPO" && nohup litellm --config config.yaml --port "$PROXY_PORT" \
          >"$REPO/litellm.log" 2>&1 & )
      printf '     démarrage'
      for _ in $(seq 1 20); do
        sleep 1; printf '.'
        curl -s --max-time 2 -o /dev/null "$PROXY_URL/health/liveliness" && break
      done
      echo
      curl -s --max-time 3 -o /dev/null "$PROXY_URL/health/liveliness" \
        && ok "Proxy démarré (logs : litellm.log)" \
        || { bad "Le proxy n'a pas démarré. Voir litellm.log"; exit 1; }
      ;;
    *) echo "     Lance 'make proxy' dans un autre terminal, puis recommence."; exit 1 ;;
  esac
else
  ok "Proxy actif sur $PROXY_URL"
fi

# ── Réglages Claude Code au niveau du projet ciblé ───────────────────
# C'est ce fichier qui fait le travail : il ne concerne que ce projet,
# contrairement à ~/.claude/settings.json qui est global.
SETTINGS="$TARGET/.claude/settings.local.json"
mkdir -p "$TARGET/.claude"

if [ -f "$SETTINGS" ] && ! grep -q '"ANTHROPIC_BASE_URL"' "$SETTINGS"; then
  cp "$SETTINGS" "$SETTINGS.bak"
  warn "settings.local.json existant sauvegardé en settings.local.json.bak"
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
    "DISABLE_PROMPT_CACHING": "1"
  }
}
EOF
ok "Réglages projet écrits : $SETTINGS"

# settings.local.json n'a pas vocation à être committé
EXCLUDE="$TARGET/.git/info/exclude"
if [ -d "$TARGET/.git" ] && [ -f "$EXCLUDE" ] \
   && ! grep -q 'settings.local.json' "$EXCLUDE" 2>/dev/null; then
  echo ".claude/settings.local.json" >> "$EXCLUDE" 2>/dev/null \
    && ok "Ajouté à .git/info/exclude"
fi

# ── Instance VS Code séparée ─────────────────────────────────────────
# --user-data-dir force un vrai process distinct : sans lui, `code` délègue
# à l'instance déjà ouverte et l'environnement n'est pas repris.
DATA_DIR="$HOME/.vscode-$PROFILE"
mkdir -p "$DATA_DIR"

export ANTHROPIC_BASE_URL="$PROXY_URL"
export ANTHROPIC_AUTH_TOKEN="$PROXY_KEY"
export ANTHROPIC_API_KEY=""
export ANTHROPIC_MODEL="$MODEL"

ok "Ouverture de $TARGET — profil « $PROFILE », modèle $MODEL"
code --new-window \
     --profile "$PROFILE" \
     --user-data-dir "$DATA_DIR" \
     "$TARGET" >/dev/null 2>&1 &

echo
echo "${BOLD}Dans la fenêtre :${OFF} /status doit indiquer $PROXY_URL."
echo "Si Claude Code demande une connexion, c'est que les réglages ne sont"
echo "pas pris : ferme la fenêtre et vérifie $SETTINGS."
