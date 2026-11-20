Config = {}

-- ============================================
-- Money
-- ============================================
-- Bets are taken with whip's ChargePlayer and paid with PayPlayer, so every one is on the activity log.
--   method:   'cash', 'bank' or 'auto' (cash if they carry enough, else the bank)
--   currency: an item that counts as money instead of cash. 'casino_chips' is whip_blackjack's chips item, bought
--             and cashed in at its cashier: run whip_blackjack too. nil = plain cash.
Config.Money = {
    method   = 'cash',
    currency = 'casino_chips',
}

-- ============================================
-- The rules
-- ============================================
-- You put down an Ante (and, if you like, a Pair Plus). You see your three cards, then Play (a second bet the
-- size of the Ante) or Fold (the Ante is lost). The dealer needs a Queen high or better to qualify.
--   Dealer doesn't qualify: the Ante pays 1:1, the Play bet comes back.
--   Dealer qualifies:        the better hand wins Ante and Play at 1:1 each; a tie gives both back.
-- Hands, best first: straight flush, three of a kind, straight, flush, pair, high card. A-2-3 is the lowest straight.
Config.Rules = {
    qualifyHigh = 12,   -- the dealer qualifies with this high card or better (12 Queen, 13 King, 14 Ace)
    -- Ante Bonus: paid on the Ante for a hand you played, whatever the dealer has. x times the Ante.
    anteBonus = { straightFlush = 5, three = 4, straight = 1 },
    -- Pair Plus: on your own hand alone (played or folded, whatever the dealer has). x to 1.
    pairPlus  = { straightFlush = 40, three = 30, straight = 6, flush = 4, pair = 1 },
    pairPlusMax = nil,  -- the most a Pair Plus can be. nil: the table's max
}

-- ============================================
-- Timing (seconds, or ms where it says)
-- ============================================
-- The ms ones are how long the dealer's animations take: the server waits them out before the next.
Config.Timing = {
    betSeconds    = 20,     -- the betting window, from the first Ante
    allInSeconds  = 6,      -- once everyone seated has an Ante down, the window shrinks to this (time for Pair Plus)
    decideSeconds = 30,     -- to Play or Fold; time out and you fold
    pickUpMs      = 1800,   -- the dealer picks up the deck
    shuffleMs     = 3000,
    dealSeatMs    = 2800,   -- three cards to one seat
    dealSelfMs    = 3200,   -- three to the dealer
    playerMoveMs  = 2200,   -- a player's play or fold
    flipMs        = 900,    -- into a reveal, when the cards turn over
    revealSelfMs  = 2800,
    revealSeatMs  = 2800,
    collectMs     = 1700,   -- the dealer takes one seat's cards and chips
    putDownMs     = 1500,
}

-- ============================================
-- Tables
-- ============================================
-- coords is the table's origin (on the floor), heading which way it faces.
-- spawn = true: we place the table. false: it's already in the map (an MLO's own table), and we find it there.
-- model: 'vw_prop_casino_3cardpoker_01' or 'vw_prop_casino_3cardpoker_01b'. Both are GTA's own three card poker
--        table, felt printed for it (Ante, Play, Pair Plus).
-- texture: the felt, 0 green, 1 red, 2 blue, 3 purple. Leave it out to keep the map's.
-- min / max: bet limits. step: how much the arrows change your bet (default the min).
--
-- These are k4mb1-casino's own tables, read out of its map files (stream/casino2/k4mb1_casino2.ytyp; the
-- penthouse's from vw_vwdlc_int_02.ytyp). The penthouse one is in k4mb1's lounge entity set 04 (Three Card Poker),
-- which k4mb1's client2.lua leaves off (set 01, Blackjack, is on): turn 04 on there for it to appear.
Config.Tables = {
    -- The main floor
    { label = 'Three Card Poker',            coords = vec3(994.685, 66.706, 79.981), heading = 238.0, model = 'vw_prop_casino_3cardpoker_01',  spawn = false, min = 50,   max = 2500 },
    { label = 'Three Card Poker',            coords = vec3(991.848, 62.165, 79.981), heading = 238.0, model = 'vw_prop_casino_3cardpoker_01b', spawn = false, min = 50,   max = 2500 },
    { label = 'Three Card Poker',            coords = vec3(988.997, 57.600, 79.981), heading = 238.0, model = 'vw_prop_casino_3cardpoker_01',  spawn = false, min = 50,   max = 2500 },
    { label = 'Three Card Poker',            coords = vec3(985.126, 77.554, 79.991), heading = 328.0, model = 'vw_prop_casino_3cardpoker_01b', spawn = false, min = 50,   max = 2500 },
    { label = 'Three Card Poker',            coords = vec3(988.979, 75.723, 79.991), heading = 328.0, model = 'vw_prop_casino_3cardpoker_01b', spawn = false, min = 50,   max = 2500 },
    { label = 'Three Card Poker',            coords = vec3(992.494, 72.990, 79.991), heading = 328.0, model = 'vw_prop_casino_3cardpoker_01b', spawn = false, min = 50,   max = 2500 },
    -- The high limit room, beside its blackjack table
    { label = 'High Limit Three Card Poker', coords = vec3(937.543, 35.661, 79.986), heading = 148.0, model = 'vw_prop_casino_3cardpoker_01b', spawn = false, min = 1000, max = 25000, step = 500 },
    -- The penthouse lounge (entity set k4mb1_apart_lounge_room_04, see above)
    { label = 'Penthouse Three Card Poker',  coords = vec3(967.314, 32.215, 115.172), heading = 238.0, model = 'vw_prop_casino_3cardpoker_01b', spawn = false, min = 1000, max = 25000, step = 500 },
}

-- The dealer's animations number the seats their own way (deck_deal_p01-p04): [our seat] = the animation's seat.
-- Our seats are the table's chairs (Chair_Base_01-04, "Seat N" in /tcpedit). If the dealer turns to the wrong
-- chair, change this: { 1, 2, 3, 4 } is the same numbering, { 4, 3, 2, 1 } mirrored (blackjack's tables are mirrored).
Config.AnimSeats = { 4, 3, 2, 1 }

-- The dealers: each restart, every table gets one of these at random, with its own face and hair (every player
-- sees the same one). female = true uses the female dealer moves where the game has them.
Config.Dealers = {
    { model = 's_m_y_casino_01', voice = 'S_M_Y_CASINO_01_WHITE_01' },
    { model = 's_m_y_casino_01', voice = 'S_M_Y_CASINO_01_WHITE_02' },
    { model = 's_m_y_casino_01', voice = 'S_M_Y_CASINO_01_ASIAN_01' },
    { model = 's_m_y_casino_01', voice = 'S_M_Y_CASINO_01_ASIAN_02' },
    { model = 's_m_y_casino_01', voice = 'S_M_Y_CASINO_01_LATINO_01' },
    { model = 's_f_y_casino_01', voice = 'S_F_Y_CASINO_01_ASIAN_01',  female = true },
    { model = 's_f_y_casino_01', voice = 'S_F_Y_CASINO_01_LATINA_01', female = true },
    { model = 's_f_y_casino_01', voice = 'S_F_Y_CASINO_01_WHITE_01',  female = true },
}

-- ============================================
-- Where things go on the felt
-- ============================================
-- Only until /tcpedit has set them: the editor's layout (layout.json) wins over all of this. Worked out from the
-- table's chair bones, in metres in the table's own frame.
Config.Layout = {
    centre       = vec2(0.0, 0.0),  -- the middle of the felt, from the table's origin
    surface      = 0.95,            -- the felt's height above the origin
    cardAt       = 0.38,            -- a seat's cards: this far from the middle towards its chair (0 middle, 1 chair)
    cardSpread   = 0.07,            -- between a hand's three cards
    -- A seat's three betting spots: { towards the chair (0-1), sideways (metres) }.
    chips = {
        ante = { 0.52, -0.06 },
        play = { 0.52,  0.06 },
        plus = { 0.64,  0.0 },
    },
    dealerStand  = 0.82,            -- the dealer stands this far behind the middle
    dealerLift   = 1.0,             -- the dealer's hips above the floor (a ped stands on its hips' height)
    dealerCardAt = 0.18,            -- the dealer's cards: this far from the middle towards the dealer
    chipHeight   = 0.0072,          -- one chip's thickness, for stacking
    seatTurn     = 0.0,             -- degrees: turn a seated player if the chairs face off
    -- Cards ride in the dealer's hand as he deals, and go down to their spots when it reaches the felt.
    dealerHand   = 28422,           -- the hand the dealer deals with (28422 right, 60309 left)
    playerHand   = 28422,           -- the hand a player puts chips down with
    grabPhase    = 0.12,            -- how far into a deal the cards are in the dealer's hand (0-1)
    dropBand     = 0.10,            -- a hand this close above the felt is putting something down

    -- The deck: lies on the felt, and is in the dealer's hand from deck_pick_up to deck_put_down.
    -- Both are set in /tcpedit ("Dealer: the deck on the table", "Dealer: the deck in his hand").
    deckModel     = 'vw_prop_casino_cards_01',
    deckAt        = 0.30,           -- on the felt: this far from the middle towards the dealer
    deckSide      = 0.28,           --              and this far to one side
    deckHand      = 60309,          -- the hand holding it (60309 left, 28422 right)
    deckHold      = { 0.0, 0.0, 0.0, 0.0, 0.0, 0.0 },   -- in the hand: x, y, z, then turn x, y, z (degrees)
    deckPickPhase = 0.40,           -- how far into deck_pick_up the hand has it (0-1)
    deckPutPhase  = 0.60,           -- how far into deck_put_down it's let go
}

-- Chips on the felt for a bet: the biggest that fit, stacked. Value -> model.
Config.Chips = {
    { 10000, 'vw_prop_chip_10kdollar_x1' },
    { 5000,  'vw_prop_chip_5kdollar_x1' },
    { 1000,  'vw_prop_chip_1kdollar_x1' },
    { 500,   'vw_prop_chip_500dollar_x1' },
    { 100,   'vw_prop_chip_100dollar_x1' },
    { 50,    'vw_prop_chip_50dollar_x1' },
    { 10,    'vw_prop_chip_10dollar_x1' },
}

-- ============================================
-- At the table
-- ============================================
-- The camera over your shoulder while seated (C turns it on and off; V is GTA's views, first person among them).
Config.Camera = {
    enabled = true,
    back    = 0.55,  -- behind the chair
    up      = 1.45,  -- above the floor
    fov     = 55.0,
}

-- Keys: GTA control ids, keyboard and pad. Shown on screen with whip's key hints.
Config.Keys = {
    up     = { key = 172, pad = 188, text = 'Up',        button = 'dpad_up' },
    down   = { key = 173, pad = 187, text = 'Down',      button = 'dpad_down' },
    min    = { key = 174, pad = 189, text = 'Left',      button = 'dpad_left' },
    max    = { key = 175, pad = 190, text = 'Right',     button = 'dpad_right' },
    accept = { key = 191, pad = 201, text = 'Enter',     button = 'a' },     -- Ante, Pair Plus, Play
    fold   = { key = 22,  pad = 203, text = 'Space',     button = 'x' },     -- Fold
    camera = { key = 26,  pad = 217, text = 'C',         button = 'view' },
    -- 194 is Backspace alone (177 is Backspace, right mouse and Esc all at once).
    leave  = { key = 194, pad = 202, text = 'Backspace', button = 'b' },     -- take your bets back, or get up
}

-- How far away a table and its game are drawn, and news of it sent.
Config.DrawRange = 45.0
Config.SyncRange = 60.0

-- Getting up: more than this far from your chair (a shove, a teleport) and you've left.
Config.LeaveDistance = 3.5
