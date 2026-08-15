<div align="center">

# ⚡ claude-code-scaleway

**Faire tourner [Claude Code](https://code.claude.com) sur les modèles ouverts de [Scaleway Generative APIs](https://www.scaleway.com/en/generative-apis/) — GLM-5.2 par défaut.**

![License](https://img.shields.io/badge/license-MIT-green)
![LiteLLM](https://img.shields.io/badge/LiteLLM-v1.96.2%20(épinglée)-blue)
![Modèle](https://img.shields.io/badge/modèle-glm--5.2-orange)
![Backend](https://img.shields.io/badge/backend-Scaleway-purple)

</div>

---

Scaleway expose une API compatible **OpenAI**. Claude Code parle **Anthropic**. LiteLLM traduit entre les deux, en local :

```
Claude Code ──/v1/messages (Anthropic)──▶ LiteLLM :4000 ──/chat/completions (OpenAI)──▶ api.scaleway.ai/v1
```

## Sommaire

- [🚀 Démarrage rapide](#-démarrage-rapide)
- [⚙️ Configuration `.env`](#️-configuration-env)
- [✅ Le test qui compte](#-le-test-qui-compte)
- [🔀 Basculer un projet sur GLM](#-basculer-un-projet-sur-glm)
- [🔄 Changer de modèle](#-changer-de-modèle)
- [🛡️ Pièges Scaleway neutralisés dans la config](#️-pièges-scaleway-neutralisés-dans-la-config)
- [🩺 Dépannage](#-dépannage)
- [🚧 Limites en l'état](#-limites-en-létat)
- [📌 Notes & choix de conception](#-notes--choix-de-conception)
- [📚 Références](#-références)

### Aide-mémoire `make`

| Commande | Effet |
|---|---|
| `make install` | Crée `.venv` avec les versions compatibles |
| `make models` | Liste les modèles réellement servis par Scaleway |
| `make check` | Diagnostic complet en 5 étapes |
| `make tools` | **Le** test qui compte (tool calling) |
| `make proxy` | Lance le proxy en venv (garder le terminal) |
| `make up` / `make down` / `make logs` | Proxy en Docker |
| `make shell [DIR=…]` | Sous-shell GLM jetable |
| `make vscode [DIR=…]` | Ouvre VS Code basculé sur GLM |
| `make help` | Liste tout |

---

## 🚀 Démarrage rapide

```bash
cp .env.example .env      # renseigne SCW_SECRET_KEY
make install              # pip install litellm[proxy] dans un venv dédié
make models               # confirme l'identifiant réel du modèle
make tools                # LE test qui compte — voir plus bas
make proxy                # lance le proxy (garder ce terminal ouvert)
```

Dans un second terminal :

```bash
eval "$(make -s env)"
claude --model glm-5.2
```

> 💡 `make env` n'émet que des lignes `export`, donc `eval` reste sûr — les messages d'aide partent sur stderr.

### 🐳 Variante Docker — recommandée pour les sessions longues

```bash
make up       # démarre le conteneur (port 4000)
make logs     # suit les logs
make down     # arrête
```

L'image est **épinglée** (`ghcr.io/berriai/litellm:v1.96.2`, la version validée du venv — `main-latest` peut changer de comportement d'un pull à l'autre). Le conteneur monte `config.yaml` et `custom_callbacks.py`, et redémarre tout seul (`restart: unless-stopped`) : aucun terminal à garder ouvert, il survit aux reboots. **C'est le mode à préférer pour les runs autonomes de nuit.**

> ⚠️ Ne pas cumuler `make proxy` (venv) et `make up` (Docker) — voir [le piège dual-stack](#-dépannage).
>
> Sur cette machine, le port 4000 est réservé à cette passerelle dans le registre `owuicore-main/docker-utilise.md` (collision connue avec les composes du repo `console`, qui mappent aussi `4000`).

---

## ⚙️ Configuration `.env`

Quatre variables, **sans commentaires ni guillemets** :

| Variable | Rôle |
|---|---|
| `SCW_SECRET_KEY` | Clé secrète Scaleway (Console → IAM → Clés API), projet ayant accès aux Generative APIs |
| `MODEL` | Identifiant du modèle tel que servi par Scaleway — `make models` fait foi |
| `PROXY_KEY` | Clé arbitraire protégeant le proxy local, devient `ANTHROPIC_AUTH_TOKEN` |
| `PROXY_PORT` | Port d'écoute de LiteLLM |
| `MAX_OUTPUT_TOKENS` | *(optionnel)* Plafond de tokens de sortie — défaut `16384` (limite Scaleway pour glm-5.2), défini une seule fois dans `scripts/lib.sh`. À relever si tu passes sur un modèle au plafond plus haut. |

> ⚠️ Le `.env` est délibérément **dépourvu de commentaires** : une apostrophe ou un backtick dans un commentaire casse le quoting selon le shell et selon l'outil qui lit le fichier. `scripts/lib.sh` découpe chaque ligne au lieu de sourcer le fichier, donc rien n'y est jamais interprété — mais autant ne pas réintroduire le piège en éditant.

---

## ✅ Le test qui compte

```bash
make tools
```

Claude Code ne fait **rien** sans appels d'outils : lire un fichier, l'éditer, lancer une commande — tout passe par du tool calling. Ce test envoie une définition d'outil au modèle et vérifie qu'il renvoie un bloc `tool_calls` correctement formé.

S'il échoue, inutile d'aller plus loin : tu auras un assistant qui discute mais ne touche jamais à ton code. Ce n'est pas un problème de configuration, **c'est le modèle**.

`make check` enchaîne les cinq étapes du diagnostic (modèles disponibles, appel direct, tool calling, traduction Anthropic, `count_tokens`).

> 🧠 GLM-5.2 est un modèle *raisonneur* : il dépense ses premiers tokens en réflexion (`reasoning` côté OpenAI, bloc `thinking` côté Anthropic) avant d'émettre la réponse. Les tests du script laissent donc 500 tokens de marge — avec un `max_tokens` serré, le modèle est coupé en plein raisonnement et la réponse texte n'arrive jamais.

---

## 🔀 Basculer un projet sur GLM

Deux façons, selon que tu travailles au terminal ou dans VS Code.

### Au terminal — le plus simple

```bash
make shell                          # shell GLM dans le repo
make shell DIR=~/dev/mon-projet     # shell GLM dans un projet
```

Un sous-shell s'ouvre avec l'environnement pointé sur le proxy et un prompt `[glm-5.2]` pour ne pas s'y tromper. Tu tapes `claude`, tu travailles, tu fais `exit`. **Rien n'est écrit nulle part, rien à défaire.**

### Dans VS Code

```bash
make vscode                         # dossier courant
make vscode DIR=~/dev/mon-projet    # un autre projet
```

Le script écrit `.claude/settings.local.json` dans le projet ciblé, puis ouvre une fenêtre normale. **C'est ce fichier qui fait tout le travail** : il ne concerne que ce projet, donc tes autres projets et ton CLI restent sur ton compte Anthropic.

<details>
<summary><b><code>--isolated</code>, et pourquoi ce n'est pas le défaut</b></summary>

```bash
./scripts/vscode.sh --isolated ~/dev/mon-projet
```

Ajoute un profil VS Code dédié et une instance séparée. Deux effets de bord à connaître avant de l'utiliser :

- un profil neuf **n'a aucune extension installée**, Claude Code compris ;
- VS Code **mémorise l'association dossier → profil**. Rouvrir ce dossier plus tard, même normalement, le rouvre dans ce profil vide.

C'est la cause classique du « Claude Code a disparu de mes fenêtres ». Pour revenir en arrière : `Cmd+Shift+P` → `Profiles: Switch Profile` → `Default`, dans chaque fenêtre concernée. Le profil se supprime ensuite depuis `Profiles: Delete Profile`, et le dossier `~/.vscode-Scaleway-GLM` peut être jeté.

L'isolation par `settings.local.json` suffit dans la quasi-totalité des cas.
</details>

<details>
<summary><b>Portée des réglages — pourquoi pas <code>~/.claude/settings.json</code></b></summary>

Ce fichier est **global**. Y mettre `ANTHROPIC_BASE_URL` bascule *tout* sur GLM — tous tes projets, toutes tes fenêtres, ton CLI. La portée projet (`.claude/settings.local.json`) fait la même chose, mais confinée.

L'ordre de priorité de Claude Code, du plus fort au plus faible :

```
réglages managés (IT) > .claude/settings.local.json > .claude/settings.json > ~/.claude/settings.json
```

`.vscode/settings.json` ne joue aucun rôle : l'extension ne le lit pas.
</details>

**Basculer un projet à la main** — `templates/settings.local.json` est le fichier commenté à copier dans `<projet>/.claude/settings.local.json`. Aucun script requis, mais pense à l'exclure du versionnement (le script le fait via `.git/info/exclude`).

**Repasser sur Anthropic** — supprime `.claude/settings.local.json` du projet, ou ouvre-le dans une fenêtre VS Code normale : les deux profils cohabitent sans interférence.

---

## 🔄 Changer de modèle

Tout Scaleway sert des modèles ouverts au même endpoint. Pour en essayer un autre :

1. `make models` → repère l'identifiant
2. remplace `hosted_vllm/glm-5.2` dans `config.yaml` (toutes les occurrences — modèle principal + alias) en **gardant le préfixe `hosted_vllm/`**
3. mets `MODEL` à jour dans `.env`
4. `make tools` pour valider avant de perdre du temps

> Les alias `claude-sonnet-4-5` / `claude-haiku-4-5` **et leurs variantes versionnées** (`claude-sonnet-4-5-20250929`, `claude-haiku-4-5-20251001`) dans `config.yaml` ne sont pas décoratifs : Claude Code réclame ces noms pour ses tâches de fond (résumés, titres de conversation), et retombe sur les IDs versionnés quand une session démarre sans l'environnement complet. Sans eux, tu récupères des erreurs `model not found` même avec un `--model` correct.

Le mapping `claude-haiku-4-5` est un bon endroit pour brancher un modèle moins cher — c'est celui qui encaisse le volume de petites requêtes.

---

## 🛡️ Pièges Scaleway neutralisés dans la config

Trois choix de `config.yaml` ont l'air arbitraires mais réparent chacun une panne réelle. **Ne pas les défaire sans savoir pourquoi.**

| Choix | Sans lui | Pourquoi |
|---|---|---|
| Préfixe **`hosted_vllm/`** (pas `openai/`) | 422 `/v1/responses` + spam 404 `input_tokens` | Le provider `openai` de LiteLLM suppose la *Responses API* |
| **Écrêtage 16384** (`custom_callbacks.py`) | 400 `max_completion_tokens` | Scaleway plafonne la sortie ; certains appels internes ignorent le plafond client |
| **Alias versionnés** | `model not found` | Les tâches de fond réclament les IDs datés |

<details>
<summary><b>Détail — préfixe <code>hosted_vllm/</code> et non <code>openai/</code></b></summary>

Même protocole OpenAI, mais le provider `openai` de LiteLLM (≥ 1.9x) suppose que le backend implémente la *Responses API* : il route `/v1/messages` vers `/v1/responses` (422 `ROUTE NOT SUPPORTED` chez Scaleway) et tente le comptage de tokens sur `/v1/responses/input_tokens` (404 en rafale à chaque `count_tokens`, une requête HTTPS perdue à chaque fois). `hosted_vllm` ne projette aucune de ces suppositions. Le flag `use_chat_completions_url_for_anthropic_messages: true` reste en ceinture-bretelles si quelqu'un remet un préfixe `openai/`.
</details>

<details>
<summary><b>Détail — écrêtage à 16384 tokens de sortie</b></summary>

Scaleway plafonne `max_completion_tokens` à 16384 pour glm-5.2 et renvoie un 400 au-delà. `CLAUDE_CODE_MAX_OUTPUT_TOKENS=16384` (exporté par `shell.sh` / `vscode.sh`) couvre la majorité des appels de Claude Code, mais certains appels internes — la compaction de contexte notamment — fixent leur propre `max_tokens` : le proxy écrête donc lui-même, quel que soit le client (`custom_callbacks.py`). Sur une session longue, une compaction qui échoue en boucle peut coincer la session ; c'est ce garde-fou qui l'empêche.
</details>

---

## 🩺 Dépannage

| Symptôme | Cause / remède |
|---|---|
| `ImportError: cannot import name 'get_flat_dependant'` | LiteLLM hors venv, `fastapi` incompatible — voir plus bas |
| `ModuleNotFoundError: No module named 'proxy_server'` | Symptôme secondaire du même problème |
| `Unable to connect to API (ECONNREFUSED)` | Proxy éteint, ou `ANTHROPIC_BASE_URL` sur `0.0.0.0` au lieu de `127.0.0.1` |
| `model not found: claude-sonnet-4-5` (ou un ID versionné) | Alias manquant dans `config.yaml` |
| 422 `endpoint '/v1/responses' is not supported` | Préfixe `openai/` réintroduit — voir section ci-dessus |
| 404 `route '/v1/responses/input_tokens' not found` en rafale | Idem — comptage de tokens du provider `openai` ; cosmétique (fallback local) mais bruyant |
| 400 `max_completion_tokens is limited to 16384` | Session lancée sans les scripts **et** proxy sans `custom_callbacks.py` |
| 429 `INSUFFICIENT QUOTA` | Quota Scaleway *tokens/minute* atteint — **pas un bug**, Claude Code retente (voir plus bas) |
| « model may not exist » au lancement de `claude` | La session ne parle pas au proxy : vérifier le prompt `[glm-5.2]` du shell |
| Docker démarre « sans conflit » alors que `make proxy` tourne | Piège dual-stack macOS (voir plus bas) |
| 400 sur `cache_control` ou `thinking` | `drop_params: true` désactivé |
| Claude Code n'édite aucun fichier | Pas de `tool_calls` → `make tools` |
| `/context` affiche des chiffres approximatifs | `count_tokens` compté par le tokenizer local du proxy, pas par Scaleway — sans gravité |
| Réponses tronquées sur les gros fichiers | Fenêtre de contexte insuffisante |
| Blocs `thinking` qui cassent le flux | `export MAX_THINKING_TOKENS=0` |
| Le proxy ignore la vraie clé Anthropic | Vérifier `ANTHROPIC_API_KEY=""` |

> 🔍 Pour voir les requêtes traduites en clair : `set_verbose: true` dans `config.yaml`.

<details>
<summary><b>LiteLLM qui casse à l'import (<code>get_flat_dependant</code>)</b></summary>

```
ImportError: cannot import name 'get_flat_dependant' from 'fastapi.dependencies.utils'
ModuleNotFoundError: No module named 'proxy_server'
```

Le second message est trompeur : c'est le gestionnaire d'erreur de LiteLLM qui retombe sur un import alternatif après l'échec du premier. La cause réelle est l'`ImportError` au-dessus.

**FastAPI a supprimé `get_flat_dependant` en 0.140.7**, alors que LiteLLM 1.96.2 l'importe encore. Frontière établie par dichotomie :

| FastAPI | `get_flat_dependant` | LiteLLM |
|---|---|---|
| 0.140.6 | présent | démarre |
| 0.140.7 et au-delà | absent | `ImportError` |

`requirements.txt` porte la contrainte `fastapi<0.140.7`, et `make install` vérifie l'import avant de rendre la main. Ce n'est **pas** un problème d'environnement pollué : reproduit à l'identique dans un venv neuf.

```bash
make install     # crée .venv avec les versions compatibles
make proxy
```

Une installation globale préexistante peut rester : `make proxy` privilégie `.venv/bin/litellm` et avertit s'il retombe dessus.

Pour revérifier quand LiteLLM aura corrigé l'import :

```bash
.venv/bin/python -c "from fastapi.dependencies.utils import get_flat_dependant"
```

Alternative sans Python du tout : `make up` / `make logs` / `make down`.
</details>

<details>
<summary><b><code>0.0.0.0</code> contre <code>127.0.0.1</code></b></summary>

LiteLLM **écoute** sur `0.0.0.0`, ce qui signifie « toutes les interfaces ». Ce n'est pas une adresse à laquelle on se **connecte** : le client Node de Claude Code la refuse, d'où `ECONNREFUSED`. Toutes les URL côté client pointent donc sur `127.0.0.1`.

`make check` distingue les deux cas — proxy éteint, ou proxy actif mais adresse de connexion incorrecte.
</details>

<details>
<summary><b>429 : Claude Code retente tout seul</b></summary>

Observé en conditions réelles pendant une run autonome de nuit qui saturait le quota. La chaîne complète :

1. Scaleway renvoie `429 INSUFFICIENT QUOTA` (quota *tokens par minute* du projet dépassé) ;
2. LiteLLM retente 2 fois de son côté (`LiteLLM Retried: 2 times` dans les logs), puis transmet le 429 au client ;
3. **Claude Code retente lui-même avec backoff exponentiel** — la session ne meurt pas, elle attend et repart. Aucune action nécessaire.

Dans les logs du proxy, ça produit des rafales de tracebacks 429 impressionnantes mais bénignes, **entrecoupées de `200 OK`** : ces 200 sont le signe que la session avance, juste au ralenti. Ne s'inquiéter que si les 200 disparaissent complètement pendant une longue période.

Même logique pour les coupures du proxy : un redémarrage (`make down` / `make up`, ou bascule venv → Docker) est absorbé par les retries de Claude Code comme un 429 de plus — on peut redémarrer le proxy en pleine session sans tuer la run.
</details>

<details>
<summary><b>Piège dual-stack macOS — Docker « démarre sans conflit »</b></summary>

Si le proxy venv tient déjà le 4000 en IPv4, le conteneur prend le port en IPv6 et démarre **sans erreur** — mais tout le trafic réel (`127.0.0.1`) continue d'aller au venv. Arrêter le venv, puis `docker compose down && make up`, et vérifier avec un `curl` sur `127.0.0.1:4000`, pas seulement avec `docker ps`.
</details>

---

## 🚧 Limites en l'état

**Les quotas par défaut de Scaleway sont limités.** Ça marche, mais c'est sensible dès que Claude Code parallélise — sous-agents, tâches de fond, compaction : plusieurs requêtes simultanées saturent vite le quota *tokens par minute* du projet, et tout ralentit (429 `INSUFFICIENT QUOTA`, absorbés par les retries de Claude Code — la session avance, au ralenti). Pour un usage soutenu ou des runs autonomes, il faudra probablement passer sur un **déploiement dédié** (Scaleway Managed Inference ou équivalent) quand il sera disponible pour le modèle visé ; en attendant, on peut demander une augmentation de quota en console, ou répartir les alias `claude-haiku-*` sur un second modèle (les quotas sont par modèle).

**Le mode Docker dépend du démon Docker.** `make up` exige que Docker Desktop tourne — sinon : `Cannot connect to the Docker daemon` (le relancer : `open -a Docker`). Une fois le démon actif, le conteneur se débrouille seul (`restart: unless-stopped`), y compris après un reboot.

**Les librairies sont épinglées à cause d'une incompatibilité.** LiteLLM 1.96.2 importe un symbole que FastAPI a supprimé en 0.140.7 : d'où la contrainte `fastapi<0.140.7` dans `requirements.txt` (venv) et l'image Docker épinglée `v1.96.2`. Monter l'une sans l'autre casse le proxy au démarrage — détail dans [Dépannage](#-dépannage).

---

## 📌 Notes & choix de conception

- **L'identifiant `glm-5.2`** retenu par défaut suit la convention de nommage Scaleway (`llama-3.3-70b-instruct`, `gpt-oss-120b`…) mais n'a pas été confirmé dans leur documentation publique au moment de l'écriture. `make models` interroge `/v1/models` et donne la liste faisant foi.
- **Pourquoi LiteLLM et pas `y-router`** — la documentation Scaleway recommande `y-router` pour Claude Code, mais ce dépôt est archivé depuis qu'OpenRouter propose une intégration officielle. LiteLLM est activement maintenu et traduit mieux le tool calling.
- **Ceci sert à évaluer, pas à remplacer** — Claude Code est conçu pour Claude. Les fonctions avancées (extended thinking, sous-agents, prompt caching) fonctionnent de façon inégale ou pas du tout derrière un autre modèle.

## 📚 Références

- [Scaleway — Generative APIs, quickstart](https://www.scaleway.com/en/docs/generative-apis/quickstart/)
- [Scaleway — Intégration avec les outils populaires](https://www.scaleway.com/en/docs/generative-apis/reference-content/integrating-generative-apis-with-popular-tools/)
- [LiteLLM — endpoint `/v1/messages`](https://docs.litellm.ai/docs/anthropic_unified/)
- [Claude Code — passerelle LLM](https://code.claude.com/docs/en/llm-gateway)
- [Claude Code — réglages](https://code.claude.com/docs/en/settings)

## Licence

[MIT](LICENSE)
