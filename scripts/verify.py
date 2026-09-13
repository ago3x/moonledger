#!/usr/bin/env python3
"""Run the documented release gate. Optional MOON_BIN selects a local toolchain."""
from pathlib import Path
import os, subprocess, sys
root=Path(__file__).resolve().parents[1]
moon=os.environ.get("MOON_BIN","moon")
for command in [
    [moon,"fmt","--check"],
    [moon,"check"],
    [moon,"test"],
    [moon,"build","--target","js","--release"],
    [sys.executable,"tests/e2e.py"],
]:
    print("+ "+" ".join(command),flush=True)
    result=subprocess.run(command,cwd=root,timeout=120)
    if result.returncode: raise SystemExit(result.returncode)
print("MoonLedger verification passed.")
