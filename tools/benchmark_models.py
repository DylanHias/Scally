"""Benchmark every bundled Core ML upscaler against real photographs.

Three things are measured, because speed alone has never been the question:

  speed    ms per 256x256 tile, on the Neural Engine and on CPU+GPU. The gap
           between them says whether the ANE is really being used.

  fidelity PSNR and SSIM against ground truth. A real photograph is
           downsampled 4x and each model asked to put it back; the original is
           the answer sheet.

  detail   mean |Laplacian| of the output over that of the truth. This is the
           one that matters for "it looks digitalised". At 1.00 a model
           resolves exactly as much fine structure as the camera did. Above
           1.00 it is inventing texture that was never photographed; below, it
           is softer than the original. GAN-trained models sit well above 1.

Run:  tools/.venv/bin/python tools/benchmark_models.py
"""
import pathlib
import time

import numpy as np
import coremltools as ct
from PIL import Image, ImageFilter

ROOT = pathlib.Path(__file__).resolve().parent.parent
RESOURCES = ROOT / "ScallyKit/Sources/ScallyKit/Resources"
TILE = 256
# The low-resolution input must fill the tile exactly. Padding a smaller image
# into a 256x256 canvas puts a hard black edge inside the model's receptive
# field, and the resulting boundary artefacts were visible as a grid in the
# output - penalising every model for something the real tiled pipeline never
# does.
LOW = TILE
CROP = LOW * 4


def gaussian(image: np.ndarray, sigma: float = 1.5) -> np.ndarray:
    radius = int(3 * sigma)
    x = np.arange(-radius, radius + 1)
    k = np.exp(-(x ** 2) / (2 * sigma ** 2))
    k /= k.sum()
    out = np.apply_along_axis(lambda r: np.convolve(r, k, "same"), 0, image)
    return np.apply_along_axis(lambda r: np.convolve(r, k, "same"), 1, out)


def ssim(a: np.ndarray, b: np.ndarray) -> float:
    a = a.mean(axis=2).astype(np.float64)
    b = b.mean(axis=2).astype(np.float64)
    c1, c2 = (0.01 * 255) ** 2, (0.03 * 255) ** 2
    mu_a, mu_b = gaussian(a), gaussian(b)
    sa = gaussian(a * a) - mu_a ** 2
    sb = gaussian(b * b) - mu_b ** 2
    sab = gaussian(a * b) - mu_a * mu_b
    num = (2 * mu_a * mu_b + c1) * (2 * sab + c2)
    den = (mu_a ** 2 + mu_b ** 2 + c1) * (sa + sb + c2)
    return float((num / den).mean())


def psnr(a: np.ndarray, b: np.ndarray) -> float:
    mse = ((a.astype(np.float64) - b.astype(np.float64)) ** 2).mean()
    return float("inf") if mse == 0 else 10 * np.log10(255 * 255 / mse)


def detail(image: np.ndarray) -> float:
    """Mean absolute Laplacian: how much fine structure is present."""
    g = image.mean(axis=2).astype(np.float64)
    lap = (-4 * g
           + np.roll(g, 1, 0) + np.roll(g, -1, 0)
           + np.roll(g, 1, 1) + np.roll(g, -1, 1))
    return float(np.abs(lap[2:-2, 2:-2]).mean())


def degrade(image: Image.Image, kind: str) -> Image.Image:
    """Two degradations, because one of them flatters Lanczos unfairly.

    "clean" downsamples with Lanczos, and a Lanczos upsample is very nearly
    its inverse - so plain resampling scores artificially well and every model
    is penalised for correcting damage that is not there. "real" adds the lens
    softness and JPEG that an actual phone photograph carries, which is what
    these models were trained to undo.
    """
    small = image.resize((LOW, LOW), Image.LANCZOS)
    if kind == "clean":
        return small
    import io
    small = small.filter(ImageFilter.GaussianBlur(0.5))
    buffer = io.BytesIO()
    small.save(buffer, "JPEG", quality=60)
    return Image.open(io.BytesIO(buffer.getvalue())).convert("RGB")


def upscale(model, low: Image.Image) -> Image.Image:
    array = np.asarray(low, np.float32).transpose(2, 0, 1)[None] / 255.0
    out = model.predict({"input": array})["output"][0].transpose(1, 2, 0)
    out = (np.clip(out, 0, 1) * 255).astype(np.uint8)
    return Image.fromarray(out).crop((0, 0, low.width * 4, low.height * 4))


def load(path, unit):
    return ct.models.MLModel(str(path), compute_units=unit)


def main() -> None:
    sources = sorted(pathlib.Path(
        pathlib.Path.home() /
        "Library/Developer/CoreSimulator/Devices").rglob("DCIM/100APPLE/*.JPG"))[:4]
    if not sources:
        raise SystemExit("no sample photographs found")

    crops = []
    for path in sources:
        image = Image.open(path).convert("RGB")
        # Pick the most detailed region rather than the centre: a benchmark run
        # on flat sky or a single petal measures nothing.
        array = np.asarray(image.convert("L"), np.float64)
        best, best_score = (0, 0), -1.0
        step = max(CROP // 2, 128)
        for y in range(0, max(1, image.height - CROP), step):
            for x in range(0, max(1, image.width - CROP), step):
                patch = array[y:y + CROP, x:x + CROP]
                if patch.shape != (CROP, CROP):
                    continue
                if (score := patch.std()) > best_score:
                    best, best_score = (x, y), score
        x, y = best
        crops.append(image.crop((x, y, x + CROP, y + CROP)))
    print(f"{len(crops)} photographs, {CROP}x{CROP} centre crops, downsampled to {LOW}x{LOW}\n")

    packages = sorted(p for p in RESOURCES.glob("*.mlpackage"))
    lows = [c.resize((LOW, LOW), Image.LANCZOS) for c in crops]

    del lows
    inputs = {k: [degrade(c, k) for c in crops] for k in ("clean", "real")}

    def score(outs):
        return (np.mean([psnr(np.asarray(o), np.asarray(t)) for o, t in zip(outs, crops)]),
                np.mean([ssim(np.asarray(o), np.asarray(t)) for o, t in zip(outs, crops)]),
                np.mean([detail(np.asarray(o)) / detail(np.asarray(t))
                         for o, t in zip(outs, crops)]))

    rows = []
    # Lanczos is the honest floor: what you get for no model at all.
    rows.append(("Lanczos (no model)", None, None,
                 score([low.resize((CROP, CROP), Image.LANCZOS) for low in inputs["clean"]]),
                 score([low.resize((CROP, CROP), Image.LANCZOS) for low in inputs["real"]])))

    for package in packages:
        name = package.stem
        try:
            ane = load(package, ct.ComputeUnit.ALL)
            cpu = load(package, ct.ComputeUnit.CPU_AND_GPU)
        except Exception as error:
            print(f"{name}: could not load ({str(error)[:60]})")
            continue

        probe = inputs["real"][0]
        timings = []
        for model in (ane, cpu):
            try:
                upscale(model, probe)
                start = time.time()
                for _ in range(3):
                    upscale(model, probe)
                timings.append((time.time() - start) / 3 * 1000)
            except Exception:
                timings.append(float("nan"))

        rows.append((name, timings[0], timings[1],
                     score([upscale(cpu, low) for low in inputs["clean"]]),
                     score([upscale(cpu, low) for low in inputs["real"]])))

    header = (f"{'model':20s} {'ANE':>8s} {'CPU+GPU':>9s} | "
              f"{'PSNR':>6s} {'SSIM':>6s} {'detail':>7s} | "
              f"{'PSNR':>6s} {'SSIM':>6s} {'detail':>7s}")
    print(f"{'':41s}   --- clean input ---      --- realistic input ---")
    print(header)
    print("-" * len(header))
    for name, a, c, clean, real in sorted(rows, key=lambda r: -r[4][1]):
        af = "   n/a" if a is None else ("  fail" if a != a else f"{a:5.0f}ms")
        cf = "    n/a" if c is None else ("   fail" if c != c else f"{c:6.0f}ms")
        print(f"{name:20s} {af:>8s} {cf:>9s} | "
              f"{clean[0]:6.2f} {clean[1]:6.4f} {clean[2]:6.2f}x | "
              f"{real[0]:6.2f} {real[1]:6.4f} {real[2]:6.2f}x")
    print("\ndetail: 1.00 = resolves exactly what the camera did.")
    print("        >1.00 = inventing texture that was never photographed.")
    print("        <1.00 = softer than the original.")


if __name__ == "__main__":
    main()
