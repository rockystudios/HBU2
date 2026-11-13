# HBU Survival integration

This update was built from the `HBU2-main.zip` supplied in this conversation.

## Apply
Extract this ZIP into the existing HBU2 project folder, preserving the paths. It contains:
- one modified file: `HBU2-main/index.html`
- nine new files under `HBU2-main/games/hbu-survival/`

The only change to the existing `index.html` is one HBU Survival entry added to the existing games array. No existing lines were removed or rewritten.

## Game
Open HBU Survival from the existing HBU game library. The game is a standalone browser game and currently keeps inventory/progress in memory only; it does not add Supabase tables, functions, or account persistence.
