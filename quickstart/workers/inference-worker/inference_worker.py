import os
import threading
from importlib.metadata import version as package_version
from typing import Any, Dict, List, Optional, Tuple

import gguf

if not getattr(gguf, "__version__", None):
    gguf.__version__ = package_version("gguf")

from iii import InitOptions, Logger, register_worker
from transformers import AutoModelForCausalLM, AutoTokenizer

iii = register_worker(
    os.environ.get("III_URL", "ws://localhost:49134"),
    InitOptions(worker_name="inference-worker"),
)
logger = Logger()

MODEL_ID = "ggml-org/gemma-3-270m-GGUF"
GGUF_FILE = "gemma-3-270m-Q8_0.gguf"

_tokenizer: Optional[AutoTokenizer] = None
_model: Optional[AutoModelForCausalLM] = None
_load_lock = threading.Lock()

CHAT_TEMPLATE = """{{ bos_token }}
{%- if messages[0]['role'] == 'system' -%}
    {%- if messages[0]['content'] is string -%}
        {%- set first_user_prefix = messages[0]['content'] + '

' -%}
    {%- else -%}
        {%- set first_user_prefix = messages[0]['content'][0]['text'] + '

' -%}
    {%- endif -%}
    {%- set loop_messages = messages[1:] -%}
{%- else -%}
    {%- set first_user_prefix = "" -%}
    {%- set loop_messages = messages -%}
{%- endif -%}
{%- for message in loop_messages -%}
    {%- if (message['role'] == 'user') != (loop.index0 % 2 == 0) -%}
        {{ raise_exception("Conversation roles must alternate user/assistant/user/assistant/...") }}
    {%- endif -%}
    {%- if (message['role'] == 'assistant') -%}
        {%- set role = "model" -%}
    {%- else -%}
        {%- set role = message['role'] -%}
    {%- endif -%}
    {{ '<start_of_turn>' + role + '
' + (first_user_prefix if loop.first else "") }}
    {%- if message['content'] is string -%}
        {{ message['content'] | trim }}
    {%- elif message['content'] is iterable -%}
        {%- for item in message['content'] -%}
            {%- if item['type'] == 'image' -%}
                {{ '<start_of_image>' }}
            {%- elif item['type'] == 'text' -%}
                {{ item['text'] | trim }}
            {%- endif -%}
        {%- endfor -%}
    {%- else -%}
        {{ raise_exception("Invalid content type") }}
    {%- endif -%}
    {{ '<end_of_turn>
' }}
{%- endfor -%}
{%- if add_generation_prompt -%}
    {{'<start_of_turn>model
'}}
{%- endif -%}"""


def _load_model() -> Tuple[AutoTokenizer, AutoModelForCausalLM]:
    global _tokenizer, _model
    if _tokenizer is not None and _model is not None:
        return _tokenizer, _model

    with _load_lock:
        if _tokenizer is not None and _model is not None:
            return _tokenizer, _model
        logger.info("Loading gemma-3-270m (first request may take a few minutes)")
        _tokenizer = AutoTokenizer.from_pretrained(MODEL_ID, gguf_file=GGUF_FILE)
        _model = AutoModelForCausalLM.from_pretrained(MODEL_ID, gguf_file=GGUF_FILE)
        _tokenizer.chat_template = CHAT_TEMPLATE
        return _tokenizer, _model


def run_inference_handler(payload: Dict[str, str | List[Dict[str, Any]]]) -> Dict[str, Any]:
    tokenizer, model = _load_model()
    messages = payload.get("messages", [])

    text = tokenizer.apply_chat_template(messages, tokenize=False, add_generation_prompt=True)
    inputs = tokenizer(text, return_tensors="pt").to(model.device)

    output = model.generate(**inputs, max_new_tokens=256)
    result = tokenizer.decode(output[0][inputs["input_ids"].shape[-1]:], skip_special_tokens=True)

    logger.info("inference complete")
    return {"content": result}


iii.register_function("inference::run_inference", run_inference_handler)
_load_model()
print("Inference worker started - model ready")
