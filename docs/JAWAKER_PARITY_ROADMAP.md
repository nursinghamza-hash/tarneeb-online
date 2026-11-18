# Tarneeb Global — Jawaker Parity Work

## Scope and reference

This is an independent Tarneeb implementation. Jawaker is a gameplay and UX reference only; the project does not copy Jawaker source code, private APIs, protected artwork, or branding.

The supplied `tarneeb_global_pro.html` was inspected as a local browser mock-up/feature specification. It describes the table layout, auction, suit selection, card tracker, score history, quick-chat phrases, settings and 0099 development console. It is not the Jawaker Android APK. The separate APK mentioned as a Drive file was not available for direct inspection in this session.

## Rules reference

Jawaker's published rules describe four players in opposite partnerships, 52 cards and 13 cards per player; counterclockwise play; bidding from 7 to 13 starting at the dealer's right; passing exits the current auction; the winning bidder chooses trump and leads; players follow suit if possible; trump beats non-trump. The published score system is +26 for a successful declared 13, +16 for an unannounced sweep, and -16 for a failed declared 13.

Reference: https://blog.jawaker.com/en/tarneeb-rules-en/

The supplied HTML/brief uses a custom score system of +16 for a successful declared 13 and +14 for an unannounced sweep. The app keeps these as separate presets instead of silently mixing the two rule sets.

## Implemented on `main`

### Table and cards
- Server seats: 0 south, 1 east/right, 2 north/partner, 3 west/left. Teams are 0+2 versus 1+3.
- Flutter rotates the table and trick-card positions around the local player so the player's own hand remains at the bottom from every seat.
- The friend-room lobby presents the three other seats as partner choices before the host can start; the server validates the host, selected occupied seat, and connected status.
- Each hand is sorted by suit and rank, A (14) down to 2. Once trump is selected, trump cards move to the beginning.
- Each player sees their own 13 cards. Normal game state never sends opponents' unplayed cards. Opponents' remaining card counts are displayed as card-back fans.
- The score cross maps each physical seat to its team score, so the two partners always display the same score. A contract badge appears at the bidder's avatar: gold while unresolved, green when the contract target is reached, and red when the completed round fails.

### Dealing and bidding
- Server uses cryptographic Fisher–Yates shuffle. It supports one-card-at-a-time dealing, optional 4-3-3-3 batches, and a manual cut phase.
- Bidding starts to the dealer's right and moves counterclockwise. Valid bids are 7–13, and each new bid must exceed the current bid.
- Passing is final for that auction; the server rejects later bids from a player who passed.
- If the first three players pass without a bid, the dealer must open at 7.
- A bid of 13 closes the auction immediately.
- Auction and trump selection are separate phases. Only the highest bidder selects the trump suit after the auction; a bot winner selects automatically.
- The bidder then leads the first trick.

### Trick play and score
- Server-authoritative validation enforces following suit whenever the player has the led suit. The Flutter hand dims only off-suit cards while the player holds the led suit; when void in that suit, every card remains playable.
- If the player is void in the led suit, any card may be played. The winner is the highest trump if a trump was played; otherwise, the highest card in the led suit.
- The fourth card remains visible briefly so all clients can see the completed trick before resolution. The trick winner leads the next trick.
- Match targets are 31 (default), 41, and 61.
- Default scoring in the new-room screen is the Jawaker preset: successful declared 13 = +26; unannounced sweep = +16; failed declared 13 = -16.
- The supplied custom preset remains separately selectable: successful declared 13 = +16; unannounced sweep = +14; failed declared 13 = -16.
- If declared 13 fails, the defending team receives its actual trick count only; no unannounced-sweep bonus is stacked onto the failed declared 13.

### AI practice
- A practice room fills seats 1–3 with أبو شهاب (partner), الزعيم (right opponent), and العقيد (left opponent).
- Practice mode is the default selection on the home screen; selecting it creates a bot-filled table and the backend starts the first deal automatically, without waiting for a manual start action or three additional human players.
- Bots use heuristic bidding, avoid unnecessary overbidding against their partner, follow suit, and use cooperative card-selection rules.
- A player can restart an AI practice match without waiting for the three bots to vote again.
- Current AI is a first heuristic version, not an expert/grandmaster engine. It still needs simulation and human gameplay testing.

### 0099 development diagnostics
- Emoji reactions remain available during play.
- At the user's request, the card tracker, round-history panel, and quick-chat message controls/bubbles were removed from the mobile interface and the quick-chat socket event was removed from the server.
- 0099 is a host-only toggle. It reveals all four hands, including the host's own hand, in a compact live panel; entering the code a second time hides the panel and returns to normal play.
- `REPORT_DEBUG_PIN` can override the default code. `DEBUG_TOOLS_ENABLED=false` disables the diagnostic mode. The server only includes hidden hands in the state sent to the host seat after the toggle is enabled.
- Do not use 0099 during public competitive play.

### Dealing fairness
- The public default uses a cryptographically shuffled deck. The HTML mock-up's high-action/VIP advantage/minimum-HCP filters deliberately bias hand strength; these are not enabled in public rooms so the server cannot secretly favor a player.
- Batch dealing and manual cut remain selectable.

## Validation

- Backend CI runs syntax checks and Node regression tests for rules, dealing, auction/trump selection, scoring and AI choices.
- Android CI runs backend syntax and regression tests, Flutter dependency resolution, Android release APK compilation and artifact upload.
- These checks do not replace end-to-end multiplayer tests with four independent clients or real-device testing.

## Remaining work and release gates

- Improve AI card counting, signalling, difficulty levels and partnership strategy.
- Replace the initial emoji avatars with a polished set of original illustrated profile portraits.
- Tune card-face proportions, card backs, and deal/trick animations against screenshots from real target devices.
- Complete richer card movement/deal/trick/round animations and tune the sound mix on real Android/iOS devices.
- Add persistent profiles, friends, clubs, tournaments, moderation, and robust reconnect-safe room persistence.
- Test complete matches with four independent Socket.IO clients and on Android/iOS devices.
- Confirm Render is running the exact backend commit used by the APK.
- Produce and test a signed production release before calling the app production-ready.

## Safe release rule

Do not merge or distribute a production release solely because CI passes. Verify the backend deployment, test full matches, and test the APK on real devices first.
