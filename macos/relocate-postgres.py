"""Make the packaged PostgreSQL libraries resolve relative to each binary."""

import os
from pathlib import Path
import subprocess
import sys


root = Path(sys.argv[1])
prefix = sys.argv[2] + "/"
for binary in root.rglob("*"):
    if not binary.is_file() or binary.is_symlink():
        continue
    info = subprocess.check_output(["/usr/bin/file", "-b", binary], text=True)
    if "Mach-O" not in info:
        continue
    # -D identifies a library's own install name, separate from its imports.
    names = subprocess.check_output(["otool", "-D", binary], text=True).splitlines()[1:]
    changes = ["-id", f"@rpath/{binary.name}"] if names else []
    imports = subprocess.check_output(["otool", "-L", binary], text=True).splitlines()[1:]
    for line in imports:
        dependency = line.strip().split(" (", 1)[0]
        if dependency.startswith(prefix) and dependency not in names:
            target = root / dependency.removeprefix(prefix)
            if not target.exists():
                raise SystemExit(f"Missing PostgreSQL library: {dependency}")
            relative = os.path.relpath(target, binary.parent)
            changes.extend(["-change", dependency, f"@loader_path/{relative}"])
        elif dependency.startswith(("/opt/homebrew/", "/usr/local/")) and dependency not in names:
            raise SystemExit(f"Unbundled PostgreSQL dependency: {dependency}")
    if changes:
        subprocess.run(["install_name_tool", *changes, binary], check=True)
        subprocess.run(["codesign", "--force", "--sign", "-", binary], check=True)
