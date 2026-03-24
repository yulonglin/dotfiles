# Modal GPU Reference

## Available GPU Types

Modal supports the following GPU types via the `gpu` parameter:

| GPU | VRAM | Typical Use Case |
|-----|------|-----------------|
| `T4` | 16 GB | Inference, light fine-tuning, budget workloads |
| `L4` | 24 GB | Inference, moderate training, good price/perf |
| `A10G` | 24 GB | Inference, fine-tuning, general ML |
| `A100-40GB` | 40 GB | Training, large model inference |
| `A100-80GB` (or `A100`) | 80 GB | Large-scale training, big models |
| `L40S` | 48 GB | Training and inference, good throughput |
| `H100` / `H100!` | 80 GB | Fastest training, large model serving |
| `H200` | 141 GB | Very large models, highest memory |
| `B200` | 192 GB | Next-gen, largest models |

`H100!` requests a dedicated H100 (vs shared).

## Requesting a GPU

Use the `gpu` parameter on `@app.function()`:

```python
import modal

app = modal.App("gpu-example")

@app.function(gpu="A10G")
def train_model():
    import torch
    print(f"CUDA available: {torch.cuda.is_available()}")
    print(f"GPU: {torch.cuda.get_device_name(0)}")
```

String values are case-insensitive (`"a10g"` and `"A10G"` both work).

## Multi-GPU

Append `:<count>` to request multiple co-located GPUs:

```python
@app.function(gpu="A100-80GB:2")
def train_large_model():
    import torch
    print(f"GPU count: {torch.cuda.device_count()}")  # 2
```

```python
@app.function(gpu="H100:8")
def distributed_training():
    # 8x H100 in one container
    ...
```

## GPU Fallback Chains

Pass a list of GPU types in order of preference. Modal tries to allocate the first type and falls back to subsequent options:

```python
@app.function(gpu=["H100", "A100-40GB:2"])
def run_on_80gb():
    # Prefers a single H100 (80GB), falls back to 2x A100-40GB (80GB total)
    ...
```

```python
@app.function(
    gpu=["h100", "a100", "any"],  # "any" means any of L4, A10, or T4
    max_inputs=1,  # new container per input, re-rolls GPU each time
)
async def flexible_inference(_idx):
    import subprocess
    gpu = subprocess.run(
        ["nvidia-smi", "--query-gpu=name", "--format=csv,noheader"],
        check=True, text=True, stdout=subprocess.PIPE,
    ).stdout.strip()
    return gpu
```

The special value `"any"` matches any of L4, A10, or T4. Fallback chains are useful when GPU availability fluctuates, especially for tightly-constrained requests (e.g., 8 co-located GPUs in a specific region).

## PyTorch + CUDA Setup

Modal's `debian_slim` image works with CUDA out of the box -- no `nvidia/cuda` base image needed:

```python
image = (
    modal.Image.debian_slim(python_version="3.11")
    .pip_install("torch", "transformers")
)

@app.function(gpu="A10G", image=image)
def inference():
    import torch
    assert torch.cuda.is_available()
```

Modal handles the NVIDIA driver and CUDA runtime when you specify `gpu=`.

## Cost Guidance

| Workload | Recommended GPU | Why |
|----------|----------------|-----|
| Light inference / prototyping | `T4` or `L4` | Cheapest, sufficient for small models |
| Standard inference / fine-tuning | `A10G` or `L4` | Good price/performance balance |
| Large model inference (7B-13B) | `A100-40GB` or `L40S` | Enough VRAM for medium LLMs |
| Large model training | `A100-80GB` or `H100` | High memory + fast interconnect |
| Very large models (70B+) | `H100:2+` or `H200` | Multi-GPU or highest single-GPU memory |
| Maximum scale | `B200` or `H100:8` | Largest models, fastest training |

Use fallback chains to balance cost vs availability:

```python
# Prefer cheap, fall back to more expensive
@app.function(gpu=["L4", "A10G", "A100-40GB"])
def cost_aware_inference():
    ...
```

Refer to [Modal pricing](https://modal.com/pricing) for current per-GPU-second rates.
