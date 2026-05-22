---
description: Cut a new Murmur release — bump VERSION, build, tag, publish GitHub release.
argument-hint: <new-version e.g. 2026.05.22.0>
---

You are cutting a new Murmur release. The version argument is `$ARGUMENTS`.

## Hard preconditions — fail fast if any are missing

1. `$ARGUMENTS` must be a dotted-integer version like `2026.05.22.0` — **no `v` prefix in the argument**. The `v` is added only when creating the git tag and GitHub release.
2. Working tree must be clean (`git status --porcelain` empty). If not, stop and tell the user to commit/stash first.
3. Current branch must be `main` (or confirm with the user before proceeding off-main).
4. `gh auth status` must succeed. If not, stop and tell the user to run `gh auth login`.

## Steps

Do these in order. If any step fails, STOP and report — do not paper over with `--force` or `--no-verify`.

1. **Bump `VERSION` in `build-app.sh`** (line 15) to `$ARGUMENTS`. Use Edit, not sed.
2. **Build the artifact:** `./build-app.sh`. This writes `dist/Murmur.zip` and `dist/Murmur.app`. Confirm `dist/Murmur.zip` exists after.
3. **Commit:** `git add build-app.sh && git commit -m "release: v$ARGUMENTS"`. Use a HEREDOC; include the `Co-Authored-By: Claude` trailer per the standard commit recipe.
4. **Tag:** `git tag v$ARGUMENTS` (with the `v` prefix — `UpdateChecker` and the existing release history both require it).
5. **Push:** `git push origin main "v$ARGUMENTS"`.
6. **Publish release:** `gh release create "v$ARGUMENTS" --latest --title "Murmur v$ARGUMENTS" --notes "<short release notes>" dist/Murmur.zip`. Draft the notes from the diff since the previous tag — `git log --oneline "$(git describe --tags --abbrev=0 HEAD^)..HEAD"` gives the commit list. Keep notes to 3–6 bullet points.
7. **Verify:** `gh release view "v$ARGUMENTS"` and report the URL to the user.

## Why each step matters

- **`v` prefix on the tag (not the argument):** GitHub Releases sorts tags by format; bare-numeric tags scatter visually among the existing `v…` history. `UpdateChecker` strips the `v` before comparing to `CFBundleShortVersionString`, so the numeric body of the tag must match `VERSION` exactly.
- **Build before commit:** if `swift build` is broken, we want to know before the tag exists.
- **Tag after commit, push both together:** so the tagged commit is the version-bump commit, not a parent.
- **`--latest`** flag is what flips the GitHub "Latest" badge that users land on from `/releases/latest` (which is what `UpdateChecker` polls).

## What to report at the end

- Released version (`v$ARGUMENTS`)
- Release URL from `gh release view`
- Reminder: users see the update badge within 6 hours of next launch (UpdateChecker polls every 6h).
