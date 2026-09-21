"""Convert Real-ESRGAN realesr-general-x4v3 to Core ML.

Source weights: BSD-3-Clause, https://github.com/xinntao/Real-ESRGAN
"""
import pathlib
import re
import requests
import torch
import torch.nn as nn
import coremltools as ct

import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
TILE = 256
SCALE = 4

# Two checkpoints, both BSD-3-Clause from the same release page.
#   general-x4v3 : 1.2M params, ~2.4MB. Fast, but barely improves a clean photo.
#   x4plus       : 16.7M params. Much stronger; the tradeoff is size and time.
MODELS = {
    "x4v3": dict(
        url="https://github.com/xinntao/Real-ESRGAN/releases/download/v0.2.5.0/realesr-general-x4v3.pth",
        weights=ROOT / "tools" / "realesr-general-x4v3.pth",
        arch="srvgg",
        product="GeneralX4v3",
    ),
    "x4plus": dict(
        url="https://github.com/xinntao/Real-ESRGAN/releases/download/v0.1.0/RealESRGAN_x4plus.pth",
        weights=ROOT / "tools" / "RealESRGAN_x4plus.pth",
        arch="rrdb",
        product="RealESRGANx4",
    ),
    # Same RRDBNet 64nf23nb as x4plus - a pure weight swap - but fine-tuned
    # from it on jpg/webp re-compression, realistic noise and lens blur.
    # CC-BY-4.0, so commercial use stays available. Ships as safetensors.
    "nomos": dict(
        url="https://github.com/Phhofm/models/releases/download/4xNomosWebPhoto_esrgan/4xNomosWebPhoto_esrgan.safetensors",
        weights=ROOT / "tools" / "4xNomosWebPhoto_esrgan.safetensors",
        arch="rrdb",
        product="NomosWebPhoto",
    ),
    # Same training data as "nomos", different backbone: RealPLKSR instead of
    # RRDBNet. 7.4M parameters against 16.7M, and a 17x17 large kernel applied
    # to a quarter of the channels rather than 23 dense blocks. Pure
    # convolution, so the ANE should take it.
    # The non-GAN twin of x4plus: same RRDBNet, same 16.7M weights shape, but
    # trained with L1 only. No adversarial loss means no invented texture - it
    # is the "faithful" end of the trade, and the reason to have it is that
    # every GAN model reads as digitally sharpened on a decent photograph.
    "esrnet": dict(
        url="https://github.com/xinntao/Real-ESRGAN/releases/download/v0.1.1/RealESRNet_x4plus.pth",
        weights=ROOT / "tools" / "RealESRNet_x4plus.pth",
        arch="rrdb",
        product="RealESRNet",
    ),
    "plksr": dict(
        url="https://github.com/Phhofm/models/releases/download/4xNomosWebPhoto_RealPLKSR/4xNomosWebPhoto_RealPLKSR.safetensors",
        weights=ROOT / "tools" / "4xNomosWebPhoto_RealPLKSR.safetensors",
        arch="realplksr",
        product="NomosPLKSR",
    ),
}
# Selected by argv when run as a script, by SCALLY_MODEL when imported (pytest
# puts the test filename in argv[1], which is not a model name).
def _selected_model() -> str:
    import os
    if len(sys.argv) > 1 and sys.argv[1] in MODELS:
        return sys.argv[1]
    return os.environ.get("SCALLY_MODEL", "x4plus")


MODEL = MODELS[_selected_model()]
WEIGHTS_URL = MODEL["url"]
WEIGHTS = MODEL["weights"]
OUTPUT = ROOT / f"ScallyKit/Sources/ScallyKit/Resources/{MODEL['product']}.mlpackage"


class SRVGGNetCompact(nn.Module):
    """Compact VGG-style super-resolution net used by realesr-general-x4v3."""

    def __init__(self, num_in_ch=3, num_out_ch=3, num_feat=64, num_conv=32, upscale=4):
        super().__init__()
        self.upscale = upscale
        self.body = nn.ModuleList()
        self.body.append(nn.Conv2d(num_in_ch, num_feat, 3, 1, 1))
        self.body.append(nn.PReLU(num_parameters=num_feat))
        for _ in range(num_conv):
            self.body.append(nn.Conv2d(num_feat, num_feat, 3, 1, 1))
            self.body.append(nn.PReLU(num_parameters=num_feat))
        self.body.append(nn.Conv2d(num_feat, num_out_ch * upscale * upscale, 3, 1, 1))
        self.upsampler = nn.PixelShuffle(upscale)

    def forward(self, x):
        out = x
        for layer in self.body:
            out = layer(out)
        out = self.upsampler(out)
        # The reference implementation adds a nearest-neighbour skip connection.
        base = nn.functional.interpolate(x, scale_factor=self.upscale, mode="nearest")
        return out + base


class ResidualDenseBlock(nn.Module):
    def __init__(self, num_feat=64, num_grow_ch=32):
        super().__init__()
        self.conv1 = nn.Conv2d(num_feat, num_grow_ch, 3, 1, 1)
        self.conv2 = nn.Conv2d(num_feat + num_grow_ch, num_grow_ch, 3, 1, 1)
        self.conv3 = nn.Conv2d(num_feat + 2 * num_grow_ch, num_grow_ch, 3, 1, 1)
        self.conv4 = nn.Conv2d(num_feat + 3 * num_grow_ch, num_grow_ch, 3, 1, 1)
        self.conv5 = nn.Conv2d(num_feat + 4 * num_grow_ch, num_feat, 3, 1, 1)
        self.lrelu = nn.LeakyReLU(negative_slope=0.2, inplace=True)

    def forward(self, x):
        x1 = self.lrelu(self.conv1(x))
        x2 = self.lrelu(self.conv2(torch.cat((x, x1), 1)))
        x3 = self.lrelu(self.conv3(torch.cat((x, x1, x2), 1)))
        x4 = self.lrelu(self.conv4(torch.cat((x, x1, x2, x3), 1)))
        x5 = self.conv5(torch.cat((x, x1, x2, x3, x4), 1))
        return x5 * 0.2 + x


class RRDB(nn.Module):
    def __init__(self, num_feat=64, num_grow_ch=32):
        super().__init__()
        self.rdb1 = ResidualDenseBlock(num_feat, num_grow_ch)
        self.rdb2 = ResidualDenseBlock(num_feat, num_grow_ch)
        self.rdb3 = ResidualDenseBlock(num_feat, num_grow_ch)

    def forward(self, x):
        out = self.rdb3(self.rdb2(self.rdb1(x)))
        return out * 0.2 + x


class RRDBNet(nn.Module):
    """Architecture behind RealESRGAN_x4plus."""

    def __init__(self, num_in_ch=3, num_out_ch=3, num_feat=64, num_block=23, num_grow_ch=32):
        super().__init__()
        self.conv_first = nn.Conv2d(num_in_ch, num_feat, 3, 1, 1)
        self.body = nn.Sequential(*[RRDB(num_feat, num_grow_ch) for _ in range(num_block)])
        self.conv_body = nn.Conv2d(num_feat, num_feat, 3, 1, 1)
        self.conv_up1 = nn.Conv2d(num_feat, num_feat, 3, 1, 1)
        self.conv_up2 = nn.Conv2d(num_feat, num_feat, 3, 1, 1)
        self.conv_hr = nn.Conv2d(num_feat, num_feat, 3, 1, 1)
        self.conv_last = nn.Conv2d(num_feat, num_out_ch, 3, 1, 1)
        self.lrelu = nn.LeakyReLU(negative_slope=0.2, inplace=True)

    def forward(self, x):
        feat = self.conv_first(x)
        feat = feat + self.conv_body(self.body(feat))
        feat = self.lrelu(self.conv_up1(
            nn.functional.interpolate(feat, scale_factor=2, mode="nearest")))
        feat = self.lrelu(self.conv_up2(
            nn.functional.interpolate(feat, scale_factor=2, mode="nearest")))
        return self.conv_last(self.lrelu(self.conv_hr(feat)))


def download_weights():
    if WEIGHTS.exists():
        return
    print(f"downloading {WEIGHTS_URL}")
    response = requests.get(WEIGHTS_URL, timeout=180)
    response.raise_for_status()
    WEIGHTS.write_bytes(response.content)


def remap_old_esrgan(state):
    """Old ESRGAN naming (model.0, model.1.sub.N.RDB...) -> BasicSR RRDBNet.

    Community fine-tunes are usually published in the original ESRGAN layout:
        model.0                  -> conv_first
        model.1.sub.{0..22}      -> body.{i}       (the RRDB blocks)
        model.1.sub.23           -> conv_body      (the trunk conv)
        model.3 / 6 / 8 / 10     -> conv_up1 / conv_up2 / conv_hr / conv_last
    """
    import re
    if not any(k.startswith("model.") for k in state):
        return state
    tail = {"3": "conv_up1", "6": "conv_up2", "8": "conv_hr", "10": "conv_last"}
    out = {}
    for key, value in state.items():
        if key.startswith("model.0."):
            out["conv_first." + key.split(".", 2)[2]] = value
        elif key.startswith("model.1.sub.23."):
            out["conv_body." + key.split(".", 4)[4]] = value
        elif key.startswith("model.1.sub."):
            m = re.match(r"model\.1\.sub\.(\d+)\.RDB(\d)\.conv(\d)\.0\.(weight|bias)", key)
            if not m:
                raise KeyError(f"unrecognised block key {key}")
            block, rdb, conv, kind = m.groups()
            out[f"body.{block}.rdb{rdb}.conv{conv}.{kind}"] = value
        else:
            m = re.match(r"model\.(\d+)\.(weight|bias)", key)
            if not m or m.group(1) not in tail:
                raise KeyError(f"unrecognised key {key}")
            out[f"{tail[m.group(1)]}.{m.group(2)}"] = value
    return out


def remap_old_esrgan(state):
    """Old ESRGAN naming (model.0, model.1.sub.N.RDB...) -> BasicSR RRDBNet.

        model.0              -> conv_first
        model.1.sub.{0..22}  -> body.{i}     (the RRDB blocks)
        model.1.sub.23       -> conv_body    (the trunk conv)
        model.3/6/8/10       -> conv_up1 / conv_up2 / conv_hr / conv_last
    """
    if not any(k.startswith("model.") for k in state):
        return state
    tail = {"3": "conv_up1", "6": "conv_up2", "8": "conv_hr", "10": "conv_last"}
    out = {}
    for key, value in state.items():
        if key.startswith("model.0."):
            out["conv_first." + key.split(".", 2)[2]] = value
        elif key.startswith("model.1.sub.23."):
            out["conv_body." + key.split(".", 4)[4]] = value
        elif key.startswith("model.1.sub."):
            m = re.match(r"model\.1\.sub\.(\d+)\.RDB(\d)\.conv(\d)\.0\.(weight|bias)", key)
            if not m:
                raise KeyError(f"unrecognised block key {key}")
            b, rdb, conv, kind = m.groups()
            out[f"body.{b}.rdb{rdb}.conv{conv}.{kind}"] = value
        else:
            m = re.match(r"model\.(\d+)\.(weight|bias)", key)
            if not m or m.group(1) not in tail:
                raise KeyError(f"unrecognised key {key}")
            out[f"{tail[m.group(1)]}.{m.group(2)}"] = value
    return out


class Mish(nn.Module):
    """x * tanh(softplus(x)).

    Written out rather than `nn.Mish` because coremltools has no converter for
    `aten::mish`. This is the definition, so parity with the reference is exact
    rather than approximate.
    """

    def forward(self, x):
        return x * torch.tanh(nn.functional.softplus(x))


class DCCM(nn.Sequential):
    """Doubled convolutional channel mixer."""

    def __init__(self, dim):
        super().__init__(
            nn.Conv2d(dim, dim * 2, 3, 1, 1),
            Mish(),
            nn.Conv2d(dim * 2, dim, 3, 1, 1),
        )


class PLKConv2d(nn.Module):
    """Partial large kernel: a 17x17 convolution over the first quarter of the
    channels only, the rest passed through untouched.

    Upstream has two forward paths and uses an in-place slice assignment at
    inference. That cannot be traced, so the split/concatenate path is used
    unconditionally here - it is the same arithmetic.
    """

    def __init__(self, dim, kernel_size):
        super().__init__()
        self.conv = nn.Conv2d(dim, dim, kernel_size, 1, kernel_size // 2)
        self.idx = dim

    def forward(self, x):
        x1, x2 = torch.split(x, [self.idx, x.size(1) - self.idx], dim=1)
        return torch.cat([self.conv(x1), x2], dim=1)


class EA(nn.Module):
    """Element-wise attention: a learned per-pixel gate."""

    def __init__(self, dim):
        super().__init__()
        self.f = nn.Sequential(nn.Conv2d(dim, dim, 3, 1, 1), nn.Sigmoid())

    def forward(self, x):
        return x * self.f(x)


class PLKBlock(nn.Module):
    """The order here is load-bearing and is not guessable from the weights:
    mixer, large kernel, attention, refine, normalise, then the skip. A
    plausible-looking reordering still loads with strict=True and still
    produces an image - just the wrong one.
    """

    def __init__(self, dim, kernel_size, pdim, norm_groups, use_ea):
        super().__init__()
        self.channel_mixer = DCCM(dim)
        self.lk = PLKConv2d(pdim, kernel_size)
        self.attn = EA(dim) if use_ea else nn.Identity()
        self.refine = nn.Conv2d(dim, dim, 1, 1, 0)
        self.norm = nn.GroupNorm(norm_groups, dim)

    def forward(self, x):
        skip = x
        x = self.channel_mixer(x)
        x = self.lk(x)
        x = self.attn(x)
        x = self.refine(x)
        x = self.norm(x)
        return x + skip


class RealPLKSR(nn.Module):
    """https://arxiv.org/abs/2404.11848, as implemented by neosr.

    Defaults are neosr's, which is what `4xNomosWebPhoto_RealPLKSR.yml` asks
    for: `type: realplksr` with nothing overridden but training-time dropout.

    `feats` is one Sequential so the checkpoint's flat indices line up: 0 is the
    stem, 1..28 the blocks, 29 a parameterless Dropout2d, 30 the tail. The
    dropout has no weights but it does occupy an index, and removing it would
    shift the tail to 29 and break a strict load.
    """

    def __init__(self, in_ch=3, out_ch=3, dim=64, n_blocks=28, upscaling_factor=4,
                 kernel_size=17, split_ratio=0.25, use_ea=True, norm_groups=4):
        super().__init__()
        self.upscale = upscaling_factor
        pdim = int(dim * split_ratio)
        self.feats = nn.Sequential(
            *([nn.Conv2d(in_ch, dim, 3, 1, 1)]
              + [PLKBlock(dim, kernel_size, pdim, norm_groups, use_ea)
                 for _ in range(n_blocks)]
              + [nn.Dropout2d(0.0)]
              + [nn.Conv2d(dim, out_ch * upscaling_factor ** 2, 3, 1, 1)])
        )
        self.to_img = nn.PixelShuffle(upscaling_factor)

    def forward(self, x):
        # The global residual is repeat_interleave(x, 16, dim=1), which after
        # the pixel shuffle is exactly a nearest-neighbour 4x of the input. It
        # is written as expand+reshape because coremltools handles those and
        # does not handle repeat_interleave.
        batch, channels, height, width = x.shape
        repeats = self.upscale ** 2
        skip = (x.unsqueeze(2)
                 .expand(batch, channels, repeats, height, width)
                 .reshape(batch, channels * repeats, height, width))
        # Clamped to match the author's own ONNX export. Without it this model
        # matches that export to 3.5e-1 in the worst pixel; with it, to 6.3e-6.
        # 1.75% of pixels land outside [0,1] on a random input, so the clamp is
        # not cosmetic - it is part of the model as published.
        return self.to_img(self.feats(x) + skip).clamp(0.0, 1.0)


def load_model():
    download_weights()
    if WEIGHTS.suffix == ".safetensors":
        from safetensors.torch import load_file
        state = load_file(str(WEIGHTS))
    else:
        state = torch.load(WEIGHTS, map_location="cpu", weights_only=True)
    weights = state.get("params") or state.get("params_ema") or state
    if MODEL["arch"] == "rrdb":
        # Only the ESRGAN lineage carries the legacy "model.N." key layout.
        weights = remap_old_esrgan(weights)
    model = {
        "srvgg": SRVGGNetCompact,
        "rrdb": RRDBNet,
        "realplksr": RealPLKSR,
    }[MODEL["arch"]]()
    model.load_state_dict(weights, strict=True)
    model.eval()
    return model


def main():
    model = load_model()
    example = torch.rand(1, 3, TILE, TILE)
    traced = torch.jit.trace(model, example)

    mlmodel = ct.convert(
        traced,
        inputs=[ct.TensorType(name="input", shape=(1, 3, TILE, TILE), dtype=float)],
        outputs=[ct.TensorType(name="output", dtype=float)],
        compute_precision=ct.precision.FLOAT16,
        compute_units=ct.ComputeUnit.ALL,
        minimum_deployment_target=ct.target.iOS18,
    )
    parameters = sum(p.numel() for p in model.parameters())
    mlmodel.short_description = (
        f"Real-ESRGAN {MODEL['arch']} 4x super-resolution, {parameters/1e6:.1f}M parameters. "
        "Weights BSD-3-Clause, Xintao Wang et al."
    )
    print(f"architecture={MODEL['arch']} parameters={parameters/1e6:.2f}M")
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    mlmodel.save(str(OUTPUT))
    print(f"wrote {OUTPUT}")


if __name__ == "__main__":
    main()
