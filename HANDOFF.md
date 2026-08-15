# Relais — état du projet

Document de passation. À jour au 15 août 2026.

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
- Le dépôt est complet et déployé dans `~/Documents/GitHub/claude-code-scaleway`

## Reste à faire

1. **Débloquer git** — un `.git/index.lock` vide empêche tout commit
2. **Premier commit et push** vers `origin` (`IA-Generative/claude-code-scaleway`)
3. **Lancer le proxy** et valider les étapes 4 et 5 de `make check`
4. **Évaluer GLM-5.2 en usage réel** dans une session Claude Code

## Structure

| Fichier | Rôle |
|---|---|
| `config.yaml` | Mapping LiteLLM : modèle réel + alias `claude-sonnet-4-5` / `claude-haiku-4-5` |
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

## Limites connues

Claude Code est conçu pour Claude. Extended thinking, sous-agents et prompt
caching fonctionnent mal ou pas du tout derrière un autre modèle — d'où
`MAX_THINKING_TOKENS=0` et `DISABLE_PROMPT_CACHING=1` dans les réglages
générés. Ce dépôt sert à évaluer, pas à remplacer.

## Points ouverts

- La fenêtre de contexte réelle de `glm-5.2` chez Scaleway n'est pas vérifiée.
  Viser 64k minimum pour une base de code ; à confronter au comportement réel
  sur un gros fichier.
- `count_tokens` n'est pas garanti côté LiteLLM : si l'étape 5 de `make check`
  renvoie autre chose que 200, `/context` sera approximatif. Sans gravité.
- Le mapping `claude-haiku-4-5` pointe sur GLM-5.2 comme le reste. Le basculer
  sur un modèle moins cher (`gpt-oss-120b`) allégerait la facture : c'est lui
  qui encaisse le volume de petites requêtes de fond.
