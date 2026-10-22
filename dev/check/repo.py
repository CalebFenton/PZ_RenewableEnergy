"""The static check's rules for this repository's layout (dev/harness/docs/static-check.md,
"Plugins").

| Check | What it catches |
| --- | --- |
| `claude-md` | A `CLAUDE.md` anywhere in the repository outside `dev/harness` and git-ignored paths: the agent instructions live in the `AGENTS.md` files. |
| `debug-in-contents` | A file under `Contents/` that requires a module under `RenewableEnergy/Debug/` or `PZHarness/`: those are the dev mod's and the harness's, which are not published, so the published mod would fail to load it. |
"""
import os
import subprocess

from rules import check

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CONTENTS = os.path.join(REPO, "Contents") + os.sep
UNPUBLISHED = ("RenewableEnergy/Debug/", "PZHarness/")


@check
def claude_md(mod, game, report):
    # git lists tracked and untracked files minus ignored ones, and a submodule as one entry, so
    # dev/harness (shared with other mods, whose CLAUDE.md is not this repository's) is skipped.
    listed = subprocess.run(["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard"],
                            cwd=REPO, capture_output=True, text=True, check=True).stdout
    for path in sorted(set(listed.split("\0"))):
        if os.path.basename(path) == "CLAUDE.md" and os.path.exists(os.path.join(REPO, path)):
            report.fail("claude-md", os.path.join(REPO, path), None, "put agent instructions in the "
                        "AGENTS.md beside it (or the repository's AGENTS.md) and delete this file")


@check
def debug_in_contents(mod, game, report):
    for lua in mod.lua:
        if not os.path.abspath(lua.path).startswith(CONTENTS):
            continue
        for name, at in lua.calls_with_literal("require"):
            if name.startswith(UNPUBLISHED):
                report.fail("debug-in-contents", lua.path, lua.line(at), "require \"%s\" is a dev-mod or "
                            "harness module, which the published mod lacks; move the code that needs it "
                            "into dev/RenewableEnergyDevHarness" % name)
