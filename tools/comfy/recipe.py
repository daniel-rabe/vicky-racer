"""Builds generation graphs from the frozen pipeline.json, so production cannot drift from it."""
import json
from pathlib import Path

import workflows as wf
from comfy_client import ComfyClient

ROOT = Path(__file__).resolve().parents[2]
PIPELINE = json.loads((Path(__file__).parent / "pipeline.json").read_text(encoding="utf-8"))


def sprite_prompt(subject: str) -> str:
    p = PIPELINE["prompt"]
    return p["sprite_template"].format(subject=subject, style=p["style"])


def flux_settings() -> wf.FluxSettings:
    g = PIPELINE["generator"]
    return wf.FluxSettings(unet=g["unet"], weight_dtype=g["weight_dtype"], clip_l=g["clip_l"], t5=g["t5"],
                           vae=g["vae"], guidance=g["guidance"], steps=g["steps"], sampler=g["sampler"],
                           scheduler=g["scheduler"])


def cutout_settings() -> wf.CutoutSettings:
    m = PIPELINE["matting"]
    return wf.CutoutSettings(model=m["model"], sensitivity=m["sensitivity"], padding=m["crop_padding"])


def upload_style_reference(client: ComfyClient) -> str:
    path = ROOT / PIPELINE["style_lock"]["reference"]
    return client.upload_image(path.read_bytes(), "vr_style_reference.png")


def style_ref(uploaded_reference: str) -> wf.StyleRef:
    s = PIPELINE["style_lock"]
    return wf.StyleRef(uploaded_reference, downsampling_factor=s["downsampling_factor"], weight=s["weight"],
                       mode=s["mode"], style_model=s["style_model"], clip_vision=s["clip_vision"])


def sprite_graph(subject: str, seed: int, uploaded_reference: str, prefix: str = "vr_asset") -> dict:
    size = PIPELINE["generator"]["size"]
    return wf.flux_txt2img(sprite_prompt(subject), seed, size, size, settings=flux_settings(),
                           cutout=cutout_settings(), style=style_ref(uploaded_reference), prefix=prefix)


def variant_graph(uploaded_image: str, instruction: str, seed: int, prefix: str = "vr_variant") -> dict:
    v = PIPELINE["variants"]
    settings = wf.FluxSettings(unet=v["unet"], weight_dtype=v["weight_dtype"], guidance=v["guidance"])
    return wf.flux_kontext_edit(uploaded_image, instruction, seed, settings=settings,
                                cutout=cutout_settings(), prefix=prefix)


def background_graph(scene: str, seed: int, size: tuple[int, int], uploaded_reference: str,
                     prefix: str = "vr_background") -> dict:
    """A full-screen picture (no cut-out): the scene in the house style, style-locked like sprites."""
    prompt = f"{scene}, {PIPELINE['prompt']['style']}"
    return wf.flux_txt2img(prompt, seed, size[0], size[1], settings=flux_settings(),
                           style=style_ref(uploaded_reference), prefix=prefix)
