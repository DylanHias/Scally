"""Convert Real-ESRGAN realesr-general-x4v3 to Core ML.

Source weights: BSD-3-Clause, https://github.com/xinntao/Real-ESRGAN
"""
import pathlib
import requests
import torch
import torch.nn as nn
import coremltools as ct

WEIGHTS_URL = (
    "https://github.com/xinntao/Real-ESRGAN/releases/download/"
    "v0.2.5.0/realesr-general-x4v3.pth"
)
ROOT = pathlib.Path(__file__).resolve().parent.parent
WEIGHTS = ROOT / "tools" / "realesr-general-x4v3.pth"
OUTPUT = ROOT / "ScallyKit/Sources/ScallyKit/Resources/RealESRGANx4.mlpackage"
TILE = 256
SCALE = 4


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


def download_weights():
    if WEIGHTS.exists():
        return
    print(f"downloading {WEIGHTS_URL}")
    response = requests.get(WEIGHTS_URL, timeout=180)
    response.raise_for_status()
    WEIGHTS.write_bytes(response.content)


def load_model():
    download_weights()
    state = torch.load(WEIGHTS, map_location="cpu", weights_only=True)
    weights = state.get("params") or state.get("params_ema") or state
    model = SRVGGNetCompact()
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
    mlmodel.short_description = (
        "Real-ESRGAN realesr-general-x4v3, 4x super-resolution. "
        "Weights BSD-3-Clause, Xintao Wang et al."
    )
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    mlmodel.save(str(OUTPUT))
    print(f"wrote {OUTPUT}")


if __name__ == "__main__":
    main()
