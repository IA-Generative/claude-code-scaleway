# claude-code-scaleway

Faire tourner **Claude Code** sur les modèles ouverts servis par **Scaleway Generative APIs** — GLM-5.2 par défaut.

Scaleway expose une API compatible **OpenAI**. Claude Code parle **Anthropic**.
LiteLLM fait la traduction, en local.

```
Claude Code ──/v1/messages (Anthropic)──▶ LiteLLM :4000 ──/chat/completions (OpenAI)──▶ api.scaleway.ai/v1
```

---

## Démarrage

```bash
cp .env.example .env      # renseigne SCW_SECRET_KEY
make install              # pip install 'litellm[proxy]'
make models               # confirme l'identifiant réel du modèle
make tools                # LE test qui compte — voir plus bas
make proxy                # lance le proxy (garder ce terminal ouvert)
```

Dans un second terminal :

```bash
eval "$(make -s env)"
claude --model glm-5.2
```

`make env` affiche simplement les trois exports à appliquer :

```bash
export ANTHROPIC_BASE_URL=http://0.0.0.0:4000
export ANTHROPIC_AUTH_TOKEN=sk-local-dev-1234
export ANTHROPIC_API_KEY=""        # neutralise une éventuelle vraie clé Anthropic
```

Variante Docker, si tu préfères ne rien installer : `make up`, puis `make logs` / `make down`.

---

## Le test déterminant

```bash
make tools
```

Claude Code ne fait **rien** sans appels d'outils : lire un fichier, l'éditer,
lancer une commande — tout passe par du tool calling. Ce test envoie une
définition d'outil au modèle et vérifie qu'il renvoie un bloc `tool_calls`
correctement formé.

S'il échoue, inutile d'aller plus loin : tu auras un assistant qui discute
mais ne touche jamais à ton code. Ce n'est pas un problème de configuration,
c'est le modèle.

`make check` enchaîne les cinq étapes du diagnostic (modèles disponibles,
appel direct, tool calling, traduction Anthropic, `count_tokens`).

---

## Extension VS Code

L'extension n'a pas de configuration propre : elle lit celle du CLI.
`.vscode/settings.json` ne sert à rien ici.

Dans `~/.claude/settings.json` :

```json
{
  "env": {
    "ANTHROPIC_BASE_URL": "http://0.0.0.0:4000",
    "ANTHROPIC_AUTH_TOKEN": "sk-local-dev-1234",
    "ANTHROPIC_API_KEY": "",
    "ANTHROPIC_MODEL": "glm-5.2"
  }
}
```

Lance le proxy **avant** d'ouvrir VS Code, puis redémarre VS Code complètement —
un simple reload de fenêtre ne recharge pas toujours l'environnement.

---

## Changer de modèle

Tout Scaleway sert des modèles ouverts au même endpoint. Pour en essayer un autre :

1. `make models` → repère l'identifiant
2. remplace `openai/glm-5.2` dans `config.yaml` (trois occurrences)
3. mets `MODEL` à jour dans `.env`
4. `make tools` pour valider avant de perdre du temps

Les alias `claude-sonnet-4-5` et `claude-haiku-4-5` dans `config.yaml` ne sont
pas décoratifs : Claude Code réclame ces noms pour ses tâches de fond
(résumés, titres de conversation). Sans eux, tu récupères des erreurs
`model not found` même avec un `--model` correct.

Le mapping `claude-haiku-4-5` est un bon endroit pour brancher un modèle
moins cher — c'est celui qui encaisse le volume de petites requêtes.

---

## Dépannage

| Symptôme | Cause |
|---|---|
| `model not found: claude-sonnet-4-5` | Alias manquant dans `config.yaml` |
| Erreur 400 sur `cache_control` ou `thinking` | `drop_params: true` désactivé |
| Claude Code n'édite aucun fichier | Pas de `tool_calls` → `make tools` |
| `/context` affiche des chiffres absurdes | `count_tokens` non implémenté, cosmétique |
| Réponses tronquées sur les gros fichiers | Fenêtre de contexte insuffisante |
| Blocs `thinking` qui cassent le flux | `export MAX_THINKING_TOKENS=0` |
| Le proxy ignore la vraie clé Anthropic | Vérifier `ANTHROPIC_API_KEY=""` |

Pour voir les requêtes traduites en clair : `set_verbose: true` dans `config.yaml`.

---

## Notes

L'identifiant `glm-5.2` retenu par défaut suit la convention de nommage
Scaleway (`llama-3.3-70b-instruct`, `gpt-oss-120b`…) mais n'a pas été confirmé
dans leur documentation publique au moment de l'écriture. `make models`
interroge `/v1/models` et donne la liste faisant foi.

La documentation Scaleway recommande `y-router` pour Claude Code. Ce dépôt est
archivé depuis qu'OpenRouter propose une intégration officielle. LiteLLM est
activement maintenu et traduit mieux le tool calling — d'où ce choix.

Claude Code est conçu pour Claude. Les fonctions avancées (extended thinking,
sous-agents, prompt caching) fonctionnent de façon inégale ou pas du tout
derrière un autre modèle. Ce dépôt sert à évaluer, pas à remplacer.

## Références

- [Scaleway — Generative APIs, quickstart](https://www.scaleway.com/en/docs/generative-apis/quickstart/)
- [Scaleway — Intégration avec les outils populaires](https://www.scaleway.com/en/docs/generative-apis/reference-content/integrating-generative-apis-with-popular-tools/)
- [LiteLLM — endpoint `/v1/messages`](https://docs.litellm.ai/docs/anthropic_unified/)
- [Claude Code — passerelle LLM](https://code.claude.com/docs/en/llm-gateway)
- [Claude Code — réglages](https://code.claude.com/docs/en/settings)

## Licence

MIT
