# Chargement de .env sans sourcer ni evaluer le fichier.
#
# Sourcer un .env expose au quoting : une apostrophe ou un backtick, meme
# dans un commentaire, casse selon le shell et selon l'outil qui le lit.
# Ici chaque ligne est decoupee, jamais interpretee.
#
# Usage :  . "$(dirname "$0")/lib.sh" ; load_env

load_env() {
    envfile="${1:-.env}"
    [ -f "$envfile" ] || return 0

    while IFS= read -r line || [ -n "$line" ]; do
        # commentaires et lignes vides
        case "$line" in
            ''|\#*) continue ;;
        esac

        # doit contenir un =
        case "$line" in
            *=*) : ;;
            *) continue ;;
        esac

        key="${line%%=*}"
        val="${line#*=}"

        # espaces autour de la cle
        key="${key#"${key%%[![:space:]]*}"}"
        key="${key%"${key##*[![:space:]]}"}"

        # export eventuel en prefixe
        case "$key" in
            export\ *) key="${key#export }" ;;
        esac

        # nom de variable valide uniquement
        case "$key" in
            ''|*[!A-Za-z0-9_]*) continue ;;
            [0-9]*) continue ;;
        esac

        # espaces autour de la valeur (avant de retirer les guillemets,
        # pour que "  x  " conserve ses espaces internes si voulu)
        val="${val#"${val%%[![:space:]]*}"}"
        val="${val%"${val##*[![:space:]]}"}"

        # guillemets englobants
        case "$val" in
            \"*\") val="${val#\"}" ; val="${val%\"}" ;;
            \'*\') val="${val#\'}" ; val="${val%\'}" ;;
        esac

        export "$key=$val"
    done < "$envfile"
}

# Plafond de tokens de sortie — limite Scaleway pour glm-5.2 (400 "payload
# validation" au-dela). Point unique de verite cote client : shell.sh et
# vscode.sh en derivent CLAUDE_CODE_MAX_OUTPUT_TOKENS. Surcharge possible via
# MAX_OUTPUT_TOKENS dans .env. Le proxy garde son propre garde-fou serveur
# (custom_callbacks.py), independant par conception.
DEFAULT_MAX_OUTPUT_TOKENS=16384

# Couleurs et helpers d'affichage
BOLD=$(printf '\033[1m'); RED=$(printf '\033[31m')
GREEN=$(printf '\033[32m'); YELLOW=$(printf '\033[33m'); OFF=$(printf '\033[0m')

hr()   { printf '\n%s>> %s%s\n' "$BOLD" "$1" "$OFF"; }
ok()   { printf '%s   OK%s  %s\n' "$GREEN" "$OFF" "$1"; }
bad()  { printf '%s   KO%s  %s\n' "$RED" "$OFF" "$1"; }
warn() { printf '%s   !!%s  %s\n' "$YELLOW" "$OFF" "$1"; }
