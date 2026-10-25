"""The static check's rules for this repository's layout (dev/harness/docs/static-check.md,
"Plugins").

| Check | What it catches |
| --- | --- |
| `claude-md` | A `CLAUDE.md` anywhere in the repository outside `dev/harness` and git-ignored paths: the agent instructions live in the `AGENTS.md` files. |
"""
import os
import subprocess

from rules import check

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


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
