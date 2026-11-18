# Tarneeb Global — Jawaker Parity Work

## Scope and reference

This project is an independent Tarneeb implementation. Jawaker is used as a gameplay and UX reference; this repository does not copy its source code, private APIs, proprietary assets, or branding.

The uploaded `tarneeb_global_pro.html` file is a browser mock-up, not the Jawaker APK. It provides design/feature requirements such as the four-seat table, auction overlay, suit selection, report dialog, card tracker, score history, settings, and custom dealing options.

## Verified base rules

The standard Tarneeb rules published by Jawaker describe:
- Four players in two partnerships, 52 cards, 13 cards per player.
- Counterclockwise play; dealer moves to the player on the right after a round.
- Auction starts to the dealer's right. Bids represent 7–13 tricks; each bid must exceed the previous bid. A pass removes the player from that auction.
- Highest bidder selects the trump suit and leads the first trick.
- Players must follow the led suit if possible. If unable, any card may be discarded; trump beats non-trump.
- Successful contracts score the number of tricks won; a failed contract deducts the bid and defenders score their actual tricks.
- Unannounced sweep (13 tricks without bidding 13): +16; declared and successful 13: +26; failed bid of 13: −16.
- Match targets: 31, 41, or 61.

Reference: https://blog.jawaker.com/en/tarneeb-rules-en/

## Implemented on `feature/jawaker-tarneeb-parity-v1`

- Server seat geometry: 0 south, 1 east/right, 2 north, 3 west/left. Flutter rotates these positions around the current local player so the local hand remains at the bottom for any seat.
- Deal and bidding begin to the dealer's right and proceed counterclockwise.
- Centralized rules helpers for seat order, card dealing, follow-suit legality, trick winner, and scoring.
- Random one-card-at-a-time deal and optional 4-3-3-3 batch deal.
- Dealer must open at 7 or higher if the other three players pass without a bid.
- A passed player cannot re-enter the auction; the server enforces this independently of the UI.
- Server keeps the fourth card visible briefly so all clients can render the completed trick before it resolves.
- Public played-card history powers the card tracker. Opponents' unplayed cards are not sent in ordinary game state.
- A persistent in-room round history records the contract, trump suit, trick counts, bid result, and before/after team scores.
- Optional AI practice rooms fill the three other seats with bots named Al-Zaeem, Abu Shehab and Al-Aqeed; bots use a separate heuristic module for bidding and legal cooperative card play.
- Intentionally biased dealing presets from the HTML mock-up (high-action / VIP advantage / minimum-HCP filtering) are not enabled in fair public rooms. The default server shuffle uses cryptographic Fisher–Yates; batch dealing and manual cut remain available. Normal friend rooms remain four-human rooms.
- 0099 diagnostics are gated by server environment settings and restricted to the room host. They can reveal the other three hands, request a tactical card suggestion highlighted in green, and optionally boost the host's hand before the first card is played.
- Regression tests cover table orientation, deal order, batch distribution, bidding order, forced opening, irreversible pass, follow-suit, trick winner, scoring and invalid inputs.
- Pull request CI runs backend syntax/rules tests and Flutter analysis/Android build.

## Scoring variants

The server default follows Jawaker's published scoring: declared Kaboot +26, unannounced sweep +16, failed declared 13 −16.

The pure rules helper accepts custom options for house rules. The values requested in the supplied brief (declared Kaboot +16 and sweep +14) can be represented as:
`scoreRound(scores, tricks, bidTeam, bidAmount, { declaredKabootPoints: 16, sweepPoints: 14 })`

The room-creation screen now exposes both presets, sends the selected preset to the authoritative server, and the server applies it for round scoring.

## Developer-only 0099 setup

On the Render service, set both:
- `REPORT_DEBUG_PIN=0099`
- `DEBUG_TOOLS_ENABLED=true`

Only the host of a room can use the diagnostics. Do not enable this for public competitive rooms. Leave both unset in normal production.

## Not yet implemented / release blockers

- Full AI practice mode (partner and two opponents). The current online table requires four real players; the HTML mock-up's bot characters are not yet part of the multiplayer server.
- Animated card dealing and complete turn/trick animations; the fourth card now has a short reveal delay, but this is not yet a full animation suite.
- Persistent player profiles, ratings, leaderboards, clubs, friends, voice chat, gifts, tournaments, abuse/report moderation and reconnection-safe persistent rooms.
- Additional scoring regression tests cover both selectable presets.
- End-to-end multiplayer tests with four actual socket clients, plus device testing on Android and iOS.
- Production deployment verification and final signed release APK.

## Safe release rule

Do not merge this branch or distribute an APK as a final release until both GitHub Actions workflows pass, the multiplayer scenarios above are tested, and the Render service is confirmed to be running the matching backend commit.
