# Releasing

Every version gets two write-ups: the technical one in `CHANGELOG.md` and a plain-English one in the README. A release isn't ready until both exist.

## Checklist

1. **CHANGELOG.md:** move the `[Unreleased]` entries under a new `## [x.y.z] - YYYY-MM-DD` heading, with a one-paragraph summary, and add the link at the bottom.
2. **README release notes:** add an entry at the top of the `## Release notes` section, newest first, in this shape:

   ```
   **[x.y.z](https://github.com/BernardoDesigns/atelier/releases/tag/vx.y.z), Month D, YYYY: a short title**

   A few sentences for a non-technical reader: what changed and why it matters.
   ```

   Write it for someone who has never opened a terminal. Say what the agents or tools can now do, not which files changed. No file names, flags or jargon, and no em dashes. If a technical term is unavoidable, explain it in the same sentence.
3. **Release notes for GitHub:** the release body can reuse the README entry plus the CHANGELOG detail.
4. **Checks:** run every suite, including `bash tests/release-notes/check.sh`, which fails if any CHANGELOG version is missing its README entry or the newest one isn't first.
5. **Tag:** only after the owner says go. Annotated tag on the merge commit, pushed, then publish the GitHub release.
