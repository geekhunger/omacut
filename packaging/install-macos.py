#!/usr/bin/env python3
"""Install a rebuilt executable into the existing, deployed macOS app bundle."""

from datetime import datetime
from pathlib import Path
import os
import shutil
import subprocess
import tempfile


def run(*args):
    return subprocess.run(args, check=True, capture_output=True, text=True).stdout


def install():
    source = Path(__file__).resolve().parent.parent
    built = source / "build/omacut.app/Contents/MacOS/omacut"
    app = Path("/Applications/Omacut.app")
    support = Path.home() / "Library/Application Support/Omacut"
    updates = support / "updates"
    backups = support / "backups"
    updates.mkdir(exist_ok=True)
    backups.mkdir(exist_ok=True)
    if not built.is_file() or not app.is_dir():
        raise RuntimeError("Build first; an existing deployed Omacut.app is required.")

    with tempfile.TemporaryDirectory(prefix="bundle-update-", dir=updates) as temp:
        staged = Path(temp) / "Omacut.app"
        run("ditto", str(app), str(staged))
        executable = staged / "Contents/MacOS/omacut"
        shutil.copy2(built, executable)

        # Rebuilding restores Homebrew load commands. Bundle plugins already
        # use bundled Qt, so mixing these with Homebrew Qt crashes at startup.
        for line in run("otool", "-L", str(executable)).splitlines()[1:]:
            dependency = line.strip().split(" (", 1)[0]
            if not dependency.startswith("/opt/homebrew/"):
                continue
            if ".framework/" in dependency:
                framework, suffix = dependency.split(".framework/", 1)
                relative = Path(framework).name + ".framework/" + suffix
            else:
                relative = Path(dependency).name
            if not (staged / "Contents/Frameworks" / relative).is_file():
                raise RuntimeError(f"Missing bundled dependency: {relative}")
            run("install_name_tool", "-change", dependency,
                "@executable_path/../Frameworks/" + relative, str(executable))

        commands = run("otool", "-l", str(executable)).splitlines()
        for i, line in enumerate(commands):
            if line.strip() == "cmd LC_RPATH":
                path = commands[i + 2].strip().split(" ")[1]
                if path.startswith("/opt/homebrew/"):
                    run("install_name_tool", "-delete_rpath", path, str(executable))
        if "/opt/homebrew/" in run("otool", "-L", str(executable)):
            raise RuntimeError("Executable still links to Homebrew libraries.")
        run("codesign", "--force", "--deep", "--sign", "-", str(staged))
        run("codesign", "--verify", "--deep", "--strict", str(staged))

        backup = backups / ("Omacut-before-bundle-update-" +
                            datetime.now().strftime("%Y%m%d-%H%M%S-%f") + ".app")
        os.rename(app, backup)
        try:
            os.rename(staged, app)
            run("codesign", "--verify", "--deep", "--strict", str(app))
        except BaseException:
            if app.exists():
                os.rename(app, updates / ("failed-" + backup.name))
            os.rename(backup, app)
            raise
        print(f"Installed {app}; previous app preserved at {backup}")


if __name__ == "__main__":
    install()
