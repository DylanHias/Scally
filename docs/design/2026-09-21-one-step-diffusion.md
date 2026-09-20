# One-step diffusion super-resolution - conversion proven, not yet integrated

Status as of 2026-09-21, 00:10. **The app still ships Real-ESRGAN x4plus.**
Nothing below is wired into Scally; it is proven in Python and on-device
benchmarks only.

## What works

**Model:** RSD - one-step residual-shifting diffusion, distilled from a 15-step
ResShift teacher (paper arXiv 2503.13358, repo github.com/Daniil-Selikhanovych/RSD).
118.60M parameters, loaded from the authors' own `ema_model_2800.pth` with an
exact state-dict match (0 missing, 0 unexpected).

**Converted to Core ML** (all three, FP16):

| Component | Size | Shapes |
|---|---|---|
| UNet (one step) | 240 MB | x/lq 1x3x64x64, noise 1x1x64x64, t 1 |
| VQ encoder (f4) | 45 MB | 1x3x256x256 -> 1x3x64x64 |
| VQ decoder | 66 MB | 1x3x64x64 -> 1x3x256x256 |
| **Total** | **351 MB** | |

**Measured on iPhone 17 Pro, Release:**

| Compute unit | ms per 64x64 latent patch |
|---|---|
| CPU + GPU | 31 |
| ANE (.all) | 33 |
| CPU only | 60 |

GPU marginally beats the ANE, so Swin attention is partly falling back - it does
not matter at this speed. A 3249x2262 photo at 4x is 12996x9048 output = 1836
latent patches, so roughly **1 minute**, plus VAE and tiling overhead.

**Quality is confirmed real.** Against a bicubic upscale of the same degraded
input, the model produces sharp, defined structure where bicubic gives smeared
blobs. It invents detail rather than sharpening what survived - a different
class of result from any CNN.

## The five things that blocked it

1. **The Hugging Face licence tag is wrong.** `sorryhyun/Distilled-ResShift-4x`
   is tagged `cc-by-sa-4.0`, but ResShift is **S-Lab License 1.0** and RSD is
   **CC BY-NC-SA 4.0** - both non-commercial. The weights inherit that. Usable
   only because Scally is free, and it locks the app to free permanently.
2. **Wrong weights.** That HF repo is a third-party ComfyUI distillation, not
   the authors' release, and it never produced correct output. The official
   Google Drive checkpoint did.
3. **`torch.roll` does not convert.** coremltools lowers it to a slice with
   `end=0` and treats that as empty. Replaced with a positive-index equivalent.
4. **An upstream bug in RSD's Swin code.** `if self.input_resolution == x_size`
   compares a **list against a tuple**, which is always False in Python, so
   every block rebuilt its attention mask inside `forward` instead of using the
   precomputed buffer. That path contains negative-index slice assignment, which
   cannot be converted. Fixing it exposed a `None` dereference beneath, proving
   the fast path had never executed - so their published inference is also
   slower than intended.
5. **`lq` is pixel-space, not latent.** `sampler.py` passes
   `model_kwargs = {'lq': y0}`: the LQ image at its ORIGINAL resolution. An f=4
   latent of the 4x-upsampled image is exactly the size of the original LQ, so
   they concatenate directly. Feeding the encoded latent produced washed-out
   garbage. This is what `cond_lq: pixel` in the checkpoint metadata meant.

## Remaining work to actually ship it

1. Numerical parity: Core ML vs PyTorch for all three models.
2. Port the one-step sampling to Swift: `z_T = z_y + kappa*sqrt_etas[T]*noise`
   with kappa 2.0, `etas_end` 0.99, `timesteps_with_zeros = [14, 0]`, plus
   `_scale_input` normalisation. **This is where a subtle error produces
   plausible-but-wrong output**, so it needs parity tests, not eyeballing.
3. Latent-space tiling with overlap, replacing the current pixel tiler.
4. A second `Upscaler` implementation behind the existing protocol, so x4plus
   stays available and the choice is a user setting.

## Reproduction

Scratch work is in the session scratchpad, not the repo: `convert_rsd.py`,
`convert_vae.py`, `quality_test.py`, plus a `shim/` providing minimal timm,
wandb and ipdb stubs so the research code imports without its training
dependencies. The repo's `.cuda()` calls were stripped to run on Apple silicon.
