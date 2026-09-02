---
name: modal
description: Run Python code in the cloud with serverless containers, GPUs, and autoscaling. Use when deploying ML models, running batch processing jobs, scheduling compute-intensive tasks, or serving APIs that require GPU acceleration or dynamic scaling.
---

# Modal

Modal is a serverless platform for running Python code in the cloud: GPUs, autoscaling containers, pay per second of compute. Sign up at https://modal.com ($30/month free credits).

For current API details — decorator options, method signatures, new features — use context7 (`mcp__context7__query-docs` with library ID `/llmstxt/modal_llms-full_txt`) rather than trusting anything written here. This page carries only the things context7 will not tell you: the failure modes, and how this setup is wired.

## Modal Is A Dev Dependency, Not A Container Dependency

```bash
uv add --dev modal     # dev dep — only needed locally, not in containers
modal token new        # opens browser for auth → saves to ~/.modal.toml
```

## Quick Start: One File Is A Whole GPU Job

```python
"""Run an experiment on Modal with persistent output."""
import modal

app = modal.App("my-experiment")

image = (
    modal.Image.debian_slim(python_version="3.14")
    .uv_sync()                                    # installs from pyproject.toml + uv.lock
    .add_local_python_source("my_experiment")     # MUST come after all build steps
)

vol = modal.Volume.from_name("experiment-data", create_if_missing=True)

@app.function(image=image, gpu="A10G", volumes={"/data": vol}, timeout=600)
def run_experiment():
    from my_experiment import train   # heavy imports inside the body
    results = train(output_dir="/data/results")
    vol.commit()
    return results

@app.local_entrypoint()
def main(lr: float = 0.001):
    print(run_experiment.remote())
```

Run it with `modal run train.py --lr 0.01` — CLI flags are auto-parsed from the `local_entrypoint` type hints. Pull outputs back off the volume with `modal volume get experiment-data results/ results/`.

## Local Code Mounting Has Two Hard Failure Modes

**Ordering.** `add_local_file` / `add_local_dir` / `add_local_python_source` MUST come AFTER every build step (`uv_pip_install`, `run_function`, `run_commands`). Modal mounts them at container startup, not build time, so a build step placed after one fails with `InvalidError('An image tried to run a build step after using image.add_local_*')`. Set `copy=True` to bake the files into the image layer when a later build step genuinely depends on them; the default `copy=False` is what makes re-deploys fast, because changing code doesn't rebuild the image.

**Loose scripts.** `add_local_python_source(".")` requires a real Python package (a directory with `__init__.py`) and fails with `ModuleNotMountable("no package specified for '.'")` otherwise. Either name the package — `add_local_python_source("my_package")` — or fall back to multiple `add_local_file()` calls for a directory of loose scripts.

## Heavy Imports Belong Inside The Function Body

Modal serializes the function definition **locally** and runs it remotely, so a top-level `import torch` fails on a laptop that has no torch — even though the container does. Import inside the function body, or defer module-level imports with `with image.imports():`.

## Pin Versions, Because Every Change Invalidates The Image Cache Layer

`uv_sync()` is the right default for a project with a `pyproject.toml` + `uv.lock` — deps never drift from local. For standalone scripts use `uv_pip_install("torch==2.5.1", ...)` with tight pins. `.pip_install_from_pyproject("pyproject.toml")` exists but uses pip and is slower than uv.

`debian_slim()` is enough for GPU work: PyTorch bundles its own CUDA, so no nvidia base image is needed.

GPU cost shape: `A10G` (24 GB) is the cheap default, `L40S` (48 GB) the best value for inference, `A100`/`H100` for training. A list — `gpu=["H100", "A100-40GB:2"]` — is a fallback chain for when the first choice has no capacity.

## Static Weights Go In The Image, Changing Data Goes In A Volume

Volumes are network-attached, so a volume read happens over the network on **every cold start**; image layers are cached on local SSD. Bake static model weights into the image with `run_function()` at build time, and reserve volumes for data that actually changes (datasets you update, experiment outputs).

```python
def download_model():
    from huggingface_hub import snapshot_download
    # unsloth/ mirrors avoid HF gated-model access issues
    snapshot_download("unsloth/Llama-3.2-1B-Instruct", cache_dir="/models")

image = (
    modal.Image.debian_slim(python_version="3.14")
    .uv_sync()
    .uv_pip_install("huggingface_hub[hf_transfer]")   # fast Rust-based downloads
    .env({"HF_HOME": "/models", "HF_HUB_ENABLE_HF_TRANSFER": "1"})
    .run_function(download_model, secrets=[modal.Secret.from_name("huggingface-secret")])
)
```

The first build downloads the weights; later builds reuse the cached layer. On the volume side, `vol.commit()` persists changes (it also auto-commits on exit).

## Containers Never Inherit Your Local Shell Environment

Every credential a Modal function needs must arrive as a `modal.Secret`. Which kind depends on the workflow:

- Local-driver jobs where the caller may rotate keys between runs — `modal.Secret.from_local_environ(["ANTHROPIC_API_KEY"])`, which re-reads the current local env on each `modal run`.
- Deployed, scheduled, shared or reproducible jobs — a persistent named Secret: `modal secret create --force -e main huggingface-secret HF_TOKEN="hf_xxx"`, then `modal.Secret.from_name("huggingface-secret", required_keys=["HF_TOKEN"])`.

Name persistent Secrets after the service or provider and put the SDK's own environment variable name inside them. Always pass `required_keys=[...]` — it turns a missing or misspelled key into a clear failure at Secret-resolution time instead of a `KeyError` deep inside a GPU container you are paying for. `Secret.from_dotenv()` and `Secret.from_dict({...})` also exist.

## References

Deeper local notes in `references/`:
- `functions.md` — decorators, `.remote()`, `.map()`, classes, async, retries
- `gpu.md` — GPU types, multi-GPU, fallback chains, PyTorch setup
- `images.md` — base images, packages, local code mounting, caching
- `secrets.md` — environment variables, auth patterns
- `scheduled-jobs.md` — cron, periodic tasks

Official guide: https://modal.com/docs/guide
