# whip_threecard

Casino three card poker on whip. You sit at one of the casino's own poker tables, and a dealer deals three cards to each player and three to themselves. Up to four players share a table. Bets go through whip's money, so every one appears on the activity log.

## How it plays

1. **Sit down.** Walk up to a free chair and press **E** on *Sit down*.
2. **Place your Ante.**
   - **↑ / ↓** changes the amount by the table's step.
   - **← / →** jumps to the minimum or maximum.
   - **Enter** puts down the Ante. The first Ante at a table opens a 20 second window for everyone.
3. **Pair Plus (optional).** With the Ante down, **Enter** again puts down a Pair Plus bet of the amount shown. Once everyone seated has an Ante down, the window closes after 6 seconds. **Backspace** takes your bets back while the window is still open.
4. **The deal.** Three cards each, and three to the dealer. Only you see your own cards: on the felt, in your panel and named ("Pair of Queens"). Everyone else sees the backs.
5. **Play or fold.**

   | Key | Action |
   | --- | --- |
   | **Enter** | Play: a second bet the size of your Ante |
   | **Space** | Fold: your Ante is lost (your Pair Plus still counts) |

   You have 30 seconds to decide (`Config.Timing.decideSeconds`). If time runs out, you fold.
6. **The dealer** turns their cards over, then each seat's.
   - **The dealer qualifies** with Queen high or better.
   - **Dealer doesn't qualify:** your Ante pays 1:1 and your Play bet comes back.
   - **Dealer qualifies:** the better hand wins. A win pays Ante and Play 1:1 each. A tie gives both back.

**C** toggles the camera over your shoulder, and **V** switches GTA's views, first person included. **Backspace** gets up.

## Payouts (Config.Rules)

Hands, best first: straight flush, three of a kind, straight, flush, pair, high card. A-2-3 is the lowest straight.

| Hand | Ante Bonus | Pair Plus |
| --- | --- | --- |
| Straight flush | 5:1 | 40:1 |
| Three of a kind | 4:1 | 30:1 |
| Straight | 1:1 | 6:1 |
| Flush | | 4:1 |
| Pair | | 1:1 |

- **Ante Bonus** is paid on the Ante for any hand you played, whatever the dealer has and even if the dealer wins.
- **Pair Plus** pays on your own hand alone, whether you played or folded and whatever the dealer has.

There's a fresh shuffled deck every hand.

## Chips

Bets are in **Casino Chips**, `casino_chips`. That's **whip_blackjack**'s item: it registers the chips, and its cashier sells them and buys them back (`/bjcashier` places one). Run whip_blackjack alongside, or set `Config.Money.currency = nil` to bet plain cash. If the item is missing, the server console says so 15 seconds after start.

## Leaving

| When you leave | What happens |
| --- | --- |
| Before the deal | Your bets come back |
| After the deal, before deciding | You fold. Your Pair Plus still plays |
| After playing | Your hand is settled with everyone else's |

A win is paid to your character even if you've disconnected. If the server or resource stops mid-hand, every stake still on the table is refunded.

## Tables

`Config.Tables` contains k4mb1-casino's own poker tables, read out of its map files. There are six on the main floor, one in the high limit room and one in the penthouse lounge. `spawn = false` makes whip_threecard find each one in the map.

**No new table prop is needed.** k4mb1 places GTA's own `vw_prop_casino_3cardpoker_01` / `01b`, and their felt is printed for three card poker. `texture` (0 green, 1 red, 2 blue, 3 purple) changes the felt colour if you want.

The penthouse table belongs to k4mb1's lounge entity set `k4mb1_apart_lounge_room_04`, which k4mb1's `client2.lua` leaves off. It turns on `_01`, the blackjack lounge, instead. Swap them there to use the poker lounge.

| Field | What it does |
| --- | --- |
| `coords`, `heading` | The table's origin and the direction it faces |
| `model` | `vw_prop_casino_3cardpoker_01` or `vw_prop_casino_3cardpoker_01b` |
| `spawn` | `true` to place the table ourselves. `false` if the map already has one there |
| `texture` | The felt colour |
| `min`, `max`, `step` | Bet limits, and how much the arrow keys change the bet (`step` defaults to `min`) |

## Setting it up

1. Put `whip_threecard` in resources and `ensure whip_threecard` after whip_core and whip_blackjack.
2. If `sf-tcp` is still running, stop it. It replaces k4mb1's roulette tables with poker tables.
3. Stand at a table and run `/tcpedit` to put the cards, chips and dealer where they belong (see below). Until you do, they go by the `Config.Layout` numbers, which are a guess.
4. If the dealer turns to the wrong chair when dealing, change `Config.AnimSeats`: `{ 4, 3, 2, 1 }` (mirrored, the default) or `{ 1, 2, 3, 4 }`.

## The layout editor: /tcpedit

Stand at a table and run `/tcpedit`. A ghost appears for every card and chip spot, and the dealer stands where they'll stand. Move each one to where it belongs. Saving needs the `whip.devtools` ACE.

| Key | What it does |
| --- | --- |
| **Scroll** | Next or previous item. **Shift + Scroll** jumps a whole seat |
| **Arrows** | Move the item, in the direction you're looking. On "which chair", **Left/Right** picks the chair |
| **Q / E** | Turn the item |
| **PgUp / PgDn** | Raise or lower the item (for the dealer, how high their hips sit) |
| **X** | On a card: whole hand on or off. On, the three cards move and turn together |
| **Shift** | Hold for fine movement |
| **G** | Put the item back where it started |
| **Enter** | Save for this table's model |
| **Shift + Enter** | Save for every table model (`01` and `01b`) |
| **Backspace** | Leave. Press twice if you haven't saved |

The items:
- **The dealer:** where they stand, their cards 1–3, and the deck:
  - *The deck on the table* is where it lies between hands.
  - *The deck in his hand* is how it sits in the dealer's left hand from picking it up to putting it down. While you edit, the dealer stands holding a deck the way he does while players decide. Here **Up/Down** and **Left/Right** move it within the hand, **PgUp/PgDn** moves it up and down, **Q/E** turns it and **Z/C** tilts it.
- **Each seat:**
  - which chair it is;
  - Ante, Play and Pair Plus chips (a 500, a 1k and a 100 stack, so you can tell them apart);
  - cards 1–3.

You can walk around the table while you edit (WASD) to check from every side. Saving writes `layout.json` in this resource, and every game picks it up at once.

## What's different from sf-tcp

- **Cards stay secret.** Only you see your cards before the reveal, and no one sees the dealer's.
- **The right payouts.**
  - A win pays Ante and Play 1:1 each. sf paid three times the Ante back instead of four.
  - When the dealer doesn't qualify, the Ante pays 1:1. sf only gave the stakes back.
  - The Ante Bonus is paid whether or not the dealer qualifies.
- **Any bet within the limits,** not a fixed list of chip sizes.
- **The poker tables stay poker tables.** sf hid k4mb1's roulette tables and put poker tables in their place.
- **The table shows correctly when you walk up mid-hand.**
- **Disconnecting doesn't cancel a hand.** It's settled, and a win is paid to your character.
