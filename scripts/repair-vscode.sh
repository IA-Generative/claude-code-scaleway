#!/usr/bin/env bash
# Diagnostique et repare la disparition de Claude Code dans VS Code apres
# un lancement en mode --isolated.
#
#   ./scripts/repair-vscode.sh          diagnostic seul
#   ./scripts/repair-vscode.sh --fix    propose les corrections
#
# Cause la plus frequente : la commande `code` se rattache a l'instance
# VS Code deja en cours. Si cette instance est celle lancee avec
# --user-data-dir, tous les `code .` suivants ouvrent des fenetres dans un
# environnement ou aucune extension n'est installee.

set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. ./scripts/lib.sh

EXT_ID="anthropic.claude-code"
FIX=0
[ "${1:-}" = "--fix" ] && FIX=1

# ---- 1. Une instance isolee tourne-t-elle encore ? -------------------
hr "1. Instances VS Code en cours"
STRAY=0
if pgrep -fl "Visual Studio Code" >/dev/null 2>&1 || pgrep -fl "[Cc]ode Helper" >/dev/null 2>&1; then
    if ps -Ao args= 2>/dev/null | grep -- '--user-data-dir' | grep -v grep | grep -q 'vscode-'; then
        bad "Une instance lancee avec --user-data-dir tourne encore :"
        ps -Ao args= 2>/dev/null | grep -- '--user-data-dir' | grep -v grep \
            | sed 's/^\(.\{140\}\).*/\1.../' | sed 's/^/       /' | head -3
        warn "C'est elle qui capte tes commandes 'code'."
        STRAY=1
    else
        ok "Aucune instance isolee detectee."
    fi
else
    warn "VS Code ne semble pas lance."
fi

# ---- 2. L'extension est-elle installee dans le profil par defaut ? ---
hr "2. Extension Claude Code"
if ! command -v code >/dev/null 2>&1; then
    bad "Commande 'code' absente du PATH."
    exit 1
fi

if [ "$STRAY" = "1" ]; then
    warn "Verification impossible tant que l'instance isolee tourne :"
    warn "'code --list-extensions' interrogerait cette instance."
else
    if code --list-extensions 2>/dev/null | grep -qi "^$EXT_ID$"; then
        ok "$EXT_ID est installee."
    else
        bad "$EXT_ID est absente du profil courant."
        if [ "$FIX" = "1" ]; then
            printf '     Reinstaller maintenant ? [o/N] '
            read -r rep
            case "$rep" in
                [oOyY]*) code --install-extension "$EXT_ID" && ok "Extension reinstallee." ;;
                *) echo "     Ignore." ;;
            esac
        else
            echo "     Relance avec --fix pour la reinstaller."
        fi
    fi
fi

# ---- 3. Le dossier de donnees isole ---------------------------------
hr "3. Dossier de donnees isole"
FOUND=0
for d in "$HOME"/.vscode-*; do
    [ -d "$d" ] || continue
    FOUND=1
    warn "Present : $d"
done
if [ "$FOUND" = "0" ]; then
    ok "Aucun dossier ~/.vscode-* residuel."
elif [ "$FIX" = "1" ]; then
    printf '     Supprimer ces dossiers ? [o/N] '
    read -r rep
    case "$rep" in
        [oOyY]*)
            for d in "$HOME"/.vscode-*; do
                [ -d "$d" ] && rm -rf "$d" && ok "Supprime : $d"
            done ;;
        *) echo "     Conserves." ;;
    esac
fi

# ---- 4. Marche a suivre ---------------------------------------------
hr "Marche a suivre"
cat <<'TXT'
   1. Quitter VS Code entierement : Cmd+Q sur chaque fenetre.
      Verifier qu'il ne reste rien :
        pgrep -fl "Visual Studio Code"
      Si un process persiste :
        pkill -f "Visual Studio Code"

   2. Relancer VS Code depuis le Dock ou Applications,
      PAS depuis le terminal avec `code`.

   3. Dans chaque fenetre ou Claude Code manque :
        Cmd+Shift+P > Profiles: Switch Profile > Default
      VS Code memorise le profil par dossier : chaque dossier ouvert
      en mode isole doit etre rebascule une fois.

   4. Supprimer le profil devenu inutile :
        Cmd+Shift+P > Profiles: Delete Profile > Scaleway-GLM

   5. Si l'extension manque toujours :
        code --install-extension anthropic.claude-code
TXT
