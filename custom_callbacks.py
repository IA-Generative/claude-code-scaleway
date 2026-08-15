"""Garde-fous cote proxy, independants du client.

Scaleway plafonne max_completion_tokens (16384 pour glm-5.2) et renvoie un
400 au-dela. CLAUDE_CODE_MAX_OUTPUT_TOKENS couvre la majorite des appels de
Claude Code, mais certains appels internes (compaction de contexte, etc.)
fixent leur propre max_tokens : on ecrete donc ici, quel que soit le client.

Reference dans config.yaml :  litellm_settings.callbacks
"""

import os

from litellm.integrations.custom_logger import CustomLogger

# Garde-fou serveur, independant du client par conception. Defaut = limite
# Scaleway pour glm-5.2 ; surchargeable via SCW_MAX_COMPLETION_TOKENS (ex. si
# le modele ou le plafond change) sans toucher au code.
SCW_MAX_COMPLETION_TOKENS = int(os.getenv("SCW_MAX_COMPLETION_TOKENS", "16384"))


class ClampMaxTokens(CustomLogger):
    async def async_pre_call_hook(self, user_api_key_dict, cache, data, call_type):
        for key in ("max_tokens", "max_completion_tokens"):
            value = data.get(key)
            if isinstance(value, int) and value > SCW_MAX_COMPLETION_TOKENS:
                data[key] = SCW_MAX_COMPLETION_TOKENS
        return data


proxy_handler_instance = ClampMaxTokens()
