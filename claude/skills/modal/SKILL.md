---
name: modal
description: Run Python code in the cloud with serverless containers, GPUs, and autoscaling. Use when deploying ML models, running batch processing jobs, scheduling compute-intensive tasks, or serving APIs that require GPU acceleration or dynamic scaling.
---

# Modal

## Overview

Modal is a serverless platform for running Python code in the cloud with minimal configuration. Execute functions on powerful GPUs, scale automatically to thousands of containers, and pay only for compute used.

Sign up at https://modal.com ($30/month free credits).

## When to Use This Skill

- GPU-accelerated training or inference
- Batch processing / parallel `.map()` over inputs
- Scheduled jobs (cron)
- Serverless ML API endpoints
- Scientific computing on specialized hardware

## Setup

```bash
uv add --dev modal     # dev dep — only needed locally, not in containers
modal token new        # opens browser for auth → saves to ~/.modal.toml
```

## Core Concepts

### Images: Container Environment

`debian_slim()` is the default base — a minimal Debian image with Python. PyTorch bundles its own CUDA, so you don't need an nvidia base image.

**Preferred: `uv_sync()` for existing projects** — reads `pyproject.toml` + `uv.lock`:

```python
image = (
    modal.Image.debian_slim(python_version="3.12")
    .uv_sync()  # installs from lockfile — deps never drift
)
```

**Alternative: explicit packages** (for standalone scripts without pyproject.toml):

```python
image = (
    modal.Image.debian_slim(python_version="3.12")
    .uv_pip_install("torch==2.5.1", "transformers==4.46.0")  # pin tightly
)
```

Pin versions for reproducibility. Each change invalidates the image cache layer.

Also available: `.pip_install_from_pyproject("pyproject.toml")` (uses pip, slower than uv).

### Getting Local Code into Containers

Three methods, from most to least common:

```python
# Named package — best for multi-file projects (requires __init__.py)
image = image.add_local_python_source("my_package")

# Entire directory — includes non-.py files too
image = image.add_local_dir("src/", remote_path="/root/src")

# Single file — when you only need one script
image = image.add_local_file("train.py", "/root/train.py")
```

**IMPORTANT — `add_local_python_source(".")` requires a proper Python package** (directory with `__init__.py`). It fails with `ModuleNotMountable("no package specified for '.'")` for loose scripts. Use a named package: `add_local_python_source("my_package")`.

**IMPORTANT — ordering constraint:** `add_local_file` / `add_local_python_source` MUST come AFTER all build steps (`uv_pip_install`, `run_function`, `run_commands`). Modal mounts these at container startup, not build time. Build steps after local mounts cause: `InvalidError('An image tried to run a build step after using image.add_local_*')`. Set `copy=True` to copy into the image layer if you need build steps after.

By default (`copy=False`), files are added at container startup (fast re-deploys — image doesn't rebuild when code changes). Set `copy=True` to bake into the image layer (needed if subsequent build steps depend on those files).

### Functions

Functions run in the cloud. **Import heavy packages inside the function body** — they exist in the container but may not be installed locally:

```python
@app.function(image=image, gpu="A10G")
def train():
    import torch  # ← inside body, not at top of file
    assert torch.cuda.is_available()
```

**Why inside the body?** Modal serializes function definitions locally and runs them remotely. Top-level `import torch` would fail locally if torch isn't installed on your laptop.

Alternative — use the `imports()` context manager for module-level imports:

```python
with image.imports():
    import torch  # deferred — only runs in container
```

### Calling Functions

```python
@app.local_entrypoint()
def main():
    result = train.remote()  # runs on Modal
    print(result)
```

CLI args are auto-parsed from `local_entrypoint` type hints:

```python
@app.local_entrypoint()
def main(lr: float = 0.001, epochs: int = 10):
    train.remote(lr, epochs)
```

Run: `modal run train.py --lr 0.01 --epochs 20`

### GPUs

```python
@app.function(gpu="A10G")       # 24GB, cost-effective
@app.function(gpu="L40S")       # 48GB, best value for inference
@app.function(gpu="A100")       # 40/80GB, training
@app.function(gpu="H100")       # top-tier training
@app.function(gpu="H100:4")     # multi-GPU
@app.function(gpu=["H100", "A100-40GB:2"])  # fallback chain
```

PyTorch bundles CUDA — `debian_slim` works fine, no nvidia base image needed.

### Volumes: Persistent Storage

Network-attached filesystem that persists across runs. Good for datasets and experiment outputs. **Not** as fast as local SSD (image layers) — use volumes for data that changes, not for static model weights.

```python
vol = modal.Volume.from_name("my-data", create_if_missing=True)

@app.function(volumes={"/data": vol})
def save_results():
    with open("/data/results.json", "w") as f:
        json.dump(results, f)
    vol.commit()  # persist changes (also auto-commits on exit)
```

### Model Weights: Bake into Image

For static model weights, **bake into the image** via `run_function()` — not a volume. Image layers are cached on local SSD; volumes are network reads on every cold start.

```python
HF_SECRET = modal.Secret.from_name("huggingface-secret")

def download_model():
    from huggingface_hub import snapshot_download
    # Use unsloth/ mirrors to avoid HF gated model access issues
    snapshot_download("unsloth/Llama-3.2-1B-Instruct", cache_dir="/models")

image = (
    modal.Image.debian_slim(python_version="3.12")
    .uv_sync()
    .uv_pip_install("huggingface_hub[hf_transfer]")  # fast Rust-based downloads
    .env({"HF_HOME": "/models", "HF_HUB_ENABLE_HF_TRANSFER": "1"})
    .run_function(download_model, secrets=[HF_SECRET])
    # add_local_* MUST come after all build steps
)
```

First build downloads the model; subsequent builds reuse the cached image layer.

### Secrets

```bash
modal secret create huggingface-secret HF_TOKEN="hf_xxx"
```

```python
@app.function(secrets=[modal.Secret.from_name("huggingface-secret")])
def use_model():
    import os
    token = os.environ["HF_TOKEN"]
```

Also: `Secret.from_dotenv()`, `Secret.from_dict({...})`.

### Environment Variables

Bake into the image with `.env()`:

```python
image = modal.Image.debian_slim().env({
    "HF_HOME": "/models",
    "CUDA_VISIBLE_DEVICES": "0",
})
```

These are set at build time and available in every container.

### Parallel Execution

```python
@app.function()
def process(item_id: int):
    return heavy_computation(item_id)

@app.local_entrypoint()
def main():
    results = list(process.map(range(1000)))  # auto-parallelized
```

### Autoscaling

```python
@app.function(
    max_containers=100,
    min_containers=2,       # keep warm
    buffer_containers=5,    # idle buffer for bursts
    scaledown_window=60,    # seconds before scale-down
)
def inference():
    pass
```

### Web Endpoints

```python
@app.function()
@modal.web_endpoint(method="POST")
def predict(data: dict):
    return {"result": model(data["input"])}
```

Deploy: `modal deploy script.py` → HTTPS URL.

### Scheduled Jobs

```python
@app.function(schedule=modal.Cron("0 2 * * *"))  # daily 2 AM
def nightly_job():
    pass
```

## Complete Example: Research Experiment on GPU

```python
"""Run an experiment on Modal with persistent output."""
import modal

app = modal.App("my-experiment")

image = (
    modal.Image.debian_slim(python_version="3.12")
    .uv_sync()
    .add_local_python_source("my_experiment")  # package with __init__.py
)

vol = modal.Volume.from_name("experiment-data", create_if_missing=True)

@app.function(image=image, gpu="A10G", volumes={"/data": vol}, timeout=600)
def run_experiment():
    from my_experiment import train  # local code, importable via add_local_python_source
    results = train(output_dir="/data/results")
    vol.commit()
    return results

@app.local_entrypoint()
def main():
    results = run_experiment.remote()
    print(results)
    print("Download: modal volume get experiment-data results/ results/")
```

## Decision Guide

| Scenario | Approach |
|---|---|
| Existing project with pyproject.toml | `uv_sync()` |
| Standalone script | `uv_pip_install("pkg==1.2.3")` |
| Multi-file project (package with `__init__.py`) | `add_local_python_source("pkg_name")` |
| Multi-file project (loose scripts) | Multiple `add_local_file()` calls |
| Static model weights | `run_function()` at build time (image layer) |
| Dynamic data / outputs | Volume |
| Credentials / tokens | `modal.Secret` |
| Config values | `image.env({...})` or function args |

## References

Local references in `references/`:
- `functions.md` — Decorators, `.remote()`, `.map()`, classes, async, retries
- `gpu.md` — GPU types, multi-GPU, fallback chains, PyTorch setup
- `images.md` — Base images, packages, local code mounting, caching
- `secrets.md` — Environment variables, auth patterns
- `scheduled-jobs.md` — Cron, periodic tasks

For volumes, scaling, and the latest API changes, use context7 (`mcp__context7__query-docs` with library ID `/llmstxt/modal_llms-full_txt`) or https://modal.com/docs/guide.
