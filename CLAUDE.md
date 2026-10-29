@AGENTS.md

## Claude Code

`AGENTS.md` above is the single source of truth for this repo — every agent
reads it (Claude Code, Copilot, Cursor, Codex, …). This file only imports it, so
nothing is duplicated: put repo instructions in `AGENTS.md`, not here.

Claude Code v2.1.277+ reads `AGENTS.md` natively, but ONLY when no `CLAUDE.md`
(or `CLAUDE.local.md`) sits in the working directory or above it. This bridge
keeps the instructions loading in the cases where that doesn't hold: an older
Claude Code, a session that can't read `AGENTS.md` (Bedrock, telemetry off), a
dev with their own `CLAUDE.local.md`, or **Project instructions** set to
`claude-md`.
