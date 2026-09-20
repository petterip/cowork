#!/usr/bin/env python3
"""Behavioral contract for scripts/cowork-doctor.sh.

The doctor exists so a session can answer "is Cowork ready here, and which
model would `auto` pick" in one call instead of probing five scripts.
"""
import json
import os
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DOCTOR = ROOT / "scripts/cowork-doctor.sh"

CLAUDE_STUB = """#!/usr/bin/env bash
if [[ "${1-} ${2-}" == "plugin list" ]]; then printf '%s\\n' 'cowork@cowork'; exit 0; fi
if [[ "${1-} ${2-}" == "auth status" ]]; then
  printf '%s\\n' '{"loggedIn":true,"authMethod":"claude.ai","apiProvider":"firstParty","subscriptionType":"max"}'
  exit 0
fi
if [[ "${1-}" == "--version" ]]; then printf '%s\\n' '9.9.9 (Claude Code)'; exit 0; fi
exit 0
"""
CODEX_STUB = """#!/usr/bin/env bash
if [[ "${1-}" == "--version" ]]; then printf '%s\\n' 'codex-cli 9.9.9'; exit 0; fi
exit 0
"""
AGY_STUB = """#!/usr/bin/env bash
if [[ "${1-}" == models ]]; then printf '%s\\n' 'gemini-9.1-flash-medium'; exit 0; fi
if [[ "${1-}" == "--version" ]]; then printf '%s\\n' 'agy 9.9.9'; exit 0; fi
exit 0
"""


def run(command, *, env, cwd=ROOT, succeeds=True):
    result = subprocess.run(
        [str(part) for part in command], cwd=cwd, env=env, text=True,
        capture_output=True, timeout=10,
    )
    assert (result.returncode == 0) == succeeds, (
        result.returncode, result.stdout, result.stderr
    )
    return result


with tempfile.TemporaryDirectory(prefix="cowork-doctor-") as temporary:
    tmp = Path(temporary)
    fake_bin = tmp / "bin"
    fake_bin.mkdir()
    for name, body in (("claude", CLAUDE_STUB), ("codex", CODEX_STUB), ("agy", AGY_STUB)):
        executable = fake_bin / name
        executable.write_text(body)
        executable.chmod(0o755)

    def environment(home):
        env = {key: value for key, value in os.environ.items()
               if not key.startswith("ANTHROPIC_")}
        env.update(PATH=f"{fake_bin}:{os.environ['PATH']}", HOME=str(home),
                   CODEX_HOME=str(home / ".codex"),
                   XDG_STATE_HOME=str(tmp / "state"))
        return env

    ready_home = tmp / "ready-home"
    ready_home.mkdir()
    ready = environment(ready_home)
    run([ROOT / "install.sh", "--agent", "all"], env=ready)

    # A ready installation reports success and the plugin version.
    human = run([DOCTOR], env=ready)
    assert "Cowork doctor: ready" in human.stdout
    assert "claude" in human.stdout and "plugin version" in human.stdout
    assert "opus" not in human.stdout  # live model resolution stays opt-in

    report = json.loads(run([DOCTOR, "--json"], env=ready).stdout)
    assert report["ready"] is True
    assert isinstance(report["checks"], list) and report["checks"]
    for check in report["checks"]:
        assert set(check) == {"name", "state", "detail"}, check

    # A home without links is reported with the exact problems, not a summary.
    broken = environment(tmp / "broken-home")
    (tmp / "broken-home").mkdir()
    failed = run([DOCTOR], env=broken, succeeds=False)
    assert "Cowork doctor: NEEDS ATTENTION" in failed.stdout
    assert "Missing:" in failed.stdout
    assert json.loads(run([DOCTOR, "--json"], env=broken, succeeds=False).stdout)["ready"] is False

    # --live resolves the peers' current models instead of pinning a version.
    live = run([DOCTOR, "--live"], env=ready)
    assert "claude model" in live.stdout and "opus" in live.stdout
    assert "gemini model" in live.stdout and "gemini-9.1-flash-medium" in live.stdout

print("Cowork doctor contract: PASS")
