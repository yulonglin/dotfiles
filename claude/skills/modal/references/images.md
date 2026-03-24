# Modal Images Reference

Modal Images are the container environments that Modal functions run in. Images are built using a builder-pattern API with method chaining. Each method call adds a layer to the image.

## Base Images

### `debian_slim`

The most common starting point. A minimal Debian-based image with Python pre-installed.

```python
import modal

image = modal.Image.debian_slim()

# Specify Python version
image = modal.Image.debian_slim(python_version="3.13")
image = modal.Image.debian_slim(python_version="3.12")
```

### `micromamba`

A Conda-compatible base image using micromamba as the package manager. Useful for packages that require non-Python dependencies managed through Conda.

```python
image = modal.Image.micromamba()
```

### `from_registry`

Pull an image from any public or private container registry (Docker Hub, GHCR, ECR, etc.).

```python
image = modal.Image.from_registry("nvidia/cuda:12.2.0-devel-ubuntu22.04")
```

### `from_dockerfile`

Build an image from a local Dockerfile.

```python
image = modal.Image.from_dockerfile("./Dockerfile")
```

## Installing Python Packages

### `uv_pip_install` (recommended)

Uses `uv` for fast package installation. Preferred over `pip_install`.

```python
# Single or multiple packages
image = modal.Image.debian_slim().uv_pip_install("pandas==2.2.0", "numpy")

# From a list
image = modal.Image.debian_slim().uv_pip_install(
    [
        "colpali-engine==0.3.5",
        "transformers>=4.45.0",
        "torch>=2.0.0",
        "huggingface-hub==0.36.0",
    ]
)
```

### `pip_install`

Fallback if `uv_pip_install` encounters issues.

```python
image = modal.Image.debian_slim(python_version="3.13").pip_install("pandas==2.2.0", "numpy")
```

### `uv_sync`

Syncs dependencies from a `uv.lock` / `pyproject.toml` lockfile using uv.

```python
image = modal.Image.debian_slim().uv_sync()
```

### `pip_install_from_pyproject`

Installs Python packages from a `pyproject.toml` file.

```python
image = modal.Image.debian_slim().pip_install_from_pyproject("pyproject.toml")
```

### GPU during package installation

Some packages (e.g., `bitsandbytes`) need GPU access at install time. Pass the `gpu` parameter:

```python
image = modal.Image.debian_slim().pip_install("bitsandbytes", gpu="H100")
```

This also works with `uv_pip_install` and other install methods.

## Adding Local Code

Modal provides three methods for including local files/code in images. By default, files are mounted at container startup (not baked into the image layer) for faster redeployment. Use `copy=True` to bake them into the image layer instead.

### `add_local_python_source`

Adds local Python source code (`.py` files by default). This is the replacement for the deprecated `Mount.from_local_python_packages`.

```python
import modal
import helpers

# Add a local package
image = modal.Image.debian_slim().add_local_python_source("helpers")

# Add from a source directory
image = modal.Image.debian_slim().add_local_python_source("./src")
```

### `add_local_dir`

Adds an entire local directory to the container.

```python
# Default: mounted at runtime (faster redeployment)
image = modal.Image.debian_slim().add_local_dir("data", "/root/data")

# Force copy into image layer (baked in)
image = modal.Image.debian_slim().add_local_dir("data", "/root/data", copy=True)

# With a remote path
image = modal.Image.debian_slim().add_local_dir(
    "~/.aws", remote_path="/root/.aws"
)
```

The `ignore` parameter supports file exclusion patterns.

### `add_local_file`

Adds a single local file to the container.

```python
image = modal.Image.debian_slim().add_local_file("config.yaml", "/root/config.yaml")

# Force copy into image layer
image = modal.Image.debian_slim().add_local_file("config.yaml", "/root/config.yaml", copy=True)
```

### `copy=True` vs `copy=False` (default)

| Behavior | `copy=False` (default) | `copy=True` |
|----------|----------------------|-------------|
| When files transfer | At container startup (runtime mount) | During image build (baked into layer) |
| Redeployment speed | Faster (image layer unchanged) | Slower (rebuilds layer on file changes) |
| Use case | Code that changes frequently | Files needed at build time, or for hermetic reproducibility |

## System Packages

### `apt_install`

Installs system packages via `apt-get`.

```python
image = modal.Image.debian_slim().apt_install("git")

# Multiple packages
image = modal.Image.debian_slim().apt_install("git", "ffmpeg", "libsndfile1")
```

## Environment Variables

### `env`

Sets environment variables in the container.

```python
image = (
    modal.Image.debian_slim()
    .env({"HF_XET_HIGH_PERFORMANCE": "1", "HF_HUB_CACHE": "/hf-cache"})
)

# Single variable
image = modal.Image.debian_slim().env({"HALT_AND_CATCH_FIRE": "0"})
```

## Running Code at Build Time

### `run_commands`

Executes shell commands during the image build.

```python
image = (
    modal.Image.debian_slim()
    .apt_install("git")
    .uv_pip_install("torch<3")
    .run_commands("git clone https://github.com/modal-labs/agi && echo 'ready to go!'")
)
```

### `run_function`

Executes a Python function during the image build. Useful for downloading model weights, preparing data, or any programmatic build step.

```python
import os

def download_models() -> None:
    import requests
    model_url = "https://example.com/model.bin"
    model_path = "/models/model.bin"
    os.makedirs(os.path.dirname(model_path), exist_ok=True)
    if not os.path.exists(model_path):
        response = requests.get(model_url, stream=True)
        with open(model_path, "wb") as f:
            for chunk in response.iter_content(chunk_size=8192):
                f.write(chunk)

image = modal.Image.debian_slim().run_function(download_models)
```

Note: Imports used only inside the function should be placed inside the function body, not at module top-level, since the build environment may not have those packages until earlier layers install them.

## Image Caching

Modal caches images based on their definitions. Caching is **per-layer** -- if a layer's definition hasn't changed since the last run or deployment, the cached version is used.

### Layer ordering for cache efficiency

Place layers that change **infrequently** first and layers that change **frequently** last. This maximizes cache reuse:

```python
image = (
    modal.Image.debian_slim()           # Rarely changes
    .apt_install("git", "ffmpeg")       # Rarely changes
    .uv_pip_install("torch", "numpy")   # Changes occasionally
    .add_local_python_source("src")     # Changes frequently -- put last
)
```

### `force_build`

Forces a rebuild of a specific layer and all subsequent layers, even if the definition hasn't changed. Available on all image-building methods.

```python
image = (
    modal.Image.debian_slim()
    .apt_install("git")
    .pip_install("slack-sdk", force_build=True)  # This and later layers rebuild
    .run_commands("echo hi")                     # Also rebuilds (downstream)
)
```

Remove `force_build=True` after the rebuild to avoid unnecessary rebuilds.

### Environment variables for global cache control

- `MODAL_FORCE_BUILD=1` -- Forces all images attached to your App to rebuild.
- `MODAL_IGNORE_CACHE=1` -- Rebuilds the Image from the top without invalidating the cache for other images. Useful for debugging specific image issues.

## GPU Support at Build Time

Some packages require GPU access during installation or compilation. Pass the `gpu` parameter to the relevant image method:

```python
# GPU during pip install
image = modal.Image.debian_slim().pip_install("bitsandbytes", gpu="H100")

# GPU during run_commands or run_function
image = modal.Image.debian_slim().run_commands("nvidia-smi", gpu="A100")
```

Valid GPU strings include `"T4"`, `"A10G"`, `"A100"`, `"H100"`, etc.

## Full Example

```python
import modal

CACHE_DIR = "/hf-cache"

def download_model() -> None:
    from huggingface_hub import snapshot_download
    snapshot_download("meta-llama/Llama-3-8B", cache_dir=CACHE_DIR)

image = (
    modal.Image.debian_slim(python_version="3.12")
    .apt_install("git")
    .uv_pip_install(
        [
            "transformers>=4.45.0",
            "torch>=2.0.0",
            "huggingface-hub==0.36.0",
        ]
    )
    .env({"HF_HUB_CACHE": CACHE_DIR, "HF_XET_HIGH_PERFORMANCE": "1"})
    .run_function(download_model)
    .add_local_python_source("src")
)

app = modal.App("my-app", image=image)
```
