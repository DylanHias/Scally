# One-step diffusion super-resolution on iPhone - feasibility probe

Run 2026-09-20 on Dylan's iPhone 17 Pro, Release build. The question: is a
Stable-Diffusion-scale model runnable on-device, which would allow one-step
diffusion super-resolution (OSEDiff class) instead of a convolutional upscaler.

## Result: yes

Apple's own Core ML conversion of SD 2.1 Base, `split_einsum_v2`, palettized
(`apple/coreml-stable-diffusion-2-1-base-palettized`). UNet only, dummy inputs,
3 timed passes after a warm-up.

| Compute unit | Per batch-2 pass | Implied batch-1 | Load time |
|---|---|---|---|
| CPU only | 816 ms | 408 ms | 4.1 s |
| CPU + GPU | 425 ms | 213 ms | 10.9 s |
| **ANE (`.all`)** | **242 ms** | **~121 ms** | 53.8 s |

The shipped model runs batch 2 for classifier-free guidance. One-step SR needs
no CFG, so the batch-1 figure is the relevant one: **about 121 ms per UNet pass
on the Neural Engine**.

The 53.8 s ANE load is a one-time graph specialisation, cached afterwards.

## Memory

`os_proc_available_memory()` reported **6434 MB** with the
`com.apple.developer.kernel.increased-memory-limit` entitlement, against
**3429 MB** measured without it earlier the same day. The entitlement is
required: the first two probe runs were killed by jetsam (signal 9) during
model load before it was added and before the ANE compile cache was warm.

## Sizes

| Component | Palettized |
|---|---|
| SD 2.1 UNet (split_einsum_v2) | 622 MB |
| Plus VAE encoder/decoder | roughly 750 MB total |
| Current Real-ESRGAN x4plus | 33 MB |

## What this implies for Scally

A 512x512 output tile costs one UNet pass plus VAE encode/decode, so roughly
0.4-0.5 s per tile. For a 3249x2262 source:

- 2x (6498x4524 output): about 117 tiles, roughly **1 minute**
- 4x (12996x9048 output): about 468 tiles, roughly **4 minutes**

Feasible, but it changes the product:

1. **The app can no longer be a 34 MB download.** ~750 MB of weights means a
   first-launch download. "Nothing is uploaded" survives; "no internet at all"
   does not.
2. **The increased-memory entitlement becomes mandatory**, and Apple requires a
   justification for it at review.
3. **Licensing**: OSEDiff's code is Apache-2.0, but the SD 2.1 weights beneath
   carry CreativeML Open RAIL++-M - commercial use permitted, with use-based
   restrictions that must be passed downstream. OSEDiff also pulls RAM and DAPE
   for prompt extraction, which have not been checked.
4. **Conversion is unproven.** No public Core ML OSEDiff exists. This probe
   shows the *runtime* is viable; it does not show the conversion is.

## Unmeasured

VAE encode/decode latency, real OSEDiff quality on Dylan's photos, and thermal
behaviour over a multi-minute run. The 0.4-0.5 s/tile figure assumes VAE cost
similar to the UNet and should be treated as an estimate, not a measurement.
