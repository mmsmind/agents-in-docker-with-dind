#!/usr/bin/env python3
"""Export a standalone Compose file from the pinned upstream and DinD overlay."""
import sys
from pathlib import Path

import yaml

root = Path(__file__).resolve().parent.parent
output = Path(sys.argv[1])
base_path = root / "upstream/docker-compose.yml"
overlay_path = root / "compose.dind.yml"
base = yaml.safe_load(base_path.read_text(encoding="utf-8"))
overlay = yaml.safe_load(overlay_path.read_text(encoding="utf-8"))

# Fail rather than silently exporting an incomplete configuration if the source
# files start depending on additional local files or new overlay merge rules.
for source, document in ((base_path, base), (overlay_path, overlay)):
    if any("env_file" in service for service in document.get("services", {}).values()):
        raise SystemExit(f"Service env_file is not supported in release export: {source}")
if set(overlay) != {"services"} or set(overlay["services"]) != {"agent", "dind"}:
    raise SystemExit("Unexpected DinD overlay structure; update the release exporter")
agent_overlay = overlay["services"]["agent"]
if set(agent_overlay) != {"image", "build", "ports"}:
    raise SystemExit("Unexpected agent overlay fields; update the release exporter")
if "agent" not in base["services"] or "dind" in base["services"]:
    raise SystemExit("Unexpected upstream services; update the release exporter")

agent = base["services"]["agent"]
if "depends_on" in agent:
    raise SystemExit("Upstream agent has dependencies; update the release exporter")
agent.pop("build", None)  # Release users pull the published image.
agent["image"] = agent_overlay["image"]
agent.setdefault("ports", []).extend(agent_overlay["ports"])
base["services"]["dind"] = overlay["services"]["dind"]

output.write_text(yaml.safe_dump(base, sort_keys=False), encoding="utf-8")
