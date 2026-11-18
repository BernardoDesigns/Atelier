# Vetting rule

Before installing any third-party skill, mod, plugin or MCP server, read its
SKILL.md and every script it ships. All of them, not a skim of the README.

Why: mods are not sandboxed. A mod runs as you, with your files, your shell
and your keys. A February 2026 scan found flaws in over a third of public
skills. A skill is instructions the model follows, so a hostile line in one is
a hostile command in your session.

## Checklist

1. Read SKILL.md top to bottom. Anything that tells the model to ignore its
   rules, hide actions from you, or fetch and run something is a no.
2. Read every script and hook file. Look for network calls, `curl | sh`,
   `eval`, base64 blobs, and reads of `~/.ssh`, `~/.aws`, `.env` or the
   keychain.
3. For an MCP server, list the tools it exposes and the scopes it asks for.
   Read-only until you have a reason otherwise.
4. Check what it writes and where. Anything outside its own folder or the
   current repo is a flag.
5. Check where it came from: who maintains it, when it last changed, whether
   the install command pulls from a pinned version or from `main`.
6. Pin the version or the commit. Don't track a moving branch.
7. Try it in a throwaway repo and a throwaway session first, with a test
   `HOME` if it touches settings.
8. If you can't read all of it, or you don't understand part of it, don't
   install it.

Re-vet on every update. A clean v1 says nothing about v2.
