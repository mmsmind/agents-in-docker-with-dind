#!/usr/bin/env python3
"""Export a standalone Compose file from the pinned upstream and DinD overlay."""
import json
import subprocess
import sys
from pathlib import Path

import yaml

root = Path(__file__).resolve().parent.parent
output = Path(sys.argv[1])
result = subprocess.run(
    [str(root / "compose"), "config", "--no-interpolate", "--no-path-resolution",
     "--no-env-resolution", "--format", "json"],
    cwd=root, check=True, capture_output=True, text=True,
)
config = json.loads(result.stdout)
# These names are computed from the build checkout, not the deployment directory.
config.pop("name", None)
for collection in ("networks", "volumes"):
    for definition in config.get(collection, {}).values():
        definition.pop("name", None)
# The release distributes a published image, not a local Dockerfile/build context.
agent = config["services"]["agent"]
agent.pop("build", None)
# With interpolation disabled, Compose cannot infer that this variable is a host
# path and represents it as a named volume. Preserve the upstream bind semantics.
ssh_mounts = [v for v in agent["volumes"] if v.get("target") == "/home/agent/.ssh/authorized_keys"]
if len(ssh_mounts) != 1 or "SSH_AUTHORIZED_KEYS" not in ssh_mounts[0].get("source", ""):
    raise SystemExit("Unexpected upstream SSH authorized_keys mount")
ssh_mounts[0]["type"] = "bind"
ssh_mounts[0].pop("volume", None)
ssh_mounts[0]["bind"] = {"create_host_path": True}
output.write_text(yaml.safe_dump(config, sort_keys=False), encoding="utf-8")
