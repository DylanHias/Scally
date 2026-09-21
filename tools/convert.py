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


def load_model():
    download_weights()
    if WEIGHTS.suffix == ".safetensors":
        from safetensors.torch import load_file
        state = load_file(str(WEIGHTS))
    else:
        state = torch.load(WEIGHTS, map_location="cpu", weights_only=True)
    weights = state.get("params") or state.get("params_ema") or state
    weights = remap_old_esrgan(weights)
    weights = remap_old_esrgan(weights)
    model = SRVGGNetCompact() if MODEL["arch"] == "srvgg" else RRDBNet()
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
