# Ticket Scaleway — `deepseek-v4-flash-0731` : appels d'outils émis en texte (parseur d'outils qui abandonne)

> À déposer sur le support Scaleway (Generative APIs). Le payload exact qui
> reproduit (données projet privées) peut être fourni à votre équipe en privé.
> Contexte technique et contournement : https://github.com/IA-Generative/claude-code-scaleway

## Résumé

Sur `deepseek-v4-flash-0731`, avec un appel comportant des outils (`tools`),
**~15 à 30 % des tours le modèle émet son appel d'outil sous forme de TEXTE**
(dans le champ `content`) au lieu d'un `tool_calls` structuré. Le markup émis
utilise vos tokens spéciaux `｜DSML｜` (`<｜DSML｜invoke name="…">…`). Le parseur
d'outils **s'engage puis abandonne** : le token ouvrant `<｜DSML｜tool_calls>`
est consommé (absent de la sortie) mais tout le bloc interne — `invoke`,
`parameter`, et même le tag fermant `</｜DSML｜tool_calls>` — **fuit en
contenu**. La réponse a alors `finish_reason: stop` (`stop_reason: end_turn`
côté Anthropic) et **aucun `tool_calls`**.

Impact : tout client agentique (Claude Code, Cline, etc.) voit du texte au lieu
d'un appel exécutable → l'action n'est jamais lancée, l'agent boucle ou se fige.

## Configuration

| | |
|---|---|
| Modèle | `deepseek-v4-flash-0731` |
| Endpoint | `POST https://api.scaleway.ai/v1/chat/completions` (format OpenAI natif) |
| Reproduit aussi via | `/v1/messages` (pont Anthropic de LiteLLM) — mais l'origine est bien la réponse `/chat/completions` |
| Paramètres | `tools` (schémas de fonctions), `tool_choice: "auto"`, `temperature: 0.6–0.7` |
| Streaming | **Les deux modes sont touchés** (`stream: true` et `false`) |
| Corrélation | Se déclenche sous **gros contexte** : requête ~1,1 Mo, ~80 outils, ~200 messages. Des payloads synthétiques petits (~55 Ko) ne le déclenchent pas. |

## Comportement attendu vs observé

- **Attendu** : le modèle décide d'appeler un outil → la réponse contient
  `choices[0].message.tool_calls` (et `content: null`), `finish_reason:
  "tool_calls"`.
- **Observé (~15–30 % des tours)** : `tool_calls` absent, `finish_reason:
  "stop"`, et `choices[0].message.content` contient le markup d'appel d'outil
  en texte brut.

## Preuve — sortie réelle (sanitisée : chemins et messages génériques)

Le modèle est **incohérent** sur le format d'un tour à l'autre. Deux variantes
observées :

**Variante A — markup `｜DSML｜` sur toutes les balises :**

```
The commit command is being interrupted. Let me retry it as a background-safe call.

<｜DSML｜invoke name="Bash">
<｜DSML｜parameter name="command" string="true">cd /path/to/repo && git commit -m "feat: implement X

Multi-line message with accents (é, à) and "quotes"." > /tmp/c.log 2>&1; echo "exit=$?"</｜DSML｜parameter>
<｜DSML｜parameter name="description" string="true">Commit staged work, logging to file</｜DSML｜parameter>
</｜DSML｜invoke>
</｜DSML｜tool_calls>
```

**Variante B — balise ouvrante `<invoke …>` SANS le marqueur `｜DSML｜`**, alors
que les `parameter` et le tag fermant le portent :

```
The commit may have failed on a pre-commit hook. Let me check.

<invoke name="Bash">
<｜DSML｜parameter name="command" string="true">cd /path/to/repo && git log --oneline -1</｜DSML｜parameter>
<｜DSML｜parameter name="description" string="true">Verify whether commit succeeded</｜DSML｜parameter>
</invoke... (fermé par) </｜DSML｜invoke>
</｜DSML｜tool_calls>
```

Points clés pour le diagnostic côté serveur :

1. Le tag **ouvrant** `<｜DSML｜tool_calls>` n'apparaît jamais dans la sortie
   (consommé), mais le tag **fermant** `</｜DSML｜tool_calls>` fuit → le parseur
   entre en mode « tool call » puis échoue à extraire l'appel et rejette le
   reste en contenu.
2. Le marqueur `｜DSML｜` est **présent ou absent de façon incohérente** selon la
   balise (`<invoke>` vs `<｜DSML｜invoke>`), ce qui suggère une divergence entre
   le template de tool-call du modèle et la grammaire attendue par le parseur
   (vLLM `--tool-call-parser`).

## Reproduction

Le taux de fuite croît avec la **taille du contexte** (nombre et taille des
schémas d'outils + longueur de l'historique). Un payload réel Claude Code
(~1,1 Mo, 80 outils, 201 messages) fuit de façon déterministe à ~15–30 % sur
des tirs répétés du **même** payload (donc non lié à un contenu particulier).

- Le harnais de mesure et un squelette de payload synthétique sont dans le repo
  ci-dessus (`scw_repro.py`) ; à cette taille (~55 Ko) il ne déclenche pas — il
  faut monter en taille de schémas/contenus.
- **Nous pouvons fournir le payload exact (1,1 Mo) qui reproduit**, en privé à
  votre équipe (il contient des chemins et du code de projet internes, non
  publiables ici).

## Contournement en place (côté client)

En attendant un correctif serveur, nous rattrapons le markup fuité dans un
proxy LiteLLM : détection du bloc `<[｜DSML｜]invoke …>` en contenu et
reconstruction en `tool_use` Anthropic. Code et validation (25/25 tours
récupérés, input JSON intact) :
https://github.com/IA-Generative/claude-code-scaleway
(`custom_callbacks.py`, fonction `rescue_dsml` + hook streaming).

Ce contournement devra être retiré une fois votre parseur d'outils DeepSeek V4
corrigé — d'où ce signalement.

## Demande

Corriger le parseur d'outils de `deepseek-v4-flash-0731` (probablement le
`--tool-call-parser` vLLM / le chat template) pour qu'il extraie de façon fiable
les appels d'outils DeepSeek V4, quelle que soit la présence du marqueur
`｜DSML｜`, plutôt que de les laisser fuir en `content`.
