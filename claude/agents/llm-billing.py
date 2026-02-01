#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# dependencies = ["httpx", "python-dotenv", "rich"]
# ///
"""Query LLM provider APIs for credit balances and usage statistics.

Supports:
- OpenRouter: balance + credits remaining
- OpenAI: daily/hourly cost breakdown (requires org-level key, not project-scoped)
- Anthropic: daily/hourly cost breakdown (requires admin API key: sk-ant-admin-...)
- HuggingFace: account info + plan (no billing API available)
"""

import json
import os
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

import httpx
from dotenv import load_dotenv
from rich.console import Console
from rich.panel import Panel
from rich.table import Table

# agents/ -> claude/ -> dotfiles/.env
load_dotenv(Path(__file__).resolve().parent.parent.parent / ".env")

console = Console()


# --- Helpers ---


def _get(url: str, headers: dict, params: dict | None = None) -> dict | None:
    """GET request with error handling. Returns JSON or None."""
    try:
        r = httpx.get(url, headers=headers, params=params or {}, timeout=15)
        r.raise_for_status()
        return r.json()
    except httpx.HTTPStatusError as e:
        console.print(f"  [dim red]{e.response.status_code}: {url}[/]")
        return None
    except (httpx.HTTPError, json.JSONDecodeError) as e:
        console.print(f"  [dim red]Error: {e}[/]")
        return None


def _utc_now() -> datetime:
    return datetime.now(timezone.utc)


def _day_key(dt: datetime) -> str:
    return dt.strftime("%Y-%m-%d")


def _hour_key(dt: datetime) -> str:
    return dt.strftime("%Y-%m-%d %H:00")


def _spend_style(amount: float) -> str:
    if amount < 0.01:
        return "dim"
    if amount < 1.0:
        return "green"
    if amount < 5.0:
        return "yellow"
    return "red"


def _fmt_cost(v: float) -> str:
    style = _spend_style(v)
    return f"[{style}]${v:.4f}[/]" if v < 1 else f"[{style}]${v:.2f}[/]"


# --- Providers ---


def query_openrouter(key: str) -> dict | None:
    """Balance only — no usage history API exists."""
    data = _get("https://openrouter.ai/api/v1/auth/key", {"Authorization": f"Bearer {key}"})
    if not data or "data" not in data:
        return None
    d = data["data"]
    limit = d.get("limit")
    usage = d.get("usage", 0)
    return {
        "provider": "OpenRouter",
        "limit": limit,
        "used": usage,
        "remaining": (limit - usage) if limit is not None else None,
        "status": "ok",
    }


def query_openai(key: str) -> tuple[dict | None, dict[str, float], dict[str, float]]:
    """Costs endpoint — requires org-level key (not project-scoped sk-proj-...)."""
    now = _utc_now()
    headers = {"Authorization": f"Bearer {key}"}

    def _parse_buckets(data: dict | None, key_fn) -> dict[str, float]:
        result: dict[str, float] = {}
        if not data or "results" not in data:
            return result
        for bucket in data["results"]:
            ts = bucket.get("start_time")
            if not isinstance(ts, (int, float)):
                continue
            k = key_fn(datetime.fromtimestamp(ts, tz=timezone.utc))
            total = 0.0
            for r in bucket.get("results", []):
                amt = r.get("amount", {})
                total += float(amt.get("value", 0)) if isinstance(amt, dict) else float(amt or 0)
            result[k] = result.get(k, 0) + total
        return result

    start_7d = int((now - timedelta(days=7)).timestamp())
    end = int(now.timestamp())
    daily = _parse_buckets(
        _get("https://api.openai.com/v1/organization/costs", headers,
             {"start_time": str(start_7d), "end_time": str(end), "bucket_width": "1d"}),
        _day_key,
    )

    start_5h = int((now - timedelta(hours=5)).timestamp())
    hourly = _parse_buckets(
        _get("https://api.openai.com/v1/organization/costs", headers,
             {"start_time": str(start_5h), "end_time": str(end), "bucket_width": "1h"}),
        _hour_key,
    )

    bal = None
    if daily or hourly:
        total_7d = sum(daily.values())
        bal = {"provider": "OpenAI", "limit": None, "used": total_7d, "remaining": None, "status": "ok"}

    return bal, daily, hourly


def query_anthropic(key: str) -> tuple[dict | None, dict[str, float], dict[str, float]]:
    """Cost + usage reports — requires admin API key (sk-ant-admin-...)."""
    now = _utc_now()
    headers = {"x-api-key": key, "anthropic-version": "2023-06-01"}
    start_7d = (now - timedelta(days=7)).strftime("%Y-%m-%dT00:00:00Z")
    end_str = now.strftime("%Y-%m-%dT%H:%M:%SZ")

    # Daily
    daily: dict[str, float] = {}
    data = _get(
        "https://api.anthropic.com/v1/organizations/cost_report", headers,
        {"starting_at": start_7d, "ending_at": end_str, "bucket_width": "1d"},
    )
    if data:
        for bucket in data.get("data", data.get("results", [])):
            ts = bucket.get("started_at") or bucket.get("start_time", "")
            dk = ts[:10] if isinstance(ts, str) else ""
            cost = float(bucket.get("cost_usd", 0) or bucket.get("cost", 0))
            if dk:
                daily[dk] = daily.get(dk, 0) + cost

    # Hourly (past 5h)
    hourly: dict[str, float] = {}
    start_5h = (now - timedelta(hours=5)).strftime("%Y-%m-%dT%H:00:00Z")
    data_h = _get(
        "https://api.anthropic.com/v1/organizations/usage_report/messages", headers,
        {"starting_at": start_5h, "ending_at": end_str, "bucket_width": "1h"},
    )
    if data_h:
        for bucket in data_h.get("data", data_h.get("results", [])):
            ts = bucket.get("started_at") or bucket.get("start_time", "")
            if not (isinstance(ts, str) and len(ts) >= 13):
                continue
            hk = ts[:13].replace("T", " ") + ":00"
            cost = float(bucket.get("cost_usd", 0) or bucket.get("cost", 0))
            if cost == 0:
                cost = sum(
                    float(bucket.get(f, 0) or 0)
                    for f in ("input_cached_write_cost_usd", "input_cost_usd", "output_cost_usd")
                )
            hourly[hk] = hourly.get(hk, 0) + cost

    bal = None
    if daily or hourly:
        total_7d = sum(daily.values())
        bal = {"provider": "Anthropic", "limit": None, "used": total_7d, "remaining": None, "status": "ok"}

    return bal, daily, hourly


def query_huggingface(key: str) -> dict | None:
    """Account info only — no billing API exists."""
    data = _get("https://huggingface.co/api/whoami-v2", {"Authorization": f"Bearer {key}"})
    if not data:
        return None
    name = data.get("name", "?")
    plan = data.get("auth", {}).get("accessToken", {}).get("role", "?")
    return {
        "provider": "HuggingFace",
        "limit": None,
        "used": None,
        "remaining": None,
        "status": f"{name} ({plan})",
    }


# --- Display ---


def show_balances(balances: list[dict]) -> None:
    table = Table(show_header=True, header_style="bold cyan", padding=(0, 1))
    table.add_column("Provider", style="bold")
    table.add_column("Limit", justify="right")
    table.add_column("Used (7d)", justify="right")
    table.add_column("Remaining", justify="right")
    table.add_column("Status", style="dim")

    for b in balances:
        limit = f"${b['limit']:.2f}" if b.get("limit") is not None else "—"
        used = f"${b['used']:.2f}" if b.get("used") is not None else "—"
        rem = b.get("remaining")
        if rem is not None:
            color = "green" if rem > 10 else "yellow" if rem > 2 else "red"
            rem_str = f"[{color}]${rem:.2f}[/]"
        else:
            rem_str = "—"
        table.add_row(b["provider"], limit, used, rem_str, b.get("status", ""))

    console.print(table)
    console.print()


def _show_spend_table(
    title: str,
    time_label: str,
    time_keys: list[str],
    data: dict[str, dict[str, float]],
) -> None:
    """Render a spend breakdown table (used for both daily and hourly views)."""
    providers = list(data.keys())
    if not providers:
        return

    table = Table(title=title, show_header=True, header_style="bold cyan", padding=(0, 1))
    table.add_column(time_label, style="bold")
    for p in providers:
        table.add_column(p, justify="right")
    table.add_column("Total", justify="right", style="bold")

    for key in time_keys:
        row = [key]
        total = 0.0
        for p in providers:
            v = data[p].get(key, 0)
            total += v
            row.append(_fmt_cost(v))
        row.append(_fmt_cost(total))
        table.add_row(*row)

    console.print(table)
    console.print()


def show_daily(all_daily: dict[str, dict[str, float]]) -> None:
    now = _utc_now()
    days = [_day_key(now - timedelta(days=i)) for i in range(6, -1, -1)]
    _show_spend_table("Daily Spend — Past 7 Days (USD)", "Date", days, all_daily)


def show_hourly(all_hourly: dict[str, dict[str, float]]) -> None:
    now = _utc_now()
    hours = [_hour_key(now - timedelta(hours=i)) for i in range(4, -1, -1)]
    _show_spend_table("Hourly Spend — Past 5 Hours (USD)", "Hour (UTC)", hours, all_hourly)


# --- Main ---


def main() -> None:
    balances: list[dict] = []
    all_daily: dict[str, dict[str, float]] = {}
    all_hourly: dict[str, dict[str, float]] = {}
    missing: list[str] = []

    console.print(Panel(
        "[bold]LLM Provider Billing Report[/]",
        subtitle=f"[dim]{_utc_now():%Y-%m-%d %H:%M UTC}[/]",
    ))
    console.print()

    # OpenRouter
    or_key = os.getenv("OPENROUTER_API_KEY")
    if or_key:
        console.print("[dim]Querying OpenRouter...[/]")
        bal = query_openrouter(or_key)
        if bal:
            balances.append(bal)
    else:
        missing.append("OPENROUTER_API_KEY")

    # Providers with usage history (daily + hourly breakdowns)
    usage_providers = [
        ("OPENAI_API_KEY", "OpenAI", query_openai,
         "No data — needs org-level key (not project-scoped sk-proj-...)"),
        ("ANTHROPIC_ADMIN_API_KEY (sk-ant-admin-...)", "Anthropic", query_anthropic, None),
    ]
    for env_var, name, query_fn, fallback_msg in usage_providers:
        env_key = env_var.split(" ")[0]  # strip parenthetical hint
        key = os.getenv(env_key)
        if not key:
            missing.append(env_var)
            continue
        console.print(f"[dim]Querying {name}...[/]")
        bal, d, h = query_fn(key)
        if bal:
            balances.append(bal)
        if d:
            all_daily[name] = d
        if h:
            all_hourly[name] = h
        if not bal and not d and fallback_msg:
            console.print(f"  [dim yellow]{fallback_msg}[/]")

    # HuggingFace
    hf_key = os.getenv("HF_TOKEN")
    if hf_key:
        console.print("[dim]Querying HuggingFace...[/]")
        bal = query_huggingface(hf_key)
        if bal:
            balances.append(bal)
    else:
        missing.append("HF_TOKEN")

    console.print()

    if balances:
        show_balances(balances)
    if all_daily:
        show_daily(all_daily)
    if all_hourly:
        show_hourly(all_hourly)

    if missing:
        console.print("[dim]Missing keys:[/]")
        for m in missing:
            console.print(f"  [dim yellow]• {m}[/]")
        console.print()

    if not balances:
        console.print("[red]No billing data available. Check API keys in .env[/]")
        sys.exit(1)


if __name__ == "__main__":
    main()
