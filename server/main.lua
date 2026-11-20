-- ============================================
-- whip_threecard — server: tables, seats, money, and what each game is told
-- ============================================
--
-- The server deals and decides everything. Games near a table are told what to show (fx), and each seated player
-- what's theirs (hud). A player's cards go to that player only, and the dealer's to no one, until they're turned
-- over: every other game is told only that a card is there, face down.

Tables = {}   -- [id] = T: { id, def, pos, seats = { [1..4] = P }, phase, dealer = { cards, shown }, inRound, running, deadline }
BySrc  = {}   -- [source] = P: { src, charId, name, table, seat, ante, plus, play, receipts, cards, shown, decision, ask, gone, dropped }

local SEATS = 4
local HIDDEN = { false, false, false }

local function now() return GetGameTimer() end

for id, def in ipairs(Config.Tables) do
    Tables[id] = {
        id = id, def = def, pos = vector3(def.coords.x, def.coords.y, def.coords.z),
        step = def.step or def.min,
        seats = {}, phase = 'idle',
        -- This table's dealer until the next restart: which of Config.Dealers, and a seed for their face and hair.
        look = { pick = math.random(#Config.Dealers), seed = math.random(1, 2147483646) },
        dealer = { cards = {}, shown = false },
        running = false, deadline = 0, span = 0,
    }
end

-- ============================================
-- Telling games
-- ============================================

local function near(T) return Whip.core:GetPlayersInRange(T.pos, Config.SyncRange) or {} end

--- News of a table, to the games near it (they draw it): seat, chips, deal, reveal, clear, dealer, speech.
function Fx(T, kind, data)
    for _, s in ipairs(near(T)) do
        TriggerClientEvent('whip_threecard:fx', s, T.id, kind, data)
    end
end

--- A seat's cards: its own player sees them, the rest see backs until they're turned over (P.shown).
function FxCards(T, P, kind, extra)
    for _, s in ipairs(near(T)) do
        local d = { seat = P.seat }
        for k, v in pairs(extra or {}) do d[k] = v end
        d.cards = (P.shown or tonumber(s) == P.src) and P.cards or HIDDEN
        TriggerClientEvent('whip_threecard:fx', s, T.id, kind, d)
    end
end

function Speech(T, line) Fx(T, 'speech', { line = line }) end

--- loop: keep playing it (the dealer holding the deck while the players decide).
function DealerAnim(T, anim, dict, loop) Fx(T, 'dealer', { anim = anim, dict = dict, loop = loop }) end

--- One seated player's panel: their bets, their cards and hand, the dealer's once shown, what they may do.
function Hud(P)
    if P.gone or P.dropped then return end
    local T = Tables[P.table]
    local d = {
        table = T.id, seat = P.seat, label = T.def.label or 'Three Card Poker',
        min = T.def.min, max = T.def.max, step = T.step,
        phase = T.phase, ante = P.ante, plus = P.plus, play = P.play,
        folded = P.decision == 'fold', result = P.result, net = P.net,
    }
    if P.cards then
        d.cards = P.cards
        d.hand = Cards.evaluate(P.cards).name
    end
    if T.dealer.shown and #T.dealer.cards == 3 then
        local e = Cards.evaluate(T.dealer.cards)
        d.dealer = { cards = T.dealer.cards, hand = e.name, qualifies = Cards.qualifies(e) }
    end
    if P.ask then
        d.ask = P.ask.kind
        d.endsIn = math.max(0, P.ask.deadline - now())
        d.span = P.ask.span
        d.cost = P.ask.cost
    elseif T.phase == 'betting' then
        d.endsIn = math.max(0, T.deadline - now())
        d.span = T.span
    end
    TriggerClientEvent('whip_threecard:hud', P.src, d)
end

function HudAll(T)
    for s = 1, SEATS do
        local P = T.seats[s]
        if P then Hud(P) end
    end
end

-- What a game coming near needs to draw the table as it is now. Cards it may not see are false.
local function snapshot(T, src)
    local seats, hands, seen = {}, {}, {}
    for s = 1, SEATS do
        local P = T.seats[s]
        if P then seats[#seats + 1] = { seat = s, src = P.src } end
    end
    local function add(P)
        if seen[P] then return end
        seen[P] = true
        local e = { seat = P.seat, ante = P.ante, plus = P.plus, play = P.play }
        if P.cards and not P.cleared then
            e.cards = (P.shown or P.src == src) and P.cards or HIDDEN
        end
        hands[#hands + 1] = e
    end
    for _, P in pairs(T.inRound or {}) do if not P.cleared then add(P) end end
    for s = 1, SEATS do
        local P = T.seats[s]
        if P and P.ante then add(P) end
    end
    local dealer
    if #T.dealer.cards > 0 and not T.dealer.cleared then
        dealer = T.dealer.shown and T.dealer.cards or HIDDEN
    end
    return { seats = seats, hands = hands, dealer = dealer, look = T.look, deckHeld = T.deckHeld == true }
end

-- ============================================
-- Money
-- ============================================

local function moneyOpts(reason, P)
    local o = { reason = reason }
    if Config.Money.currency then o.currency = Config.Money.currency end
    if not (P and P.dropped) then o.method = Config.Money.method end
    return o
end

--- Takes a stake. A receipt, or false and a sentence for the player.
function Charge(P, amount, reason)
    if P.dropped then return false, 'gone' end
    return Whip.core:ChargePlayer(P.src, amount, moneyOpts(reason, P))
end

--- Pays a player, at the table or not (a player who has gone home is paid to their character).
function Pay(P, amount, reason)
    if amount <= 0 then return true end
    local who = P.dropped and { charId = P.charId } or P.src
    local ok, why = Whip.core:PayPlayer(who, amount, moneyOpts(reason, P))
    if not ok then
        print(('[whip_threecard] CRITICAL: could not pay %s (char %s) %d: %s'):format(P.name, tostring(P.charId), amount, tostring(why)))
    end
    return ok
end

function Refund(receipt)
    if not receipt then return end
    local ok, why = Whip.core:RefundPlayer(receipt)
    if not ok then print(('[whip_threecard] CRITICAL: refund failed: %s'):format(tostring(why))) end
end

--- Every stake of P's not yet settled, back to them.
function RefundAll(P)
    if P.settled then return end
    P.settled = true
    for _, r in pairs(P.receipts or {}) do Refund(r) end
    P.receipts = {}
end

function Notify(P, msg, kind)
    if P.gone or P.dropped then return end
    Whip.core:NotifyPlayer(P.src, msg, kind or 'inform')
end

-- ============================================
-- Sitting down and getting up
-- ============================================

local function greet(T, P)
    local model = GetEntityModel(GetPlayerPed(P.src))
    local lines = { 'MINIGAME_DEALER_GREET' }
    if model == `mp_f_freemode_01` then lines[2] = 'MINIGAME_DEALER_GREET_FEMALE'
    elseif model == `mp_m_freemode_01` then lines[2] = 'MINIGAME_DEALER_GREET_MALE' end
    if T.recent and T.recent[P.charId] and os.time() - T.recent[P.charId] < 900 then
        Speech(T, 'MINIGAME_DEALER_REJOIN_TABLE')
    else
        Speech(T, lines[math.random(#lines)])
    end
end

local function sit(src, player, tableId, seat)
    local T = Tables[tableId]
    if not T then return false, 'No such table' end
    if BySrc[src] then return false, 'You are already at a table' end
    local at = GetEntityCoords(GetPlayerPed(src))
    if #(at - T.pos) > 3.5 then return false, 'Too far from the table' end

    -- The chair they chose. One whose player left mid-hand stays theirs until the round ends: their cards are on it.
    if T.seats[seat] then return false, 'Someone is sitting there' end
    if T.inRound and T.inRound[seat] then return false, 'That seat is still in the hand, wait for it to finish' end

    local P = {
        src = src, charId = player.charId, name = player.fullName or GetPlayerName(src),
        table = tableId, seat = seat, receipts = {},
    }
    T.seats[seat], BySrc[src] = P, P
    Fx(T, 'seat', { seat = seat, src = src })
    DealerAnim(T, 'acknowledge_p0' .. Cards.animSeat(seat), 'shared')
    greet(T, P)
    CreateThread(function() Wait(250) Hud(P) end)
    return { seat = seat }
end

local function inRound(T, P) return T.inRound ~= nil and T.inRound[P.seat] == P end

--- Off the table. Bets not yet dealt go back; a hand already dealt is folded if it hasn't been played, and settled
--- with the rest (its Pair Plus still counts, and a win is paid to their character).
function Leave(P, why)
    local T = Tables[P.table]
    if not T or T.seats[P.seat] ~= P then return end
    T.seats[P.seat] = nil
    BySrc[P.src] = nil

    if inRound(T, P) then
        P.gone = true          -- the round answers for them (fold) and pays them
    elseif P.ante or P.plus then
        RefundAll(P)
        P.ante, P.plus, P.settled = nil, nil, nil
        Fx(T, 'chips', { seat = P.seat, spot = 'ante', amount = 0 })
        Fx(T, 'chips', { seat = P.seat, spot = 'plus', amount = 0 })
    end

    T.recent = T.recent or {}
    T.recent[P.charId] = os.time()
    Fx(T, 'seat', { seat = P.seat, src = false })
    if P.result == 'won' then Speech(T, 'MINIGAME_DEALER_LEAVE_GOOD_GAME')
    elseif P.result == 'lost' then Speech(T, 'MINIGAME_DEALER_LEAVE_BAD_GAME')
    else Speech(T, 'MINIGAME_DEALER_LEAVE_NEUTRAL_GAME') end
    if not P.dropped and why ~= 'asked' then TriggerClientEvent('whip_threecard:stand', P.src) end
end

-- ============================================
-- Betting and deciding
-- ============================================

local function bet(src, spot, amount)
    local P = BySrc[src]
    if not P then return false, 'You are not at a table' end
    local T = Tables[P.table]
    if (T.phase ~= 'idle' and T.phase ~= 'betting') or inRound(T, P) then return false, 'Wait for the next hand' end
    local max = T.def.max
    if spot == 'ante' then
        if P.ante then return false, 'Your Ante is down' end
    else
        if not P.ante then return false, 'Put down an Ante first' end
        if P.plus then return false, 'Your Pair Plus is down' end
        max = math.min(max, Config.Rules.pairPlusMax or max)
    end
    if amount < T.def.min then return false, ('The minimum here is %s'):format(Cards.money(T.def.min)) end
    if amount > max then return false, ('The most here is %s'):format(Cards.money(max)) end

    local receipt, why = Charge(P, amount, spot == 'ante' and 'Three Card Poker ante' or 'Three Card Poker pair plus')
    if not receipt then return false, why end
    -- It may have closed while the money moved, or they got up.
    if (T.phase ~= 'idle' and T.phase ~= 'betting') or T.seats[P.seat] ~= P then
        Refund(receipt)
        return false, 'Too late, the cards are out'
    end
    P[spot], P.receipts[spot] = amount, receipt
    P.result, P.net, P.settled = nil, nil, nil
    local anim = spot == 'ante' and 'bet_ante' or 'bet_plus'
    TriggerClientEvent('whip_threecard:anim', src, anim)
    -- With the animation: each game puts the chips down as the player's hand does.
    Fx(T, 'chips', { seat = P.seat, spot = spot, amount = amount, anim = anim })
    Round.start(T)
    HudAll(T)
    return true
end

local function unbet(src)
    local P = BySrc[src]
    if not P or not P.ante then return end
    local T = Tables[P.table]
    if (T.phase ~= 'idle' and T.phase ~= 'betting') or inRound(T, P) then return end
    RefundAll(P)
    P.ante, P.plus, P.settled = nil, nil, nil
    Fx(T, 'chips', { seat = P.seat, spot = 'ante', amount = 0 })
    Fx(T, 'chips', { seat = P.seat, spot = 'plus', amount = 0 })
    HudAll(T)
end

local function act(src, choice)
    local P = BySrc[src]
    local a = P and P.ask
    if not a or a.answer or not a.allowed[choice] then return end
    a.answer = choice
end

Whip.register(function()
    Whip.core:SecureCallback('whip_threecard:sit', {
        rateLimit = 1000, params = { { 'table', 'id', 1, #Config.Tables }, { 'seat', 'id', 1, SEATS } },
    }, sit)

    Whip.core:SecureCallback('whip_threecard:snapshot', {
        rateLimit = 500, burst = 6, params = { { 'table', 'id', 1, #Config.Tables } },
    }, function(source, _, tableId)
        return snapshot(Tables[tableId], source)
    end)

    Whip.core:SecureEvent('whip_threecard:bet', {
        rateLimit = 400, params = { { 'spot', 'enum', { 'ante', 'plus' } }, { 'amount', 'amount', 100000000 } },
    }, function(source, _, spot, amount)
        local ok, why = bet(source, spot, amount)
        if not ok and why then Whip.core:NotifyPlayer(source, why, 'error') end
    end)

    Whip.core:SecureEvent('whip_threecard:unbet', { rateLimit = 400 }, function(source) unbet(source) end)

    Whip.core:SecureEvent('whip_threecard:act', {
        rateLimit = 250, burst = 3, params = { { 'choice', 'enum', { 'play', 'fold' } } },
    }, function(source, _, choice) act(source, choice) end)

    Whip.core:SecureEvent('whip_threecard:leave', { rateLimit = 500, whileDead = true }, function(source)
        local P = BySrc[source]
        if P then Leave(P, 'asked') end
    end)

    -- The chips are whip_blackjack's item (and its cashier sells them). Said once, if they aren't there.
    SetTimeout(15000, function()
        local cur = Config.Money.currency
        if cur and not Whip.core:GetItemDef(cur) then
            print(('[whip_threecard] the bets are in "%s", but no such item exists: start whip_blackjack (it has the casino chips and the cashier), or set Config.Money.currency = nil to bet cash.'):format(cur))
        end
    end)
end)

AddEventHandler('playerDropped', function()
    local P = BySrc[source]
    if P then
        P.dropped = true
        Leave(P, 'dropped')
    end
end)

-- Shoved off, teleported, or down: they've left.
CreateThread(function()
    while true do
        Wait(1000)
        for src, P in pairs(BySrc) do
            local T = Tables[P.table]
            local ped = GetPlayerPed(src)
            if ped == 0 or #(GetEntityCoords(ped) - T.pos) > Config.LeaveDistance + 2.0
                or Whip.core:IsPlayerDead(src) == true then
                Leave(P, 'away')
            end
        end
    end
end)

-- Stopping mid-hand: every stake still on the felt goes back. The players did nothing wrong.
AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for _, T in pairs(Tables) do
        for s = 1, SEATS do if T.seats[s] then RefundAll(T.seats[s]) end end
        for _, P in pairs(T.inRound or {}) do RefundAll(P) end
    end
end)

-- ============================================
-- The layout (/tcpedit): where cards, chips and the dealer go, per table model
-- ============================================
-- Kept in layout.json in this resource: { [model] = { chairs, cards, chips, dealer } }, in each table's own frame.
--   cards: ['seat:card'] (seat 0 the dealer's, cards 1-3)   chips: ['seat:ante|play|plus']   each { x, y, z, turn }

local LAYOUT_FILE = 'layout.json'
local Layouts = {}

do
    local raw = LoadResourceFile(GetCurrentResourceName(), LAYOUT_FILE)
    if raw and raw ~= '' then
        local ok, v = pcall(json.decode, raw)
        if ok and type(v) == 'table' then Layouts = v
        else print('[whip_threecard] layout.json could not be read: ' .. tostring(v)) end
    end
end

-- Only numbers in the shapes we use, so a bad send can't write rubbish into the file: x, y, z within 50 m of the
-- table, and a turn in degrees.
local dropped = 0
local function cleanSpot(v, n)
    if type(v) ~= 'table' then dropped = dropped + 1 return nil end
    local out = {}
    for i = 1, n do
        local x = tonumber(v[i])
        local limit = (i >= 4) and 720 or 50   -- 4 on: turns
        if not x or x ~= x or math.abs(x) > limit then dropped = dropped + 1 return nil end
        out[i] = math.floor(x * 10000 + 0.5) / 10000
    end
    return out
end

local function cleanLayout(d)
    if type(d) ~= 'table' then return nil end
    local out = { chairs = {}, cards = {}, chips = {} }
    for k, v in pairs(type(d.chairs) == 'table' and d.chairs or {}) do
        local s, c = tonumber(k), tonumber(v)
        if s and c and s >= 1 and s <= SEATS and c >= 1 and c <= SEATS then out.chairs[tostring(s)] = math.floor(c) end
    end
    for k, v in pairs(type(d.cards) == 'table' and d.cards or {}) do
        if type(k) == 'string' and k:match('^[0-4]:[1-3]$') then out.cards[k] = cleanSpot(v, 4) end
    end
    for k, v in pairs(type(d.chips) == 'table' and d.chips or {}) do
        if type(k) == 'string' and (k:match('^[1-4]:ante$') or k:match('^[1-4]:play$') or k:match('^[1-4]:plus$')) then
            out.chips[k] = cleanSpot(v, 4)
        end
    end
    out.dealer = cleanSpot(d.dealer, 4)
    if d.deck ~= nil then out.deck = cleanSpot(d.deck, 4) end
    if d.hold ~= nil then out.hold = cleanSpot(d.hold, 6) end
    return out
end

Whip.register(function()
    Whip.core:SecureCallback('whip_threecard:layouts', { rateLimit = 2000, requirePlayer = false }, function()
        return Layouts
    end)

    Whip.core:SecureEvent('whip_threecard:saveLayout', {
        rateLimit = 2000, params = { { 'model', 'key', 64 }, { 'data', 'any' } },
    }, function(source, _, model, data)
        if not IsPlayerAceAllowed(source, 'whip.devtools') then return false, 'Dev only' end
        local known = false
        for _, def in ipairs(Config.Tables) do if def.model == model then known = true break end end
        if not known then return false, 'No table uses that model' end
        dropped = 0
        local clean = cleanLayout(data)
        if not clean then return false, 'Bad layout' end
        if dropped > 0 then
            -- Never quietly: say what didn't go in.
            Whip.core:NotifyPlayer(source, ('%d spot(s) were not valid and were not saved'):format(dropped), 'error')
        end
        Layouts[model] = clean
        SaveResourceFile(GetCurrentResourceName(), LAYOUT_FILE, json.encode(Layouts, { indent = true }), -1)
        TriggerClientEvent('whip_threecard:layout', -1, model, clean)
        print(('[whip_threecard] %s saved the layout for %s to %s'):format(GetPlayerName(source), model, LAYOUT_FILE))
        Whip.core:NotifyPlayer(source, 'Layout saved for every ' .. model, 'success')
    end)
end)

local function suggestions(src)
    if not IsPlayerAceAllowed(src, 'whip.devtools') then return end
    TriggerClientEvent('chat:addSuggestions', src, {
        { name = '/tcpedit', help = 'Three card poker: move the cards, chips and dealer at the table you stand at' },
    })
end
AddEventHandler('whip_core:player:loaded', function(e) if type(e) == 'table' and e.source then suggestions(e.source) end end)
CreateThread(function() for _, s in ipairs(GetPlayers()) do suggestions(tonumber(s)) end end)

Whip.sayStarted()
