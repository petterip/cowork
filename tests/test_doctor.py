#!/usr/bin/env python3
"""Compatibility contract for cowork-doctor.sh."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
DOCTOR = ROOT / "scripts/cowork-doctor.sh"
COWORK = ROOT / "scripts/cowork"


def run(command, *, env, succeeds=True):
    result = subprocess.run(
        [str(part) for part in command], cwd=ROOT, env=env, text=True,
        capture_output=True, timeout=15,
    )
    assert (result.returncode == 0) == succeeds, (
        result.returncode, result.stdout, result.stderr
    )
    return result


with tempfile.TemporaryDirectory(prefix="cowork-doctor-") as temporary:
    tmp = Path(temporary)
    fake_bin = tmp / "bin"
    fake_bin.mkdir()
    peer = fake_bin / "copilot"
    peer.write_text(r'''#!/usr/bin/env bash
if [[ "${1-}" == --version ]]; then printf '%s\n' 'peer-cli 1'; exit 0; fi
if [[ "${1-} ${2-}" == "help config" ]]; then
  printf '%s\n' '  `model`: available:' '    - "peer-alpha-2"' '' '  `other`: value'
  exit 0
fi
if [[ "${1-}" == --help ]]; then printf '%s\n' '  --reasoning-effort <level>'; exit 0; fi
exit 0
''')
    peer.chmod(0o755)
    env = dict(
        os.environ,
        PATH=f"{fake_bin}:{Path(shutil.which('jq')).parent}:/usr/bin:/bin",
        XDG_STATE_HOME=str(tmp / "state"),
    )

    run([COWORK, "setup", "--refresh"], env=env)
    report = json.loads(run([DOCTOR, "--json"], env=env).stdout)
    assert report["schemaVersion"] == 1
    assert report["peers"]["copilot"]["available"] is True

    live = json.loads(run([DOCTOR, "--live", "--json"], env=env).stdout)
    assert live["peers"]["copilot"]["models"] == ["peer-alpha-2"]

    manifest = tmp / "state" / "cowork" / "capabilities.json"
    manifest.unlink()
    failed = run([DOCTOR, "--json"], env=env, succeeds=False)
    assert "missing or stale" in failed.stderr

print("Cowork doctor contract: PASS")
