# Local services and upgrades

Apply to local services, proxies, hooks, and update automation. Verify each item against tests, service state, or retained diagnostics before reporting a change complete.

- [ ] Verify the dependency's real readiness before use; an installed file, configured URL, or running PID is not proof.
- [ ] Before restarting or repairing, save bounded private diagnostics: timestamp, versions, service state, exit status, and safe log evidence. Exclude credentials and request contents. Record the recovery result too.
- [ ] Make startup safe for unloaded, stopped, and already-running services. Respect explicit disables, preserve healthy processes, bound retries, and show actionable failures.
- [ ] Test lifecycle failures with disposable real services: fresh registration, restart, upgrade, concurrent startup, and intentional disable. State which cases were simulated or not tested; claim reboot persistence only after a real reboot check.
- [ ] Run a bounded smoke check after upgrades. Cache success only for the versions actually tested; surface failures and preserve evidence. Distinguish infrastructure checks from model inference tests.
- [ ] Fix the component that owns the failure when practical. Document local workarounds and when to remove them; do not patch disposable plugin caches as a durable fix.
