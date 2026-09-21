"""Convert a spandrel-loadable super-resolution checkpoint to Core ML.

The ESRGAN and RealPLKSR converters in `convert.py` hand-write their
architectures. That is the right call for a network small enough to verify
against the author's own export, and the wrong one for DAT or DRCT, which are
thousands of lines of window attention. spandrel already implements them and
auto-detects the architecture from the checkpoint, so this uses that and
concentrates on the part that is actually hard: getting shifted-window
attention through coremltools.

    uv run --python tools/.venv/bin/python tools/convert_transformer.py \
        tools/4xNomos2_hq_drct-l.safetensors DRCTL
"""
import sys
import pathlib
import time

import torch
import coremltools as ct
from spandrel import ModelLoader

ROOT = pathlib.Path(__file__).resolve().parent.parent
TILE = 256


def _detach(value):
    """DRCT returns one mask; DAT returns a pair, one per window shape."""
    if isinstance(value, torch.Tensor):
        return value.detach().clone()
    if isinstance(value, (tuple, list)):
        return type(value)(_detach(v) for v in value)
    return value


def freeze_attention_masks(model, example) -> int:
    """Replace every `calculate_mask` with the constant it returns.

    Shifted-window attention builds its mask with negative-index slices
    (`slice(-window, -shift)`). Tracing turns those into absolute indices, and
    coremltools rejects the result: `slice_by_index ... (begin, end, stride) :
    (240, 0, 1)`. The mask is not data - it depends only on the tile size,
    which is fixed here - so it is computed once in eager mode, where the
    slicing is fine, and pinned as a constant before the trace ever sees it.
    """
    captured: dict[str, torch.Tensor] = {}
    original: dict[str, object] = {}

    for name, module in model.named_modules():
        if not hasattr(module, "calculate_mask"):
            continue
        original[name] = module.calculate_mask

        def wrap(key, fn):
            # Signature varies by architecture: DRCT takes (x_size), DAT takes
            # (x_size, dtype=...). Pass everything through untouched.
            def recording(*args, **kwargs):
                result = fn(*args, **kwargs)
                captured[key] = _detach(result)
                return result
            return recording

        module.calculate_mask = wrap(name, module.calculate_mask)

    with torch.no_grad():
        model(example)

    for name, module in model.named_modules():
        if name in captured:
            module.calculate_mask = (
                lambda c: (lambda *_args, **_kwargs: c)
            )(captured[name])
        elif name in original:
            # Never called: this block's input_resolution already matched, so
            # it uses its registered buffer and needs no help.
            module.calculate_mask = original[name]
    return len(captured)


def main() -> None:
    source = pathlib.Path(sys.argv[1])
    product = sys.argv[2]
    output = ROOT / f"ScallyKit/Sources/ScallyKit/Resources/{product}.mlpackage"

    descriptor = ModelLoader().load_from_file(str(source))
    model = descriptor.model.eval()
    parameters = sum(p.numel() for p in model.parameters())
    print(f"{descriptor.architecture.name}  {parameters/1e6:.2f}M params  "
          f"scale {descriptor.scale}  tags={descriptor.tags}")

    example = torch.rand(1, 3, TILE, TILE)
    frozen = freeze_attention_masks(model, example)
    print(f"froze {frozen} attention masks at {TILE}x{TILE}")

    started = time.time()
    with torch.no_grad():
        traced = torch.jit.trace(model, example, check_trace=False)
    print(f"traced in {time.time()-started:.1f}s")

    started = time.time()
    mlmodel = ct.convert(
        traced,
        inputs=[ct.TensorType(name="input", shape=(1, 3, TILE, TILE), dtype=float)],
        outputs=[ct.TensorType(name="output", dtype=float)],
        compute_precision=ct.precision.FLOAT16,
        compute_units=ct.ComputeUnit.ALL,
        minimum_deployment_target=ct.target.iOS18,
    )
    mlmodel.short_description = (
        f"{descriptor.architecture.name} 4x super-resolution, "
        f"{parameters/1e6:.1f}M parameters. Weights CC BY 4.0, Philip Hofmann."
    )
    print(f"converted in {time.time()-started:.1f}s")
    output.parent.mkdir(parents=True, exist_ok=True)
    mlmodel.save(str(output))
    print(f"wrote {output}")


if __name__ == "__main__":
    main()
