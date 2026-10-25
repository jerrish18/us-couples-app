import asyncio
import contextlib
import hmac
import json
import logging
import os
import time
from datetime import datetime, timezone
from aiohttp import web
import httpx
from .calls import EchoCall, should_answer
from .config import Config
from .store import Account, load_accounts
from .inference import Inference
from .speech import Speech


class Bridge:
    def __init__(self, config):
        self.config = config
        self.http = httpx.AsyncClient(timeout=10, follow_redirects=False)
        self.accounts = load_accounts(config, self.http)
        self.inference = Inference(config, self.http)
        self.speech = Speech(config)
        self.calls = {}
        self.worker = None
        self.preparing = None

    async def prepare(self):
        try:
            await self.speech.prepare()
        except Exception:
            logging.warning("ECHO voice preflight failed; automatic answering disabled")

    async def poll(self):
        while True:
            for uid, account in list(self.accounts.items()):
                try:
                    await account.put(
                        "echo_devices",
                        {
                            "user_id": uid,
                            "heartbeat": datetime.now(timezone.utc).isoformat(),
                            "ready": self.speech.ready,
                        },
                    )
                    if not self.speech.ready:
                        continue
                    prefs = await account.select(
                        "echo_preferences", user_id="eq." + uid, enabled="eq.true"
                    )
                    requests = await account.select(
                        "echo_requests", user_id="eq." + uid
                    )
                    manual = {r["call_id"] for r in requests}
                    rows = await account.select(
                        "calls",
                        callee_id="eq." + uid,
                        state="eq.ringing",
                        order="created_at.desc",
                        limit="3",
                    )
                    prefs = [p for p in prefs if p.get("host", "bridge") == "bridge"]
                    for row in rows:
                        key = (uid, row["id"])
                        if key in self.calls:
                            continue
                        settings = next(
                            (p for p in prefs if p["couple_id"] == row["couple_id"]),
                            None,
                        )
                        if settings and should_answer(
                            row, settings, row["id"] in manual
                        ):
                            call = EchoCall(
                                account, row, settings, self.speech, self.inference
                            )
                            self.calls[key] = call
                            try:
                                async with asyncio.timeout(20):
                                    await call.answer()
                            except Exception:
                                await call.close(persist=False)
                                logging.warning(
                                    "ECHO could not claim call; human answering remains available"
                                )
                    for key, call in list(self.calls.items()):
                        if call.closed:
                            self.calls.pop(key, None)
                except httpx.HTTPStatusError as error:
                    if error.response.status_code in (400, 401, 403):
                        logging.warning(
                            "ECHO authorization unavailable; reauthorize the bridge if needed"
                        )
                except Exception:
                    logging.warning(
                        "ECHO polling unavailable; retrying without stopping active media"
                    )
            await asyncio.sleep(2)

    async def complete(self, request):
        expected = self.config.inference_key
        if not expected or not hmac.compare_digest(
            request.headers.get("Authorization", ""), "Bearer " + expected
        ):
            raise web.HTTPUnauthorized()
        body = await request.json()
        if not isinstance(body, dict):
            raise web.HTTPBadRequest()
        messages = body.get("messages")
        if (
            not isinstance(messages, list)
            or len(messages) > 25
            or any(
                not isinstance(m, dict)
                or m.get("role") not in ("system", "user", "assistant")
                or not isinstance(m.get("content"), str)
                for m in messages
            )
        ):
            raise web.HTTPBadRequest()
        schema = body.get("response_format", {}).get("json_schema", {}).get("schema")
        try:
            answer = await self.inference.complete(messages, schema, local_only=True)
            if schema:
                json.loads(answer)
            return web.json_response(
                {
                    "choices": [
                        {
                            "finish_reason": "stop",
                            "message": {"role": "assistant", "content": answer},
                        }
                    ]
                }
            )
        except (RuntimeError, TimeoutError, ValueError):
            return web.json_response(
                {"error": "Local inference unavailable"}, status=503
            )

    async def health(self, request):
        # No account identifiers, conversation data or credentials in health output.
        return web.json_response(
            {
                "voice_ready": self.speech.ready,
                "local_llm_ready": await self.inference.health(),
            }
        )

    async def close(self):
        for task in (self.worker, self.preparing):
            if task:
                task.cancel()
                with contextlib.suppress(asyncio.CancelledError):
                    await task
        for call in list(self.calls.values()):
            await call.close()
        for account in self.accounts.values():
            with contextlib.suppress(Exception):
                await account.patch(
                    "echo_devices", {"ready": False}, user_id="eq." + account.uid
                )
        await self.http.aclose()


@web.middleware
async def private_errors(request, handler):
    try:
        response = await handler(request)
    except web.HTTPException:
        raise
    except Exception:
        # Never expose provider response bodies, tokens or user data in exceptions.
        return web.json_response({"error": "ECHO request could not finish"}, status=503)
    response.headers["Cache-Control"] = "no-store"
    return response


def create_app(bridge):
    app = web.Application(client_max_size=48000, middlewares=[private_errors])
    app.router.add_post("/v1/chat/completions", bridge.complete)
    app.router.add_get("/health", bridge.health)

    async def start(_):
        bridge.preparing = asyncio.create_task(bridge.prepare())
        bridge.worker = asyncio.create_task(bridge.poll())

    async def close(_):
        await bridge.close()

    app.on_startup.append(start)
    app.on_cleanup.append(close)
    return app


def main():
    logging.basicConfig(level=logging.WARNING)
    config = Config()

    async def app():
        return create_app(Bridge(config))

    # TLS terminates at a trusted reverse proxy. Never expose this port directly.
    web.run_app(
        app(),
        host=os.environ.get("ECHO_HOST", "127.0.0.1"),
        port=int(os.environ.get("ECHO_PORT", "8787")),
        access_log=None,
    )


if __name__ == "__main__":
    main()
