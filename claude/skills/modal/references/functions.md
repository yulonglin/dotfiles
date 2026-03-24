# Modal Functions Reference

## Basic Function Definition

Decorate a Python function with `@app.function()` to run it on Modal:

```python
import modal

app = modal.App("my-app")

@app.function()
def hello(name: str) -> str:
    return f"Hello, {name}!"
```

## Calling Functions

### `.remote()` -- Run on Modal

```python
@app.local_entrypoint()
def main():
    result = hello.remote("world")
    print(result)  # "Hello, world!"
```

### `.local()` -- Run locally

```python
result = hello.local("world")  # Runs in the current process
```

## Local Entrypoint

`@app.local_entrypoint()` defines the CLI entry point that runs locally and dispatches work to Modal. Function parameters become CLI arguments automatically:

```python
@app.local_entrypoint()
def main(frame_count: int = 250, frame_skip: int = 1):
    # frame_count and frame_skip become --frame-count and --frame-skip CLI args
    result = my_function.remote(frame_count)
    print(result)
```

Run with: `modal run my_script.py --frame-count 100`

Optional parameters use `typing.Optional`:

```python
from typing import Optional

@app.local_entrypoint()
def main(document_filename: Optional[str] = None):
    if document_filename is None:
        # use default
        ...
    result = process.remote(document_filename)
```

## Parallel Execution

### `.map()` -- Parallel over single argument

```python
@app.function()
def square(x: int) -> int:
    return x * x

@app.local_entrypoint()
def main():
    results = list(square.map([1, 2, 3, 4, 5]))
    print(results)  # [1, 4, 9, 16, 25]
```

`.map()` returns an iterator. Use `order_outputs=False` if you do not need results in input order (can be faster):

```python
results = list(square.map(range(100), order_outputs=False))
```

### `.starmap()` -- Parallel over multiple arguments

Pass a list of tuples, each tuple is unpacked as function arguments:

```python
@app.function()
def add(a: int, b: int) -> int:
    return a + b

@app.local_entrypoint()
def main():
    args = [(1, 2), (3, 4), (5, 6)]
    results = list(add.starmap(args))
    print(results)  # [3, 7, 11]
```

## Classes

Use `@app.cls()` for stateful functions with lifecycle hooks:

```python
@app.cls(gpu="A10G")
class Model:
    @modal.enter()
    def load_model(self):
        # Runs once when container starts -- load weights here
        self.model = load_my_model()

    @modal.method()
    def predict(self, text: str) -> str:
        return self.model(text)

    @modal.exit()
    def cleanup(self):
        # Runs when container shuts down
        ...
```

Call class methods:

```python
@app.local_entrypoint()
def main():
    model = Model()
    result = model.predict.remote("Hello")
    print(result)
```

### Parametrized Classes

Use `modal.parameter()` to create constructor arguments that define separate container pools:

```python
@app.cls()
class MyClass:
    foo: str = modal.parameter()
    bar: int = modal.parameter(default=10)

    @modal.method()
    def baz(self, qux: str = "default") -> str:
        return f"Pool ({self.foo}, {self.bar}), input qux={qux}"

@app.local_entrypoint()
def main():
    m1 = MyClass(foo="hedgehog", bar=7)
    m1.baz.remote()
    m2 = MyClass(foo="fox")  # bar defaults to 10
    m2.baz.remote(qux="override")
```

Each unique combination of parameters runs in its own container pool. Use `@modal.enter()` to load resources based on parameters:

```python
@app.cls()
class Model:
    name: str = modal.parameter()
    size: int = modal.parameter(default=100)

    @modal.enter()
    def load_model(self):
        self.model = load_model_util(self.name, self.size)

    @modal.method()
    def generate(self, prompt: str) -> str:
        return self.model.generate(prompt)
```

## Async Functions

Functions can be `async`. Use `.aio` variants for async calling:

```python
@app.function()
async def fetch_data(url: str) -> str:
    import httpx
    async with httpx.AsyncClient() as client:
        resp = await client.get(url)
        return resp.text

@app.local_entrypoint()
async def main():
    # .starmap.aio for async iteration
    inputs = [(url,) for url in urls]
    async for result in fetch_data.starmap.aio(inputs):
        print(result)
```

## Spawning Background Jobs

Use `.spawn()` to start a function asynchronously and retrieve results later. Results are available for up to 7 days:

```python
@app.function()
def process_job(data):
    return {"result": data}

def submit_job(data):
    process_job_fn = modal.Function.from_name("my-app", "process_job")
    call = process_job_fn.spawn(data)
    return call.object_id  # Save this ID to retrieve results later

def get_job_result(call_id):
    function_call = modal.FunctionCall.from_id(call_id)
    try:
        result = function_call.get(timeout=5)
    except modal.exception.OutputExpiredError:
        result = "expired"  # Results expire after 7 days
    except TimeoutError:
        result = "pending"  # Still running
    return result
```

Async variant:

```python
call = await process_job_fn.spawn.aio(data)
result = await function_call.get.aio(timeout=0)
```

## Function Configuration

### Timeout

Set maximum execution time in seconds:

```python
@app.function(timeout=600)  # 10 minutes
def long_running():
    ...
```

Catch timeout errors:

```python
import modal.exception

try:
    result = long_running.remote()
except modal.exception.FunctionTimeoutError:
    print("Function timed out")
```

### Startup Timeout

Separate timeout for container startup (image pull + enter hooks):

```python
@app.function(startup_timeout=300.0)  # 5 minutes for startup
def needs_slow_init():
    ...
```

### Retries

Configure automatic retries with `modal.Retries`:

```python
@app.function(
    retries=modal.Retries(
        max_retries=3,
        initial_delay=1.0,
        backoff_coefficient=2.0,
    ),
    timeout=3600,
)
def train():
    ...
```

### max_inputs

Limit how many inputs a container handles before being recycled:

```python
@app.function(max_inputs=1)  # Fresh container for every input
def stateless_work(data):
    ...
```

### Combined Configuration Example

```python
@app.function(
    gpu="A100-80GB",
    image=my_image,
    secrets=[modal.Secret.from_name("my-secret")],
    volumes={"/data": modal.Volume.from_name("my-volume")},
    timeout=3600,
    retries=modal.Retries(max_retries=2),
    max_inputs=1,
)
def full_example():
    ...
```

## Looking Up Deployed Functions

Reference a deployed function without importing its code:

```python
process_job = modal.Function.from_name("my-app", "process_job")
result = process_job.remote(data)
```
