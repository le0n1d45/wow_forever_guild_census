# Guild Census (WoW Forever addon)

## Workflow

- When you finish a piece of work, commit and push it automatically without asking first.
- Run `lua tests/run.lua` (Lua 5.1) before committing; don't commit with failing tests.
- Tests run headlessly against a stub (`tests/wow_stub.lua`); they don't prove anything about the real client.
