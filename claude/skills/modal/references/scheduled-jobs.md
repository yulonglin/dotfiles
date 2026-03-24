# Scheduled Jobs and Cron

## Basic Scheduling

Schedule functions to run automatically at regular intervals or specific times.

### Simple Daily Schedule

```python
import modal

app = modal.App()

@app.function(schedule=modal.Period(days=1))
def daily_task():
    print("Running daily task")
```

Deploy to activate:
```bash
modal deploy script.py
```

## Schedule Types

### Period Schedules

Run at fixed intervals from deployment time:

```python
@app.function(schedule=modal.Period(hours=5))
def every_5_hours():
    ...

@app.function(schedule=modal.Period(minutes=30))
def every_30_minutes():
    ...
```

**Note**: Redeploying resets the period timer.

### Cron Schedules

Run at specific times using cron syntax:

```python
# Every Monday at 8 AM UTC
@app.function(schedule=modal.Cron("0 8 * * 1"))
def weekly_report():
    ...

# Daily at 6 AM New York time
@app.function(schedule=modal.Cron("0 6 * * *", timezone="America/New_York"))
def morning_report():
    ...
```

**Cron syntax**: `minute hour day month day_of_week`

## Deployment

```bash
modal deploy script.py
```

Scheduled functions persist until explicitly stopped.

## Common Patterns

### Model Retraining

```python
volume = modal.Volume.from_name("models")

@app.function(
    schedule=modal.Cron("0 0 * * 0"),  # Weekly on Sunday midnight
    gpu="A100",
    timeout=7200,
    volumes={"/models": volume}
)
def retrain_model():
    data = load_training_data()
    model = train(data)
    save_model(model, "/models/latest.pt")
    volume.commit()
```

## Best Practices

1. **Set timeouts**: Always specify timeout for scheduled functions
2. **Use appropriate schedules**: Period for relative timing, Cron for absolute
3. **Monitor failures**: Check dashboard regularly for failed runs
4. **Idempotent operations**: Design tasks to handle reruns safely
5. **Timezone awareness**: Specify timezone for cron schedules
