#!/usr/bin/env bash
# Stop hook — if any tracked .swift file is dirty this turn, run a debug build
# and surface failures. Debug build is used (not release) for speed; build-app.sh
# remains the release path. Silent on success.
set -uo pipefail

cd "$(dirname "$0")/../.." || exit 0

# Bail if not a git repo (defensive — the project always is)
git rev-parse --git-dir >/dev/null 2>&1 || exit 0

# Any uncommitted Swift changes? Includes staged + unstaged + untracked.
if ! { git diff --name-only --diff-filter=ACMR -- '*.swift'; \
       git diff --cached --name-only --diff-filter=ACMR -- '*.swift'; \
       git ls-files --others --exclude-standard -- '*.swift'; } | grep -q .; then
  exit 0
fi

# Build silently; on failure surface the tail of the output as hook feedback.
out=$(swift build 2>&1)
rc=$?
if [ $rc -ne 0 ]; then
  echo "swift build failed (exit $rc) — last 40 lines:" >&2
  echo "$out" | tail -n 40 >&2
  # Non-zero exit on a Stop hook becomes feedback to Claude.
  exit 2
fi
exit 0
