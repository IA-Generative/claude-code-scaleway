# Relais — état du projet

Document de passation. À jour au 16 août 2026.

## Objectif

Faire tourner Claude Code sur **GLM-5.2 servi par Scaleway Generative APIs**,
à des fins d'évaluation. Scaleway expose une API compatible OpenAI, Claude Code
parle Anthropic, LiteLLM traduit entre les deux en local.

```
Claude Code ──/v1/messages (Anthropic)──▶ LiteLLM :4000 ──/chat/completions (OpenAI)──▶ api.scaleway.ai/v1
```

## Acquis, vérifié

- `glm-5.2` est bien l'identifiant servi par Scaleway (confirmé via `/v1/models`)
- L'appel direct en format OpenAI répond
- **Le tool calling fonctionne** — `get_time {"city": "Paris"}` correctement formé.
  C'était le risque principal : sans lui, Claude Code ne peut éditer aucun fichier.
- **`make check` passe ses 5 étapes**, traduction Anthropic et `count_tokens` compris
- **Claude Code fonctionne en réel via le proxy** : sessions interactives,
  mode `-p`, usage d'outils (lecture/édition de fichiers) validés
- **Une run autonome de nuit** (orchestrateur multi-modules sur `async-api`)
  a tourné derrière la passerelle — c'est elle qui a révélé les pièges
  documentés plus bas
- **Le proxy tourne en Docker** (`make up`, image épinglée `v1.96.2`,
  `restart: unless-stopped`) — plus aucun terminal à garder ouvert
- Le port 4000 est réservé dans `owuicore-main/docker-utilise.md`
  (section 2.16 ; collision documentée avec le repo `console`)

## Reste à faire

1. **Dépouiller la run de nuit** — rapport dans
   `async-api/private/rapport-nuit-<date>-<runner-id>/`
2. **Quotas Scaleway** — la run sature le quota *tokens/minute* par défaut
   (429 `INSUFFICIENT QUOTA`), surtout quand Claude Code parallélise ;
   augmenter en console, router `claude-haiku-*` vers un modèle moins cher
   (quota séparé par modèle), et à terme viser un **déploiement dédié**
   (Managed Inference) quand disponible pour le modèle visé
3. **Merger la branche** `chore/tchap-vault-only-owui-state` d'`owuicore-main`
   pour que la réservation du port 4000 atteigne le registre officiel

## Structure

| Fichier | Rôle |
|---|---|
| `config.yaml` | Mapping LiteLLM (`hosted_vllm/glm-5.2`) + alias Claude, versions datées comprises |
| `custom_callbacks.py` | Pre-call hook : écrête `max_tokens` à 16384 (limite Scaleway) quel que soit le client |
| `docker-compose.yml` | Proxy conteneurisé, image épinglée `v1.96.2`, monte config + callbacks |
| `scripts/lib.sh` | Chargement de `.env` par découpage, sans sourcing |
| `scripts/check.sh` | Diagnostic en 5 étapes |
| `scripts/shell.sh` | Sous-shell GLM, n'écrit rien sur disque |
| `scripts/vscode.sh` | Écrit `.claude/settings.local.json` puis ouvre VS Code |
| `scripts/repair-vscode.sh` | Répare l'extension Claude Code disparue |
| `templates/settings.local.json` | À copier à la main dans un projet |
| `Makefile` | Point d'entrée, `make help` liste tout |

## Pièges déjà rencontrés — ne pas réintroduire

**`0.0.0.0` contre `127.0.0.1`.** LiteLLM écoute sur `0.0.0.0` (toutes
interfaces), mais ce n'est pas une adresse de connexion : le client Node de
Claude Code la refuse avec `ECONNREFUSED`. Toutes les URL client sont sur
`127.0.0.1`.

**Pas de commentaires dans `.env`.** Une apostrophe ou un backtick dans un
commentaire casse le quoting selon le shell et l'outil qui lit le fichier.
`scripts/lib.sh` découpe chaque ligne au lieu de sourcer, donc rien n'est
interprété — mais autant ne pas réintroduire le piège. La documentation des
variables est dans le README.

**`code --user-data-dir` est à proscrire.** La commande `code` se rattache à
l'instance VS Code déjà en cours. Lancer une instance avec `--user-data-dir`
détourne tous les `code .` suivants vers un environnement sans extensions —
Claude Code paraît désinstallé. Et VS Code mémorise l'association
dossier → profil. Le mode `--isolated` de `vscode.sh` existe encore mais n'est
plus le défaut ; ne pas le conseiller sans raison précise.

**Portée des réglages.** Ne jamais écrire `ANTHROPIC_BASE_URL` dans
`~/.claude/settings.json` : c'est global, tous les projets et le CLI
basculeraient. La portée projet (`.claude/settings.local.json`) suffit.

**Préfixe `openai/` interdit.** LiteLLM ≥ 1.9x suppose la Responses API pour
ce provider : `/v1/messages` part vers `/v1/responses` (422 Scaleway) et
chaque `count_tokens` tente `/v1/responses/input_tokens` (404 en rafale).
`hosted_vllm/` évite les deux ; le flag
`use_chat_completions_url_for_anthropic_messages: true` reste en filet.

**Limite Scaleway 16384 tokens de sortie.** Claude Code en demande plus par
défaut (400 `payload validation`), et ses appels internes (compaction de
contexte) ignorent `CLAUDE_CODE_MAX_OUTPUT_TOKENS`. Double protection :
la variable dans les scripts, l'écrêtage `custom_callbacks.py` côté proxy.

**`zsh --norc` n'existe pas.** L'exec final de `shell.sh` mourait
silencieusement sous zsh (défaut macOS) : l'utilisateur retombait dans son
shell normal sans l'environnement, et `claude` partait vers la vraie API
Anthropic (« model may not exist »). Le script détecte le shell
(`--no-rcs` pour zsh, `--norc` pour bash).

**Dual-stack macOS : Docker « démarre sans conflit ».** Si le proxy venv
tient déjà le 4000 en IPv4, le conteneur prend le port en IPv6 et démarre
sans erreur — mais tout le trafic réel (127.0.0.1) continue d'aller au venv.
Arrêter le venv puis `docker compose down && make up`, et vérifier avec un
curl sur `127.0.0.1:4000`, pas seulement avec `docker ps`.

**429 `INSUFFICIENT QUOTA` ≠ panne.** C'est le quota Scaleway tokens/minute.
LiteLLM retente 2 fois, Claude Code fait son backoff, la session avance au
ralenti. Ne rien « réparer » : augmenter le quota ou répartir sur plusieurs
modèles.

## Limites connues

Claude Code est conçu pour Claude. Extended thinking, sous-agents et prompt
caching fonctionnent mal ou pas du tout derrière un autre modèle — d'où
`MAX_THINKING_TOKENS=0` et `DISABLE_PROMPT_CACHING=1` dans les réglages
générés. Ce dépôt sert à évaluer, pas à remplacer.

## Points ouverts

- La fenêtre de contexte réelle de `glm-5.2` chez Scaleway n'est pas vérifiée.
  Viser 64k minimum pour une base de code ; à confronter au comportement réel
  sur un gros fichier.
- Les mappings `claude-haiku-*` pointent sur GLM-5.2 comme le reste. Les
  basculer sur un modèle moins cher (`hosted_vllm/gpt-oss-120b`) allégerait la
  facture **et** le quota tokens/minute de glm-5.2 (quotas séparés par
  modèle) : c'est eux qui encaissent le volume de petites requêtes de fond.
