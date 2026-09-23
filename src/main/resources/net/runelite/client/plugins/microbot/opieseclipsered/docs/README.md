# Eclipse Red

Hops safe members worlds collecting the single Eclipse red spawn on the top floor of Guildmaster Apatura's quarters in the Hunter Guild. When the inventory hits the configured threshold, wines are deposited at the Hunter Guild bank.

## Requirements

- Membership
- Hunter Guild access
- Start near the guild. The spawn tile is `1555, 3035, 2`. The bank is `1542, 3041, 0`.

## How it works

1. Walks to the spawn tile.
2. Picks up Eclipse red (item 29415) if it is on the tile.
3. Hops to a random accessible members world that is not PvP, high-risk, bounty, skill-total, LMS, deadman, arena, tournament, seasonal, beta, or fresh start.
4. Repeats until the wine threshold is reached (default 28).
5. Banks at Hunter Guild. Config chooses resume or stop after banking.

Worlds recently visited are skipped for the configured cooldown so the spawn has time to exist again.

## Config

- Wine threshold (inventory size before banking)
- Stop goal: WINES or GP
- Stop after wines (session total, 0 = unlimited)
- Stop after gp (in k): 100 = 100k, 1000 = 1m. Each wine is 700 gp, so 100k needs 143 wines
- After banking: RESUME or STOP
- World cooldown
- Hop delay range
- Avoid empty / overcrowded worlds
- Max wait for wine before hopping
