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
make install              # pip install litellm[proxy]
make models               # confirme l'identifiant réel du modèle
make tools                # LE test qui compte — voir plus bas
make proxy                # lance le proxy (garder ce terminal ouvert)
```

Dans un second terminal :

```bash
eval "$(make -s env)"
claude --model glm-5.2
```

`make env` n'émet que des lignes `export`, donc `eval` reste sûr — les
messages d'aide partent sur stderr.

Variante Docker, si tu préfères ne rien installer : `make up`, puis `make logs` / `make down`.

### Le fichier `.env`

Quatre variables, **sans commentaires ni guillemets** :

| Variable | Rôle |
|---|---|
| `SCW_SECRET_KEY` | Clé secrète Scaleway (Console → IAM → Clés API), projet ayant accès aux Generative APIs |
| `MODEL` | Identifiant du modèle tel que servi par Scaleway — `make models` fait foi |
| `PROXY_KEY` | Clé arbitraire protégeant le proxy local, devient `ANTHROPIC_AUTH_TOKEN` |
| `PROXY_PORT` | Port d'écoute de LiteLLM |

Le `.env` est délibérément dépourvu de commentaires : une apostrophe ou un
backtick dans un commentaire casse le quoting selon le shell et selon
l'outil qui lit le fichier. `scripts/lib.sh` découpe chaque ligne au lieu de
sourcer le fichier, donc rien n'y est jamais interprété — mais autant ne pas
réintroduire le piège en éditant.

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

## Basculer un projet sur GLM

Deux façons, selon que tu travailles au terminal ou dans VS Code.

### Au terminal — le plus simple

```bash
make shell                          # shell GLM dans le repo
make shell DIR=~/dev/mon-projet     # shell GLM dans un projet
```

Un sous-shell s'ouvre avec l'environnement pointé sur le proxy et un prompt
`[glm-5.2]` pour ne pas s'y tromper. Tu tapes `claude`, tu travailles, tu fais
`exit`. Rien n'est écrit nulle part, rien à défaire.

### Dans VS Code

```bash
make vscode                         # dossier courant
make vscode DIR=~/dev/mon-projet    # un autre projet
```

Le script écrit `.claude/settings.local.json` dans le projet ciblé, puis ouvre
une fenêtre normale. **C'est ce fichier qui fait tout le travail** : il ne
concerne que ce projet, donc tes autres projets et ton CLI restent sur ton
compte Anthropic.

Pas de profil VS Code séparé par défaut — voir l'avertissement ci-dessous.

### `--isolated`, et pourquoi ce n'est pas le défaut

```bash
./scripts/vscode.sh --isolated ~/dev/mon-projet
```

Ajoute un profil VS Code dédié et une instance séparée. Deux effets de bord à
connaître avant de l'utiliser :

- un profil neuf **n'a aucune extension installée**, Claude Code compris ;
- VS Code **mémorise l'association dossier → profil**. Rouvrir ce dossier plus
  tard, même normalement, le rouvre dans ce profil vide.

C'est la cause classique du « Claude Code a disparu de mes fenêtres ». Pour
revenir en arrière : `Cmd+Shift+P` → `Profiles: Switch Profile` → `Default`,
dans chaque fenêtre concernée. Le profil se supprime ensuite depuis
`Profiles: Delete Profile`, et le dossier `~/.vscode-Scaleway-GLM` peut être
jeté.

L'isolation par `settings.local.json` suffit dans la quasi-totalité des cas.

### Pourquoi pas `~/.claude/settings.json`

Ce fichier est **global**. Y mettre `ANTHROPIC_BASE_URL` bascule *tout* sur
GLM — tous tes projets, toutes tes fenêtres, ton CLI. La portée projet
(`.claude/settings.local.json`) fait la même chose, mais confinée.

L'ordre de priorité de Claude Code, du plus fort au plus faible :

```
réglages managés (IT) > .claude/settings.local.json > .claude/settings.json > ~/.claude/settings.json
```

`.vscode/settings.json` ne joue aucun rôle : l'extension ne le lit pas.

### Basculer un projet à la main

`templates/settings.local.json` est le fichier commenté à copier dans
`<projet>/.claude/settings.local.json`. Aucun script requis, mais pense à
l'exclure du versionnement — le script le fait via `.git/info/exclude`.

### Repasser sur Anthropic

Supprime `.claude/settings.local.json` du projet, ou ouvre-le dans une fenêtre
VS Code normale : les deux profils cohabitent sans interférence.

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
| `ImportError: cannot import name 'get_flat_dependant'` | LiteLLM installé hors venv, `fastapi` incompatible — voir ci-dessous |
| `ModuleNotFoundError: No module named 'proxy_server'` | Symptôme secondaire du même problème |
| `Unable to connect to API (ECONNREFUSED)` | Proxy éteint, ou `ANTHROPIC_BASE_URL` sur `0.0.0.0` au lieu de `127.0.0.1` |
| `model not found: claude-sonnet-4-5` | Alias manquant dans `config.yaml` |
| Erreur 400 sur `cache_control` ou `thinking` | `drop_params: true` désactivé |
| Claude Code n'édite aucun fichier | Pas de `tool_calls` → `make tools` |
| `/context` affiche des chiffres absurdes | `count_tokens` non implémenté, cosmétique |
| Réponses tronquées sur les gros fichiers | Fenêtre de contexte insuffisante |
| Blocs `thinking` qui cassent le flux | `export MAX_THINKING_TOKENS=0` |
| Le proxy ignore la vraie clé Anthropic | Vérifier `ANTHROPIC_API_KEY=""` |

Pour voir les requêtes traduites en clair : `set_verbose: true` dans `config.yaml`.

### LiteLLM qui casse à l'import

```
ImportError: cannot import name 'get_flat_dependant' from 'fastapi.dependencies.utils'
ModuleNotFoundError: No module named 'proxy_server'
```

Le second message est trompeur : c'est le gestionnaire d'erreur de LiteLLM qui
retombe sur un import alternatif après l'échec du premier. La cause réelle est
l'`ImportError` au-dessus.

**FastAPI a supprimé `get_flat_dependant` en 0.140.7**, alors que LiteLLM 1.96.2
l'importe encore. Frontière établie par dichotomie :

| FastAPI | `get_flat_dependant` | LiteLLM |
|---|---|---|
| 0.140.6 | présent | démarre |
| 0.140.7 et au-delà | absent | `ImportError` |

`requirements.txt` porte la contrainte `fastapi<0.140.7`, et `make install`
vérifie l'import avant de rendre la main. Ce n'est **pas** un problème
d'environnement pollué : reproduit à l'identique dans un venv neuf.

```bash
make install     # cree .venv avec les versions compatibles
make proxy
```

Une installation globale préexistante peut rester, `make proxy` privilégie
`.venv/bin/litellm` et avertit s'il retombe dessus.

Pour reverifier quand LiteLLM aura corrigé l'import :

```bash
.venv/bin/python -c "from fastapi.dependencies.utils import get_flat_dependant"
```

Alternative sans Python du tout :

```bash
make up      # docker compose
make logs
make down
```

### `0.0.0.0` contre `127.0.0.1`

LiteLLM **écoute** sur `0.0.0.0`, ce qui signifie « toutes les interfaces ».
Ce n'est pas une adresse à laquelle on se **connecte** : le client Node de
Claude Code la refuse, d'où `ECONNREFUSED`. Toutes les URL côté client
pointent donc sur `127.0.0.1`.

`make check` distingue les deux cas — proxy éteint, ou proxy actif mais
adresse de connexion incorrecte.

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
