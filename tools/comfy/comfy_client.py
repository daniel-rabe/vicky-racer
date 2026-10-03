"""Minimal ComfyUI HTTP client: queue a graph, wait for it, download the images.

Polls /history rather than holding a websocket open. Generations take seconds,
so a one-second poll costs nothing and there is no connection state to manage.
Standard library only, so the tooling runs on any Python without installs.
"""
import json
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid

DEFAULT_URL = "http://127.0.0.1:8188"


class ComfyError(RuntimeError):
    pass


class ComfyClient:
    def __init__(self, base_url: str = DEFAULT_URL, timeout: float = 900.0, poll_interval: float = 1.0):
        self.base_url = base_url.rstrip("/")
        self.timeout = timeout
        self.poll_interval = poll_interval
        self.client_id = uuid.uuid4().hex

    def _request(self, path: str, payload: dict | None = None) -> bytes:
        data = None
        headers = {}
        if payload is not None:
            data = json.dumps(payload).encode("utf-8")
            headers["Content-Type"] = "application/json"
        req = urllib.request.Request(self.base_url + path, data=data, headers=headers)
        try:
            with urllib.request.urlopen(req, timeout=30) as resp:
                return resp.read()
        except urllib.error.HTTPError as e:
            body = e.read().decode("utf-8", "replace")
            raise ComfyError(f"{e.code} from {path}: {_describe_error(body)}") from None
        except urllib.error.URLError as e:
            raise ComfyError(
                f"Cannot reach ComfyUI at {self.base_url} ({e.reason}). "
                "Start it with run_nvidia_gpu.bat and try again."
            ) from None

    def _get_json(self, path: str) -> dict:
        return json.loads(self._request(path))

    def check_alive(self) -> dict:
        return self._get_json("/system_stats")

    def queue(self, graph: dict) -> str:
        resp = json.loads(self._request("/prompt", {"prompt": graph, "client_id": self.client_id}))
        return resp["prompt_id"]

    def wait(self, prompt_id: str) -> dict:
        deadline = time.monotonic() + self.timeout
        while time.monotonic() < deadline:
            history = self._get_json(f"/history/{prompt_id}")
            entry = history.get(prompt_id)
            if entry:
                status = entry.get("status", {})
                if status.get("status_str") == "error":
                    raise ComfyError(f"Prompt {prompt_id} failed: {_execution_error(status)}")
                if status.get("completed", True):
                    return entry
            time.sleep(self.poll_interval)
        raise ComfyError(f"Prompt {prompt_id} did not finish within {self.timeout:.0f}s")

    def fetch_image(self, ref: dict) -> bytes:
        query = urllib.parse.urlencode({
            "filename": ref["filename"],
            "subfolder": ref.get("subfolder", ""),
            "type": ref.get("type", "output"),
        })
        return self._request(f"/view?{query}")

    def upload_image(self, png: bytes, name: str) -> str:
        """Upload an image to ComfyUI's input folder; returns the name LoadImage expects."""
        boundary = uuid.uuid4().hex.encode()
        crlf = b"\r\n"
        body = b"".join([
            b"--" + boundary + crlf,
            b'Content-Disposition: form-data; name="image"; filename="' + name.encode() + b'"' + crlf,
            b"Content-Type: image/png" + crlf + crlf,
            png + crlf,
            b"--" + boundary + crlf,
            b'Content-Disposition: form-data; name="overwrite"' + crlf + crlf,
            b"true" + crlf,
            b"--" + boundary + b"--" + crlf,
        ])
        req = urllib.request.Request(
            self.base_url + "/upload/image", data=body,
            headers={"Content-Type": "multipart/form-data; boundary=" + boundary.decode()},
        )
        try:
            with urllib.request.urlopen(req, timeout=30) as resp:
                info = json.loads(resp.read())
        except urllib.error.URLError as e:
            raise ComfyError(f"Upload of {name} failed: {e}") from None
        sub = info.get("subfolder", "")
        return f"{sub}/{info['name']}" if sub else info["name"]

    def run(self, graph: dict) -> dict[str, list[bytes]]:
        """Queue a graph and return {output_node_id: [png_bytes, ...]}."""
        entry = self.wait(self.queue(graph))
        images = {}
        for node_id, output in entry.get("outputs", {}).items():
            refs = output.get("images", [])
            if refs:
                images[node_id] = [self.fetch_image(ref) for ref in refs]
        if not images:
            raise ComfyError("Graph finished but produced no images — is there a SaveImage node?")
        return images


def _describe_error(body: str) -> str:
    try:
        data = json.loads(body)
    except json.JSONDecodeError:
        return body[:500]
    parts = [data.get("error", {}).get("message", "")]
    for node_id, node in data.get("node_errors", {}).items():
        for err in node.get("errors", []):
            parts.append(f"node {node_id} ({node.get('class_type')}): {err.get('message')} {err.get('details', '')}")
    return " | ".join(p for p in parts if p)


def _execution_error(status: dict) -> str:
    for kind, info in status.get("messages", []):
        if kind == "execution_error":
            return f"{info.get('node_type')}: {info.get('exception_message', '').strip()}"
    return "unknown error"
