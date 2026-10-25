import asyncio
import json
import time
import httpx


class Inference:
    """Bounded local/cloud failover. A provider failure never owns the media peer."""

    def __init__(self, config, http):
        self.config, self.http = config, http
        self.cooldowns = {}
        self.limit = asyncio.Semaphore(2)

    def providers(self):
        providers = [
            ("local", self.config.ollama_url + "/api/chat", None, self.config.model)
        ]
        if self.config.groq_key:
            providers.append(
                (
                    "groq",
                    "https://api.groq.com/openai/v1/chat/completions",
                    self.config.groq_key,
                    self.config.groq_model,
                )
            )
        return providers

    async def stream(self, messages, schema=None, local_only=False):
        async with self.limit:
            for name, url, key, model in self.providers():
                if local_only and name != "local":
                    continue
                if self.cooldowns.get(name, 0) > time.monotonic():
                    continue
                emitted = False
                try:
                    body = {"model": model, "messages": messages, "stream": True}
                    if name == "local":
                        body.update(
                            {
                                "options": {
                                    "num_predict": 2000 if schema else 600,
                                    "num_ctx": 8192,
                                },
                                "think": False,
                            }
                        )
                        if schema:
                            body["format"] = schema
                    else:
                        body["max_completion_tokens"] = 2000
                        if model.startswith("openai/gpt-oss"):
                            body["reasoning_effort"] = "low"
                        if schema:
                            body["response_format"] = {"type": "json_object"}
                            body["messages"] = [
                                *messages,
                                {
                                    "role": "system",
                                    "content": "Return JSON matching this schema: "
                                    + json.dumps(schema),
                                },
                            ]
                    headers = {"Authorization": f"Bearer {key}"} if key else {}
                    async with self.http.stream(
                        "POST", url, json=body, headers=headers, timeout=18
                    ) as response:
                        if response.status_code == 429:
                            try:
                                wait = min(
                                    300,
                                    max(
                                        1,
                                        float(
                                            response.headers.get("retry-after", "60")
                                        ),
                                    ),
                                )
                            except ValueError:
                                wait = 60
                            self.cooldowns[name] = time.monotonic() + wait
                            continue
                        response.raise_for_status()
                        async for line in response.aiter_lines():
                            if not line or line == "data: [DONE]":
                                continue
                            data = json.loads(
                                line[6:] if line.startswith("data: ") else line
                            )
                            text = (
                                data.get("message", {}).get("content", "")
                                if name == "local"
                                else data.get("choices", [{}])[0]
                                .get("delta", {})
                                .get("content", "")
                            )
                            if text:
                                emitted = True
                                yield text
                            if data.get("done") and data.get("done_reason") == "length":
                                raise ValueError("Answer truncated")
                    if emitted:
                        return
                    raise ValueError("Empty inference response")
                except (httpx.HTTPError, ValueError, KeyError):
                    self.cooldowns[name] = time.monotonic() + 30
                    # Audio already spoken cannot be replayed by a second provider.
                    # The next turn includes the actual partial answer in context.
                    if emitted:
                        raise RuntimeError(
                            "Inference interrupted after partial response"
                        )
            raise RuntimeError("All inference providers unavailable")

    async def complete(self, messages, schema=None, local_only=False):
        async with asyncio.timeout(35):
            return "".join(
                [part async for part in self.stream(messages, schema, local_only)]
            )

    async def health(self):
        try:
            response = await self.http.get(
                self.config.ollama_url + "/api/tags", timeout=2
            )
            response.raise_for_status()
            names = [x["name"] for x in response.json().get("models", [])]
            return self.config.model in names
        except (httpx.HTTPError, ValueError, KeyError):
            return False
