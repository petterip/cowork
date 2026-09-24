#!/usr/bin/env python3
"""Behavioral contract for model-neutral Cowork setup and resolution."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
COWORK = ROOT / "scripts/cowork"


def run(args, *, env, succeeds=True):
    result = subprocess.run(
        [str(COWORK), *args], cwd=ROOT, env=env, text=True,
        capture_output=True, timeout=15,
    )
    assert (result.returncode == 0) == succeeds, (
        result.returncode, result.stdout, result.stderr
    )
    return result


with tempfile.TemporaryDirectory(prefix="cowork-cli-") as temporary:
    tmp = Path(temporary)
    fake_bin = tmp / "bin"
    fake_bin.mkdir()
    log = tmp / "calls.log"

    tools = {
        "copilot": r'''#!/usr/bin/env bash
printf 'copilot:%s\n' "$*" >>"$CALL_LOG"
if [[ "${1-}" == --version ]]; then printf '%s\n' "${COPILOT_FAKE_VERSION:-peer-cli 1}"; exit 0; fi
if [[ "${1-} ${2-}" == "help config" ]]; then
  printf '%s\n' '  `model`: available:' \
    '    - "peer-alpha-2"' \
    '    - "shared-model-1"' \
    '    - "vendor-series-1"' \
    '    - "vendor-series-2"' '' '  `other`: value'
  exit 0
fi
if [[ "${1-}" == --help ]]; then printf '%s\n' '  --reasoning-effort <level>'; exit 0; fi
exit 0
''',
        "codex": r'''#!/usr/bin/env bash
printf 'codex:%s\n' "$*" >>"$CALL_LOG"
if [[ "${1-}" == --version ]]; then printf '%s\n' 'code-peer 1'; exit 0; fi
if [[ "${1-} ${2-}" == "debug models" ]]; then
  printf '%s\n' '{"models":[{"slug":"peer-beta-7"},{"slug":"shared-model-1"}]}'
  exit 0
fi
exit 0
''',
        "agy": r'''#!/usr/bin/env bash
printf 'agy:%s\n' "$*" >>"$CALL_LOG"
if [[ "${1-}" == --version ]]; then printf '%s\n' 'gravity-peer 1'; exit 0; fi
if [[ "${1-}" == models ]]; then printf '%s\n' 'peer-gamma-3 available'; exit 0; fi
if [[ "${1-}" == --help ]]; then printf '%s\n' '  --effort <level>'; exit 0; fi
exit 0
''',
        "claude": r'''#!/usr/bin/env bash
printf 'claude:%s\n' "$*" >>"$CALL_LOG"
if [[ "${1-}" == --version ]]; then printf '%s\n' 'dialog-peer 1'; exit 0; fi
if [[ "${1-} ${2-}" == "auth status" ]]; then
  printf '%s\n' '{"loggedIn":true}'
  exit 0
fi
if [[ "${1-}" == --help ]]; then printf '%s\n' '  --effort <level>'; exit 0; fi
exit 0
''',
    }
    for name, body in tools.items():
        executable = fake_bin / name
        executable.write_text(body)
        executable.chmod(0o755)

    env = dict(os.environ)
    env.update(
        PATH=f"{fake_bin}:{Path(shutil.which('jq')).parent}:/usr/bin:/bin",
        XDG_STATE_HOME=str(tmp / "state"),
        CALL_LOG=str(log),
    )

    manifest = json.loads(run(["setup", "--refresh", "--json"], env=env).stdout)
    assert manifest["schemaVersion"] == 1
    assert set(manifest["peers"]) == {"agy", "claude", "codex", "copilot"}
    assert manifest["peers"]["copilot"]["reasoningEffortOption"] == "--reasoning-effort"
    assert "peer-alpha-2" in manifest["peers"]["copilot"]["models"]

    # A valid cache rechecks cheap versions but does not rediscover catalogs.
    catalog_calls = log.read_text().count("copilot:help config")
    run(["setup", "--json"], env=env)
    assert log.read_text().count("copilot:help config") == catalog_calls

    explicit = json.loads(run(
        ["resolve", "--peer", "copilot", "--model", "Alpha 2", "--json"], env=env
    ).stdout)
    assert explicit == {"peer": "copilot", "model": "peer-alpha-2"}

    default = json.loads(run(
        ["resolve", "--peer", "copilot", "--json"], env=env
    ).stdout)
    assert default == {"peer": "copilot", "model": None}

    unique = json.loads(run(
        ["resolve", "--model", "Beta 7", "--json"], env=env
    ).stdout)
    assert unique == {"peer": "codex", "model": "peer-beta-7"}

    # A selected peer without a catalog passes user text through for that CLI
    # to validate; Cowork does not maintain aliases.
    uncatalogued = json.loads(run(
        ["resolve", "--peer", "claude", "--model", "user-choice", "--json"], env=env
    ).stdout)
    assert uncatalogued == {"peer": "claude", "model": "user-choice"}

    ambiguous_peer = run(
        ["resolve", "--peer", "copilot", "--model", "vendor series", "--json"],
        env=env,
    )
    assert json.loads(ambiguous_peer.stdout) == {"peer": "copilot", "model": "vendor series"}

    ambiguous_global = run(
        ["resolve", "--model", "shared model 1", "--json"],
        env=env, succeeds=False,
    )
    assert "multiple peers" in ambiguous_global.stderr

    # A peer CLI version change invalidates the cache and refreshes discovery.
    changed = dict(env, COPILOT_FAKE_VERSION="peer-cli 2")
    run(["setup", "--json"], env=changed)
    assert log.read_text().count("copilot:help config") == catalog_calls + 1

print("Cowork setup and resolver contract: PASS")
