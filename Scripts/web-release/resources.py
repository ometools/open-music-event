#!/usr/bin/env python3
"""Report build capacity without exposing environment variables or credentials."""
import json
from pathlib import Path


def snapshot():
    result = {}
    memory = Path("/proc/meminfo")
    if memory.exists():
        for line in memory.read_text().splitlines():
            name, value = line.split(":", 1)
            if name in ("MemTotal", "MemAvailable", "SwapTotal", "SwapFree"):
                result[name] = value.strip()
    for name in ("memory.max", "memory.current", "memory.peak", "memory.events"):
        path = Path("/sys/fs/cgroup") / name
        if path.exists():
            result[name] = path.read_text().strip()
    legacy = Path("/sys/fs/cgroup/memory/memory.limit_in_bytes")
    if legacy.exists():
        result["memory.limit_in_bytes"] = legacy.read_text().strip()
    return result


if __name__ == "__main__":
    print(json.dumps(snapshot(), sort_keys=True))
