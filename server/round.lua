-- ============================================
-- whip_threecard — server: one round, start to finish
-- ============================================
--
-- Antes (and Pair Plus) -> the deal, three each -> every player plays or folds, all at once -> the dealer turns
-- theirs over and qualifies or not -> each seat turned over and paid, in seat order -> the felt cleared.
-- One thread per table while a round runs. Every wait for a player has a deadline: one who doesn't answer folds, and
-- one who leaves is folded (if they hadn't played) and settled like everyone else.

Round = {}

local SEATS = 4
local R, TM = Config.Rules, Config.Timing

local function now() return GetGameTimer() end

local function seatsInOrder(T)
    local out = {}
    for s = 1, SEATS do
        local P = T.inRound[s]
        if P then out[#out + 1] = P end
    end
    return out
end

--- Waits for one player's choice from `allowed` (a set), up to `seconds`. Gone or out of time: `default`.
local function ask(P, kind, allowed, seconds, default, cost)
    if P.gone then return default end
    -- Held here as well as on P: Leave can take P.ask away while this waits.
    local a = { kind = kind, allowed = allowed, deadline = now() + seconds * 1000, span = seconds * 1000, cost = cost }
    P.ask = a
    Hud(P)
    while not a.answer and not P.gone and now() < a.deadline do Wait(100) end
    if P.ask == a then P.ask = nil end
    Hud(P)
    return (not P.gone and a.answer) or default
end

local function pAnim(P, anim, dictKey)
    if not P.gone then TriggerClientEvent('whip_threecard:anim', P.src, anim, dictKey) end
end

local function react(P, how)
    pAnim(P, 'reaction_' .. how .. '_var_0' .. math.random(1, 4), 'shared')
end

-- ============================================
-- Settling a seat
-- ============================================

local function settle(T, P, dealerHand, qualifies)
    if P.settled then return end
    P.settled = true
    local hand = Cards.evaluate(P.cards)
    local staked = (P.ante or 0) + (P.plus or 0) + (P.play or 0)
    local back = 0
    local lines = {}

    if P.decision == 'play' and P.play then
        if not qualifies then
            back = back + P.ante * 2 + P.play          -- Ante pays 1:1, Play comes back
            lines[#lines + 1] = 'the dealer didn\'t qualify'
        else
            local c = Cards.compare(hand, dealerHand)
            if c > 0 then
                back = back + (P.ante + P.play) * 2    -- both at 1:1
                lines[#lines + 1] = 'you beat the dealer'
            elseif c == 0 then
                back = back + P.ante + P.play
                lines[#lines + 1] = 'a tie with the dealer'
            else
                lines[#lines + 1] = 'the dealer wins'
            end
        end
        local bonus = R.anteBonus[hand.id] or 0
        if bonus > 0 then
            back = back + P.ante * bonus
            lines[#lines + 1] = ('Ante Bonus %d:1'):format(bonus)
        end
    end
    if P.plus then
        local m = R.pairPlus[hand.id] or 0
        if m > 0 then
            back = back + P.plus * (m + 1)
            lines[#lines + 1] = ('Pair Plus %d:1'):format(m)
        end
    end

    if back > 0 then Pay(P, back, 'Three Card Poker winnings') end
    P.receipts = {}
    P.net = back - staked
    local why = #lines > 0 and (' (' .. table.concat(lines, ', ') .. ')') or ''
    if P.net > 0 then
        P.result = 'won'
        Notify(P, ('%s: you won %s%s'):format(hand.name, Cards.money(P.net), why), 'success')
        react(P, P.net >= staked * 3 and 'great' or 'good')
    elseif P.net < 0 then
        P.result = 'lost'
        Notify(P, ('%s: you lost %s%s'):format(hand.name, Cards.money(-P.net), why), 'error')
        react(P, -P.net > 1000 and 'terrible' or 'bad')
    else
        P.result = 'push'
        Notify(P, ('%s: your bets are back%s'):format(hand.name, why), 'inform')
        react(P, 'impartial')
    end
    Hud(P)
end

-- ============================================
-- The round
-- ============================================

local function bettingWindow(T)
    T.phase = 'betting'
    T.deadline = now() + TM.betSeconds * 1000
    T.span = TM.betSeconds * 1000
    Speech(T, 'MINIGAME_DEALER_PLACE_CHIPS')
    HudAll(T)
    local shrunk = false
    while now() < T.deadline do
        Wait(200)
        local seated, antes = 0, 0
        for s = 1, SEATS do
            local P = T.seats[s]
            if P then
                seated = seated + 1
                if P.ante then antes = antes + 1 end
            end
        end
        if antes == 0 then return false end   -- everyone took their bets back, or left
        if antes == seated and not shrunk and T.deadline - now() > TM.allInSeconds * 1000 then
            shrunk = true
            T.deadline = now() + TM.allInSeconds * 1000
            T.span = TM.allInSeconds * 1000
            HudAll(T)
        end
    end
    return true
end

local function play(T)
    if not bettingWindow(T) then return end

    -- Bets closed: who's in.
    T.phase = 'dealing'
    T.inRound = {}
    for s = 1, SEATS do
        local P = T.seats[s]
        if P and P.ante then
            P.cards, P.shown, P.decision, P.play, P.cleared = nil, false, nil, nil, nil
            P.settled, P.result, P.net = false, nil, nil
            T.inRound[s] = P
        end
    end
    local players = seatsInOrder(T)
    if #players == 0 then return end
    Speech(T, 'MINIGAME_DEALER_CLOSED_BETS')
    HudAll(T)

    -- A fresh deck every hand.
    local deck = Cards.deck()
    local function draw() return table.remove(deck) end

    DealerAnim(T, 'deck_pick_up', 'tcp')
    T.deckHeld = true    -- for a game arriving mid-hand
    Wait(TM.pickUpMs)
    DealerAnim(T, 'deck_shuffle', 'tcp')
    Wait(TM.shuffleMs)

    -- Three to each seat (only its player sees them), then three to the dealer (no one does).
    for _, P in ipairs(players) do
        P.cards = { draw(), draw(), draw() }
        local anim = 'deck_deal_p0' .. Cards.animSeat(P.seat)
        DealerAnim(T, anim, 'tcp')
        FxCards(T, P, 'deal', { anim = anim })
        Wait(TM.dealSeatMs)
        Hud(P)
    end
    T.dealer.cards = { draw(), draw(), draw() }
    DealerAnim(T, 'deck_deal_self', 'tcp')
    Fx(T, 'deal', { seat = 0, cards = { false, false, false }, anim = 'deck_deal_self' })
    Wait(TM.dealSelfMs)
    DealerAnim(T, 'deck_idle', 'tcp', true)

    -- Play or fold: everyone at once.
    T.phase = 'deciding'
    HudAll(T)
    local pending = #players
    for _, P in ipairs(players) do
        CreateThread(function()
            local choice = ask(P, 'decide', { play = true, fold = true }, TM.decideSeconds, 'fold', P.ante)
            if choice == 'play' then
                local receipt, why = Charge(P, P.ante, 'Three Card Poker play')
                if receipt and T.decided then
                    -- Too late (the round moved on while the money did): it goes back, and they fold.
                    Refund(receipt)
                    receipt = nil
                end
                if receipt then
                    P.play, P.receipts.play = P.ante, receipt
                    pAnim(P, 'cards_play')
                    Fx(T, 'chips', { seat = P.seat, spot = 'play', amount = P.play, anim = 'cards_play' })
                else
                    Notify(P, (why and why ~= 'gone') and (why .. ': folded') or 'You couldn\'t cover the Play bet: folded', 'error')
                    choice = 'fold'
                end
            end
            if choice == 'fold' then pAnim(P, 'cards_fold') end
            if not T.decided then P.decision = choice end
            Hud(P)
            pending = pending - 1
        end)
    end
    local deadline = now() + (TM.decideSeconds + 5) * 1000
    while pending > 0 and now() < deadline do Wait(100) end
    T.decided = true
    for _, P in ipairs(players) do if not P.decision then P.decision = 'fold' end end
    Wait(TM.playerMoveMs)

    -- The dealer's hand.
    T.phase = 'reveal'
    HudAll(T)
    DealerAnim(T, 'reveal_self', 'tcp')
    Wait(TM.flipMs)
    T.dealer.shown = true
    Fx(T, 'reveal', { seat = 0, cards = T.dealer.cards })
    HudAll(T)
    Wait(math.max(0, TM.revealSelfMs - TM.flipMs))
    local dealerHand = Cards.evaluate(T.dealer.cards)
    local qualifies = Cards.qualifies(dealerHand)
    if not qualifies then
        DealerAnim(T, 'reaction_impartial_var_0' .. math.random(1, 3), 'shared')
        Wait(2000)
    end

    -- Each seat turned over (played or folded: a folded hand's Pair Plus still counts) and paid.
    for _, P in ipairs(players) do
        local n = Cards.animSeat(P.seat)
        DealerAnim(T, ('reveal_%s_p0%d'):format(P.decision == 'play' and 'played' or 'folded', n), 'tcp')
        Wait(TM.flipMs)
        P.shown = true
        FxCards(T, P, 'reveal')
        settle(T, P, dealerHand, qualifies)
        Wait(math.max(0, TM.revealSeatMs - TM.flipMs))
    end

    -- Clear the felt, seat by seat, then the dealer's own.
    T.phase = 'payout'
    HudAll(T)
    Wait(1200)
    for _, P in ipairs(players) do
        DealerAnim(T, 'cards_collect_p0' .. Cards.animSeat(P.seat), 'tcp')
        Wait(700)
        P.cleared = true
        Fx(T, 'clear', { seat = P.seat })
        Wait(math.max(0, TM.collectMs - 700))
    end
    DealerAnim(T, 'cards_collect_self', 'tcp')
    Wait(700)
    T.dealer.cleared = true
    Fx(T, 'clear', { seat = 0 })
    Wait(math.max(0, TM.collectMs - 700))
    DealerAnim(T, 'deck_put_down', 'tcp')
    T.deckHeld = false
    Wait(TM.putDownMs)
end

--- Called on an Ante: starts this table's round if one isn't running.
function Round.start(T)
    if T.running then return end
    T.running = true
    CreateThread(function()
        local ok, err = pcall(play, T)
        if not ok then
            print(('[whip_threecard] table %d: the round failed: %s'):format(T.id, tostring(err)))
            -- Anything not settled goes back.
            for _, P in pairs(T.inRound or {}) do RefundAll(P) end
            Fx(T, 'clear', { all = true })
        end
        if T.deckHeld then
            T.deckHeld = false
            Fx(T, 'deck', { held = false })
        end
        -- Ready for the next.
        for _, P in pairs(T.inRound or {}) do
            P.ante, P.plus, P.play, P.receipts = nil, nil, nil, {}
            P.cards, P.shown, P.decision, P.ask, P.cleared, P.settled = nil, nil, nil, nil, nil, nil
        end
        T.inRound, T.decided = nil, nil
        T.dealer = { cards = {}, shown = false }
        T.phase = 'idle'
        T.running = false
        DealerAnim(T, 'idle')
        Speech(T, 'MINIGAME_DEALER_ANOTHER_GO')
        HudAll(T)
        -- Antes put down while the last round ran out: go again.
        for s = 1, SEATS do
            local P = T.seats[s]
            if P and P.ante then Round.start(T) break end
        end
    end)
end
