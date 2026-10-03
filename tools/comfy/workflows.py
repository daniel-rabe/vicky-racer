"""Builds ComfyUI API-format graphs as plain dicts.

Every knob Phase 2 will want to sweep (model, guidance, sampler, steps, size,
matting model) is an argument, so the bake-off is a loop over parameters
rather than a pile of near-duplicate JSON files.
"""
from dataclasses import dataclass

FLUX_DEV = "flux1-dev.safetensors"
FLUX_KONTEXT = "flux1-dev-kontext_fp8_scaled.safetensors"


@dataclass
class FluxSettings:
    unet: str = FLUX_DEV
    weight_dtype: str = "fp8_e4m3fn"
    clip_l: str = "clip_l.safetensors"
    t5: str = "t5xxl_fp8_e4m3fn_scaled.safetensors"
    vae: str = "ae.safetensors"
    guidance: float = 3.5
    steps: int = 20
    sampler: str = "euler"
    scheduler: str = "beta"


@dataclass
class CutoutSettings:
    model: str = "BiRefNet-general"
    sensitivity: float = 1.0
    padding: int = 8


@dataclass
class StyleRef:
    """Redux style-lock: borrow the look of a reference image, not its content.

    Higher downsampling_factor and lower weight both weaken the reference's pull.
    `image_name` is a name returned by ComfyClient.upload_image.
    """
    image_name: str
    downsampling_factor: float = 3.0
    weight: float = 1.0
    mode: str = "keep aspect ratio"
    style_model: str = "flux1-redux-dev.safetensors"
    clip_vision: str = "sigclip_vision_patch14_384.safetensors"


@dataclass
class SD35Settings:
    checkpoint: str = r"stable-diffusion-3.5-medium\sd3.5_medium.safetensors"
    clip_g: str = r"stable-diffusion-3.5-medium\text_encoders\clip_g.safetensors"
    clip_l: str = r"stable-diffusion-3.5-medium\text_encoders\clip_l.safetensors"
    t5: str = r"stable-diffusion-3.5-medium\text_encoders\t5xxl_fp8_e4m3fn.safetensors"
    steps: int = 28
    cfg: float = 4.5
    shift: float = 3.0
    sampler: str = "dpmpp_2m"
    scheduler: str = "sgm_uniform"


def _flux_loaders(g: dict, s: FluxSettings) -> None:
    g["unet"] = {"class_type": "UNETLoader", "inputs": {"unet_name": s.unet, "weight_dtype": s.weight_dtype}}
    g["clip"] = {"class_type": "DualCLIPLoader", "inputs": {"clip_name1": s.clip_l, "clip_name2": s.t5, "type": "flux"}}
    g["vae"] = {"class_type": "VAELoader", "inputs": {"vae_name": s.vae}}


def _flux_conditioning(g: dict, s: FluxSettings, prompt: str, style: StyleRef | None = None) -> None:
    g["prompt"] = {"class_type": "CLIPTextEncode", "inputs": {"text": prompt, "clip": ["clip", 0]}}
    conditioning = ["prompt", 0]
    if style:
        g["style_model"] = {"class_type": "StyleModelLoader", "inputs": {"style_model_name": style.style_model}}
        g["clip_vision"] = {"class_type": "CLIPVisionLoader", "inputs": {"clip_name": style.clip_vision}}
        g["style_image"] = {"class_type": "LoadImage", "inputs": {"image": style.image_name}}
        g["redux"] = {"class_type": "ReduxAdvanced", "inputs": {
            "conditioning": conditioning, "style_model": ["style_model", 0], "clip_vision": ["clip_vision", 0],
            "image": ["style_image", 0], "downsampling_factor": style.downsampling_factor,
            "downsampling_function": "area", "mode": style.mode, "weight": style.weight,
        }}
        conditioning = ["redux", 0]
    g["guided"] = {"class_type": "FluxGuidance", "inputs": {"conditioning": conditioning, "guidance": s.guidance}}
    # FLUX-dev runs at cfg 1.0, so the negative is never used — KSampler still requires one.
    g["negative"] = {"class_type": "ConditioningZeroOut", "inputs": {"conditioning": ["prompt", 0]}}


def _sample_and_decode(g: dict, s: FluxSettings, seed: int, latent: list, denoise: float = 1.0) -> None:
    g["sampler"] = {"class_type": "KSampler", "inputs": {
        "model": ["unet", 0], "positive": ["guided", 0], "negative": ["negative", 0],
        "latent_image": latent, "seed": seed, "steps": s.steps, "cfg": 1.0,
        "sampler_name": s.sampler, "scheduler": s.scheduler, "denoise": denoise,
    }}
    g["decode"] = {"class_type": "VAEDecode", "inputs": {"samples": ["sampler", 0], "vae": ["vae", 0]}}


def _append_cutout(g: dict, c: CutoutSettings, prefix: str) -> None:
    g["rmbg"] = {"class_type": "BiRefNetRMBG", "inputs": {
        "image": ["decode", 0], "model": c.model, "sensitivity": c.sensitivity,
        "mask_blur": 0, "mask_offset": 0, "invert_output": False,
        "refine_foreground": True, "background": "Alpha", "background_color": "#222222",
    }}
    # The RMBG node's IMAGE and MASK both feed the crop, giving a tight box per sprite.
    g["crop"] = {"class_type": "AILab_CropObject", "inputs": {"image": ["rmbg", 0], "mask": ["rmbg", 1], "padding": c.padding}}
    g["save_cutout"] = {"class_type": "SaveImage", "inputs": {"images": ["crop", 0], "filename_prefix": f"{prefix}_cutout"}}


def flux_txt2img(prompt: str, seed: int, width: int = 1024, height: int = 1024,
                 settings: FluxSettings | None = None, cutout: CutoutSettings | None = None,
                 prefix: str = "vicky", style: StyleRef | None = None,
                 init_image: str | None = None, denoise: float = 1.0) -> dict:
    """Plain FLUX generation, optionally style-locked to a reference image.

    With `init_image` (an uploaded name) it becomes a restyle pass: the image is encoded and
    only partly re-noised, so `denoise` around 0.4-0.6 keeps the shape and changes the finish. With `cutout`, also saves an alpha cut-out of the subject.

    Output node ids: "save" (raw) and, with a cutout, "save_cutout".
    """
    s = settings or FluxSettings()
    g: dict = {}
    _flux_loaders(g, s)
    _flux_conditioning(g, s, prompt, style)
    if init_image:
        g["init"] = {"class_type": "LoadImage", "inputs": {"image": init_image}}
        g["latent"] = {"class_type": "VAEEncode", "inputs": {"pixels": ["init", 0], "vae": ["vae", 0]}}
    else:
        g["latent"] = {"class_type": "EmptySD3LatentImage", "inputs": {"width": width, "height": height, "batch_size": 1}}
    _sample_and_decode(g, s, seed, ["latent", 0], denoise)
    g["save"] = {"class_type": "SaveImage", "inputs": {"images": ["decode", 0], "filename_prefix": prefix}}
    if cutout:
        _append_cutout(g, cutout, prefix)
    return g


def flux_kontext_edit(image_name: str, instruction: str, seed: int,
                      settings: FluxSettings | None = None, cutout: CutoutSettings | None = None,
                      prefix: str = "vicky_edit") -> dict:
    """Edit an uploaded image with FLUX Kontext (e.g. repaint a car, keep the shape).

    `image_name` is the name returned by ComfyClient.upload_image.
    """
    s = settings or FluxSettings(unet=FLUX_KONTEXT, weight_dtype="default", guidance=2.5)
    g: dict = {}
    _flux_loaders(g, s)
    g["source"] = {"class_type": "LoadImage", "inputs": {"image": image_name}}
    g["scaled"] = {"class_type": "FluxKontextImageScale", "inputs": {"image": ["source", 0]}}
    g["encoded"] = {"class_type": "VAEEncode", "inputs": {"pixels": ["scaled", 0], "vae": ["vae", 0]}}
    g["prompt"] = {"class_type": "CLIPTextEncode", "inputs": {"text": instruction, "clip": ["clip", 0]}}
    g["referenced"] = {"class_type": "ReferenceLatent", "inputs": {"conditioning": ["prompt", 0], "latent": ["encoded", 0]}}
    g["guided"] = {"class_type": "FluxGuidance", "inputs": {"conditioning": ["referenced", 0], "guidance": s.guidance}}
    g["negative"] = {"class_type": "ConditioningZeroOut", "inputs": {"conditioning": ["prompt", 0]}}
    _sample_and_decode(g, s, seed, ["encoded", 0])
    g["save"] = {"class_type": "SaveImage", "inputs": {"images": ["decode", 0], "filename_prefix": prefix}}
    if cutout:
        _append_cutout(g, cutout, prefix)
    return g


def sd35_txt2img(prompt: str, negative: str, seed: int, width: int = 1024, height: int = 1024,
                 settings: SD35Settings | None = None, cutout: CutoutSettings | None = None,
                 prefix: str = "vicky_sd35") -> dict:
    """SD3.5-medium generation. Unlike FLUX-dev it runs at cfg > 1, so `negative` is honoured."""
    s = settings or SD35Settings()
    g: dict = {
        "ckpt": {"class_type": "CheckpointLoaderSimple", "inputs": {"ckpt_name": s.checkpoint}},
        "clip": {"class_type": "TripleCLIPLoader", "inputs": {"clip_name1": s.clip_g, "clip_name2": s.clip_l, "clip_name3": s.t5}},
        "shifted": {"class_type": "ModelSamplingSD3", "inputs": {"model": ["ckpt", 0], "shift": s.shift}},
        "prompt": {"class_type": "CLIPTextEncode", "inputs": {"text": prompt, "clip": ["clip", 0]}},
        "negative": {"class_type": "CLIPTextEncode", "inputs": {"text": negative, "clip": ["clip", 0]}},
        "latent": {"class_type": "EmptySD3LatentImage", "inputs": {"width": width, "height": height, "batch_size": 1}},
    }
    g["sampler"] = {"class_type": "KSampler", "inputs": {
        "model": ["shifted", 0], "positive": ["prompt", 0], "negative": ["negative", 0],
        "latent_image": ["latent", 0], "seed": seed, "steps": s.steps, "cfg": s.cfg,
        "sampler_name": s.sampler, "scheduler": s.scheduler, "denoise": 1.0,
    }}
    g["decode"] = {"class_type": "VAEDecode", "inputs": {"samples": ["sampler", 0], "vae": ["ckpt", 2]}}
    g["save"] = {"class_type": "SaveImage", "inputs": {"images": ["decode", 0], "filename_prefix": prefix}}
    if cutout:
        _append_cutout(g, cutout, prefix)
    return g


def cutout_only(image_name: str, cutout: CutoutSettings | None = None, prefix: str = "vicky_cut") -> dict:
    """Cut the subject out of an uploaded image. Output node: "save_cutout"."""
    g: dict = {"decode": {"class_type": "LoadImage", "inputs": {"image": image_name}}}
    _append_cutout(g, cutout or CutoutSettings(), prefix)
    return g
