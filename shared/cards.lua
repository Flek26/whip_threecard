-- Cards, three-card hands and chips: one set of rules for the server (which deals and pays) and each game (which
-- shows them). A card is 'suit_rank', as the casino's card props are named: 'hrt_ace', 'spd_10', 'club_queen'.

Cards = {}

Cards.SUITS = { 'club', 'dia', 'hrt', 'spd' }
Cards.RANKS = { 'ace', '02', '03', '04', '05', '06', '07', '08', '09', '10', 'jack', 'queen', 'king' }

local VALUE = { jack = 11, queen = 12, king = 13, ace = 14 }
for i = 2, 10 do VALUE[('%02d'):format(i)] = i end

function Cards.rank(card) return type(card) == 'string' and card:match('_(%w+)$') or nil end
function Cards.suit(card) return type(card) == 'string' and card:match('^(%a+)_') or nil end

--- 2-14: an ace is high (A-2-3 is still a straight: see evaluate).
function Cards.value(card) return VALUE[Cards.rank(card) or ''] or 0 end

--- A fresh deck of 52, shuffled (Fisher-Yates). One deck a round: three card poker shuffles every hand.
function Cards.deck()
    local d = {}
    for _, s in ipairs(Cards.SUITS) do
        for _, r in ipairs(Cards.RANKS) do d[#d + 1] = s .. '_' .. r end
    end
    for i = #d, 2, -1 do
        local j = math.random(i)
        d[i], d[j] = d[j], d[i]
    end
    return d
end

-- Hand categories, best first. id is the key Config.Rules pays by.
local CATS = {
    [5] = { id = 'straightFlush', name = 'Straight flush' },
    [4] = { id = 'three',         name = 'Three of a kind' },
    [3] = { id = 'straight',      name = 'Straight' },
    [2] = { id = 'flush',         name = 'Flush' },
    [1] = { id = 'pair',          name = 'Pair' },
    [0] = { id = 'high',          name = 'High card' },
}

local WORD = { [11] = 'Jack', [12] = 'Queen', [13] = 'King', [14] = 'Ace' }
local function word(v) return WORD[v] or tostring(v) end
local function plural(v) return word(v) .. 's' end   -- 'Queens', '7s'

--- What three cards are: { cat (0-5), id, name, key = { ... } }. Two hands of one cat compare by key, in order.
function Cards.evaluate(cards)
    local v = {}
    for i = 1, 3 do v[i] = Cards.value(cards[i]) end
    table.sort(v, function(a, b) return a > b end)
    local s1, s2, s3 = Cards.suit(cards[1]), Cards.suit(cards[2]), Cards.suit(cards[3])
    local flush = s1 ~= nil and s1 == s2 and s2 == s3
    local straight, top = false, nil
    if v[1] == v[2] + 1 and v[2] == v[3] + 1 then
        straight, top = true, v[1]
    elseif v[1] == 14 and v[2] == 3 and v[3] == 2 then
        straight, top = true, 3            -- A-2-3: the ace is low, the lowest straight
    end

    local cat, key, name
    if straight and flush then
        cat, key, name = 5, { top }, ('Straight flush, %s high'):format(word(top))
    elseif v[1] == v[3] then
        cat, key, name = 4, { v[1] }, ('Three %s'):format(plural(v[1]))
    elseif straight then
        cat, key, name = 3, { top }, ('Straight, %s high'):format(word(top))
    elseif flush then
        cat, key, name = 2, { v[1], v[2], v[3] }, ('Flush, %s high'):format(word(v[1]))
    elseif v[1] == v[2] or v[2] == v[3] then
        local pair = v[2]                  -- sorted: the middle card is always one of the pair
        local kicker = (v[1] == v[2]) and v[3] or v[1]
        cat, key, name = 1, { pair, kicker }, ('Pair of %s'):format(plural(pair))
    else
        cat, key, name = 0, { v[1], v[2], v[3] }, ('%s high'):format(word(v[1]))
    end
    return { cat = cat, id = CATS[cat].id, name = name, key = key }
end

--- 1 when a beats b, -1 when b wins, 0 for a tie.
function Cards.compare(a, b)
    if a.cat ~= b.cat then return a.cat > b.cat and 1 or -1 end
    for i = 1, #a.key do
        if a.key[i] ~= b.key[i] then return a.key[i] > b.key[i] and 1 or -1 end
    end
    return 0
end

--- The dealer plays on with a Queen high or better (Config.Rules.qualifyHigh), or any pair or better.
function Cards.qualifies(e)
    return e.cat >= 1 or e.key[1] >= (Config.Rules.qualifyHigh or 12)
end

--- The number the dealer's animations give a seat ('deck_deal_p0N'): Config.AnimSeats.
function Cards.animSeat(seat)
    return (Config.AnimSeats and Config.AnimSeats[seat]) or seat
end

function Cards.model(card)
    return 'vw_prop_cas_card_' .. card
end

--- A bet as chips on the felt: { { model, count }, ... }, biggest first, at most `cap` chips in all.
function Cards.chips(amount, cap)
    cap = cap or 20
    local out, left, n = {}, math.floor(tonumber(amount) or 0), 0
    for _, c in ipairs(Config.Chips) do
        local value, model = c[1], c[2]
        local k = math.floor(left / value)
        if k > 0 then
            k = math.min(k, cap - n)
            if k <= 0 then break end
            out[#out + 1] = { model = model, count = k }
            left, n = left - k * value, n + k
        end
    end
    -- Less than the smallest chip still shows one.
    if #out == 0 and amount and amount > 0 then out[1] = { model = Config.Chips[#Config.Chips][2], count = 1 } end
    return out
end

--- '$1,250'
function Cards.money(n)
    local s = tostring(math.floor(tonumber(n) or 0))
    local out = s:reverse():gsub('(%d%d%d)', '%1,'):reverse()
    return '$' .. out:gsub('^,', '')
end
