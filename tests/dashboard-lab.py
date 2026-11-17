"""Measure concurrent officer session polls against the disposable portal."""

from concurrent.futures import ProcessPoolExecutor
from multiprocessing import get_context
from pathlib import Path
import runpy
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
sys.path[:0] = [str(ROOT), str(ROOT / "dashboard")]
active_logins = runpy.run_path(str(ROOT / "dashboard" / "host.py"))["active_logins"]
settings = active_logins.__globals__
run = settings["run"]
lab = Path(sys.argv[1])
settings["SESSION_CACHE"] = lab / "dashboard-cache"
calls = lab / "dashboard-docker-calls"
LOGIN = "review-ab123456-team-1-cd123456"
STALE = "review-ab123456-team-2-cd123457"


def lab_run(*args, **options):
    with calls.open("a") as trace:
        trace.write(args[1] + "\n")
    return run(*(arg.replace("workshop-", "peter-portal-test-", 1)
                 if arg in {"workshop-web-1", "workshop-guacd-1", "workshop-db-1"} else arg
                 for arg in args), **options)


def officer_poll(_):
    start = time.monotonic()
    return settings["cached_active_logins"]("test-event"), time.monotonic() - start


if __name__ == "__main__":
    history = ("INSERT INTO guacamole_connection_history (username, connection_id, connection_name, start_date) "
               f"SELECT 'fixture', connection_id, connection_name, now() FROM guacamole_connection WHERE connection_name = '{STALE}';")
    run("docker", "exec", "peter-portal-test-db-1", "psql", "-XqAt", "-U", "postgres",
        "--dbname", "guacamole", "-v", "ON_ERROR_STOP=1", "-c", history)
    settings["run"] = lab_run
    settings["SESSION_CACHE"].unlink(missing_ok=True)
    calls.unlink(missing_ok=True)
    with ProcessPoolExecutor(max_workers=6, mp_context=get_context("fork")) as officers:
        polls = list(officers.map(officer_poll, range(6)))
    assert all(result == {LOGIN} for result, _ in polls), polls
    assert calls.read_text().splitlines() == ["inspect", "exec"]
    print(f"Six concurrent officer polls shared one inspect and one exec. "
          f"Longest poll: {max(elapsed for _, elapsed in polls):.3f} s.")
