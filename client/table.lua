-- ============================================
-- whip_threecard — client: the tables as this game draws them
-- ============================================
--
-- Every table near you is made here, in this game only: its dealer, the cards and the chips (the table itself is
-- the map's). The server sends what happens (fx) and this game shows it, so nothing is networked and every game
-- agrees. Coming near a table mid-hand, the game asks for it as it stands (snapshot).
--
-- Where things lie is the layout's (/tcpedit, layout.json), or Config.Layout until that's set. The animations say
-- when: cards ride in the dealer's hand as he deals and go down when it reaches the felt, chips go down as the
-- player's hand does.

local DICT = {
    tcp    = 'anim_casino_b@amb@casino@games@threecardpoker@dealer',
    shared = 'anim_casino_b@amb@casino@games@shared@dealer@',
}
-- A female dealer's own moves, where the game has them; else the male set (the same skeleton, it plays fine).
local FEMALE = {
    tcp    = 'anim_casino_b@amb@casino@games@threecardpoker@dealer_female',
    shared = 'anim_casino_b@amb@casino@games@shared@dealer@female',
}
local PLAY_DICT = 'anim_casino_b@amb@casino@games@threecardpoker@player'
local SEATS = 4
local SPOTS = { 'ante', 'play', 'plus' }
local LY = Config.Layout

Live = {}      -- [tableId] = L: { id, def, obj, owned, dealer, voice, dicts, frame, model, cards, chips, ready, queue }
Layouts = {}   -- [model] = the saved layout (/tcpedit)

-- ============================================
-- The table's frame: chairs, the middle, the dealer's side
-- ============================================

local function norm(x, y)
    local l = math.sqrt(x * x + y * y)
    if l < 0.0001 then return 0.0, 1.0, 0.0 end
    return x / l, y / l, l
end

local function buildFrame(L)
    local obj = L.obj
    local cx, cy = LY.centre.x, LY.centre.y
    local chairs, bones, mx, my = {}, {}, 0.0, 0.0
    for c = 1, SEATS do
        local idx = GetEntityBoneIndexByName(obj, ('Chair_Base_0%d'):format(c))
        local lp
        if idx ~= -1 then
            bones[c] = idx
            lp = GetOffsetFromEntityGivenWorldCoords(obj, GetWorldPositionOfEntityBone(obj, idx))
        else
            -- No bones (another model): four chairs on an arc in front of the table.
            local a = math.rad(-60 + (c - 1) * 40)
            lp = vector3(cx + math.sin(a) * 1.05, cy - math.cos(a) * 1.05, 0.0)
        end
        chairs[c] = lp
        mx, my = mx + (lp.x - cx), my + (lp.y - cy)
    end
    -- The dealer stands opposite the chairs.
    local dx, dy = norm(-mx, -my)
    L.frame = { chairs = chairs, bones = bones, cx = cx, cy = cy, dx = dx, dy = dy }
    if not next(bones) then
        print(('[whip_threecard] table %d: no chair bones on its model, seats are guessed'):format(L.id))
    end
end

local function lay(L) return Layouts[L.def.model] end

--- The chair a seat is (the layout's "which chair", else the same number).
local function chairOf(L, s)
    local t = lay(L)
    if t and t.chairs and t.chairs[tostring(s)] then return t.chairs[tostring(s)] end
    return s
end

local boneRotation = GetEntityBoneRotation or GetWorldRotationOfEntityBone

local function world(L, x, y, z) return GetOffsetFromEntityInWorldCoords(L.obj, x, y, z) end
local function toLocal(L, p) return GetOffsetFromEntityGivenWorldCoords(L.obj, p.x, p.y, p.z) end

-- A local direction as a world heading (GTA: 0 is north, turning left).
local function headingOf(L, dx, dy)
    return (GetEntityHeading(L.obj) + math.deg(math.atan(-dx, dy))) % 360.0
end

local function seatAxes(L, s)
    local f = L.frame
    local c = f.chairs[chairOf(L, s)]
    local ux, uy, r = norm(c.x - f.cx, c.y - f.cy)   -- out towards the chair
    return ux, uy, -uy, ux, r                         -- out, and sideways
end

--- Where card `i` (1-3) of seat `s` lies (s = 0: the dealer's), and its heading.
function CardSpot(L, s, i)
    local t = lay(L)
    local set = t and t.cards and t.cards[('%d:%d'):format(s, i)]
    if set then
        return world(L, set[1], set[2], set[3]), (GetEntityHeading(L.obj) + set[4]) % 360.0
    end
    local f = L.frame
    local z = LY.surface + 0.0007 * i
    if s == 0 then
        local tx, ty = -f.dy, f.dx
        local off = (i - 2) * LY.cardSpread
        return world(L, f.cx + f.dx * LY.dealerCardAt + tx * off, f.cy + f.dy * LY.dealerCardAt + ty * off, z),
            headingOf(L, -f.dx, -f.dy)
    end
    local ux, uy, tx, ty, r = seatAxes(L, s)
    local along, across = r * LY.cardAt, (i - 2) * LY.cardSpread
    return world(L, f.cx + ux * along + tx * across, f.cy + uy * along + ty * across, z), headingOf(L, -ux, -uy)
end

--- Where one of a seat's betting spots is ('ante', 'play', 'plus'), in the table's frame: x, y, the sideways
--- direction the stacks line up along, and the height.
function ChipSpot(L, s, spot)
    local t = lay(L)
    local set = t and t.chips and t.chips[('%d:%s'):format(s, spot)]
    if set then
        local a = math.rad(set[4] or 0.0)
        return set[1], set[2], math.cos(a), math.sin(a), set[3]
    end
    local f = L.frame
    local ux, uy, tx, ty, r = seatAxes(L, s)
    local c = LY.chips[spot] or LY.chips.ante
    return f.cx + ux * r * c[1] + tx * c[2], f.cy + uy * r * c[1] + ty * c[2], tx, ty, LY.surface
end

--- Where the dealer stands (his feet), his heading, and how high his hips are.
function DealerSpot(L)
    local t = lay(L)
    if t and t.dealer then
        local d = t.dealer
        return world(L, d[1], d[2], 0.0), (GetEntityHeading(L.obj) + d[4]) % 360.0, d[3]
    end
    local f = L.frame
    return world(L, f.cx + f.dx * LY.dealerStand, f.cy + f.dy * LY.dealerStand, 0.0), headingOf(L, -f.dx, -f.dy), LY.dealerLift
end

--- Where the deck lies on the felt, and its heading.
function DeckSpot(L)
    local t = lay(L)
    if t and t.deck then
        local d = t.deck
        return world(L, d[1], d[2], d[3]), (GetEntityHeading(L.obj) + d[4]) % 360.0
    end
    local f = L.frame
    local tx, ty = -f.dy, f.dx
    return world(L, f.cx + f.dx * LY.deckAt + tx * LY.deckSide, f.cy + f.dy * LY.deckAt + ty * LY.deckSide, LY.surface),
        headingOf(L, -f.dx, -f.dy)
end

--- How the deck sits in the dealer's hand: { x, y, z, turn x, y, z } from the hand bone.
function DeckHold(L)
    local t = lay(L)
    return (t and t.hold) or LY.deckHold
end

--- A seat's chair in the world, and the heading its sit animations are played at (the chair bone's own).
function ChairSpot(L, s)
    local c = chairOf(L, s)
    local p = L.frame.chairs[c]
    local at = world(L, p.x, p.y, p.z)
    local idx = L.frame.bones[c]
    local bone = (idx and boneRotation) and boneRotation(L.obj, idx) or nil
    local heading
    if bone then
        heading = bone.z
    else
        local d = DealerSpot(L)
        heading = GetHeadingFromVector_2d(d.x - at.x, d.y - at.y)
    end
    return at, (heading + LY.seatTurn) % 360.0
end

function FeltMiddle(L)
    local f = L.frame
    return world(L, f.cx + f.dx * LY.dealerCardAt * 0.5, f.cy + f.dy * LY.dealerCardAt * 0.5, LY.surface)
end

-- ============================================
-- Props
-- ============================================

local function model(name) return exports.whip_core:LoadModel(name) end

-- Made inside an MLO, a prop or ped isn't drawn until it's put in the table's room.
local function intoRoom(L, ent)
    local interior = GetInteriorFromEntity(L.obj)
    if interior ~= 0 then ForceRoomForEntity(ent, interior, GetRoomKeyFromEntity(L.obj)) end
end

local function flat(ent, heading, faceDown)
    SetEntityRotation(ent, faceDown and 180.0 or 0.0, 0.0, heading, 2, true)
end

local function makeProp(L, name, at, heading, faceDown)
    local hash = model(name)
    if not hash then return nil end
    local ent = CreateObject(hash, at.x, at.y, at.z, false, false, false)
    SetModelAsNoLongerNeeded(hash)
    intoRoom(L, ent)
    SetEntityCollision(ent, false, false)
    FreezeEntityPosition(ent, true)
    flat(ent, heading, faceDown)
    return ent
end

local function gone(ent)
    if ent and DoesEntityExist(ent) then DeleteEntity(ent) end
end

local function moveTo(ent, p, heading, faceDown)
    -- Face down, the card is turned over on its own middle: lifted a touch so it doesn't sink into the felt.
    SetEntityCoordsNoOffset(ent, p.x, p.y, p.z + (faceDown and 0.003 or 0.0), false, false, false)
    flat(ent, heading, faceDown)
end

-- ============================================
-- Watching a hand
-- ============================================

--- Follows a ped's hand through one animation, calling `onHand(pos, phase)` each frame, until the hand puts
--- something down on the felt (away from where it started). Returns that point, or nil when the animation never
--- played or nothing was put down. Never longer than the animation once through.
local function watchDrop(ped, dict, anim, bone, feltZ, onHand, minAway)
    minAway = minAway or 0.25
    local t0 = GetGameTimer()
    while not IsEntityPlayingAnim(ped, dict, anim, 3) do
        if GetGameTimer() - t0 > 1500 or not DoesEntityExist(ped) then return nil end
        Wait(0)
    end
    local untilAt = GetGameTimer() + math.max(600, math.floor(GetAnimDuration(dict, anim) * 1000))
    local start, low, lastPhase = nil, nil, -1.0
    while DoesEntityExist(ped) and IsEntityPlayingAnim(ped, dict, anim, 3) do
        local phase = GetEntityAnimCurrentTime(ped, dict, anim)
        if phase < lastPhase - 0.05 or GetGameTimer() > untilAt then break end
        lastPhase = phase
        local p = GetPedBoneCoords(ped, bone, 0.0, 0.0, 0.0)
        if onHand then onHand(p, phase) end
        if phase >= LY.grabPhase then
            start = start or p
            local away = #(vector2(p.x, p.y) - vector2(start.x, start.y)) > minAway
            if away and p.z <= feltZ + LY.dropBand then
                if not low or p.z < low.z then low = p
                elseif p.z > low.z + 0.015 then return low end
            elseif low then
                return low
            end
        end
        Wait(0)
    end
    return low
end

-- ============================================
-- The model: what's on the felt, and drawing it
-- ============================================
-- L.cards['s:i'] = { ent, at, heading, card }   (card false: face down)
-- L.chips['s:spot'] = { ents }

local function seatModel(L, s)
    local m = L.model.seats[s]
    if not m then
        m = { cards = {} }
        L.model.seats[s] = m
    end
    return m
end

local function cardKey(s, i) return ('%d:%d'):format(s, i) end

local function dropCard(L, s, i)
    local key = cardKey(s, i)
    local c = L.cards[key]
    if c then gone(c.ent) end
    L.cards[key] = nil
end

--- A card where it lies now, face up or down. Returns its entry.
local function placeCard(L, s, i, card)
    dropCard(L, s, i)
    local at, heading = CardSpot(L, s, i)
    local ent = makeProp(L, Cards.model(card or 'spd_ace'), at, heading, not card)
    if not ent then return nil end
    moveTo(ent, at, heading, not card)
    local c = { ent = ent, at = at, heading = heading, card = card }
    L.cards[cardKey(s, i)] = c
    return c
end

-- From where it is down onto its spot, quickly.
local function slideDown(L, key, c, ms)
    local from = GetEntityCoords(c.ent)
    local t0 = GetGameTimer()
    while L.cards[key] == c and DoesEntityExist(c.ent) do
        local k = math.min(1.0, (GetGameTimer() - t0) / ms)
        moveTo(c.ent, from + (c.at - from) * k, c.heading, not c.card)
        if k >= 1.0 then break end
        Wait(0)
    end
end

--- Three cards dealt to a seat (0 the dealer): in the dealer's hand as he deals them, then down on their spots.
--- No animation (a snapshot): straight onto their spots.
local function dealCards(L, s, cards, anim)
    local list = {}
    for i = 1, 3 do list[i] = placeCard(L, s, i, cards[i] or false) end
    local ped = L.dealer
    if not anim or not ped or not DoesEntityExist(ped) then return end
    for _, c in pairs(list) do SetEntityVisible(c.ent, false, false) end
    CreateThread(function()
        local D = L.dicts or DICT
        watchDrop(ped, D.tcp, anim, LY.dealerHand, GetEntityCoords(L.obj).z + LY.surface, function(hand, phase)
            if phase < LY.grabPhase then return end
            for i, c in pairs(list) do
                if L.cards[cardKey(s, i)] == c and DoesEntityExist(c.ent) then
                    SetEntityVisible(c.ent, true, false)
                    SetEntityCoordsNoOffset(c.ent, hand.x, hand.y, hand.z - 0.01 - 0.0008 * i, false, false, false)
                    flat(c.ent, c.heading, not c.card)
                end
            end
        end)
        -- Down one after the other.
        for i = 1, 3 do
            local c = list[i]
            local key = cardKey(s, i)
            if c and L.cards[key] == c and DoesEntityExist(c.ent) then
                SetEntityVisible(c.ent, true, false)
                slideDown(L, key, c, 140)
            end
        end
    end)
end

--- Cards turned over where they lie: lifted, flipped and laid back down.
local function revealCards(L, s, cards)
    for i = 1, 3 do
        local key = cardKey(s, i)
        local old = L.cards[key]
        local card = cards[i]
        if card and not (old and old.card == card) then
            local c = placeCard(L, s, i, card)
            if c then
                CreateThread(function()
                    local t0 = GetGameTimer()
                    while L.cards[key] == c and DoesEntityExist(c.ent) do
                        local k = math.min(1.0, (GetGameTimer() - t0) / 280)
                        SetEntityCoordsNoOffset(c.ent, c.at.x, c.at.y, c.at.z + math.sin(k * math.pi) * 0.05, false, false, false)
                        SetEntityRotation(c.ent, 180.0 * (1.0 - k), 0.0, c.heading, 2, true)
                        if k >= 1.0 then break end
                        Wait(0)
                    end
                end)
            end
        end
    end
end

local function stackChips(L, s, spot, amount)
    local key = ('%d:%s'):format(s, spot)
    for _, e in ipairs(L.chips[key] or {}) do gone(e) end
    L.chips[key] = nil
    if not amount or amount <= 0 then return end
    local x, y, tx, ty, z = ChipSpot(L, s, spot)
    local stacks = Cards.chips(amount)
    local list = {}
    for k, st in ipairs(stacks) do
        local off = (k - 1 - (#stacks - 1) / 2) * 0.042
        for j = 1, st.count do
            local at = world(L, x + tx * off, y + ty * off, z + (j - 1) * LY.chipHeight)
            local e = makeProp(L, st.model, at, GetEntityHeading(L.obj), false)
            if e then list[#list + 1] = e end
        end
    end
    L.chips[key] = list
end

local function seatPed(L, s)
    local src = L.model.taken[s]
    if not src then return nil end
    local p = GetPlayerFromServerId(src)
    if p == -1 then return nil end
    local ped = GetPlayerPed(p)
    return ped ~= 0 and ped or nil
end

--- Chips on a spot: as the player's hand puts them down (an `anim` playing), or at once.
local function chipsAt(L, s, spot, amount, anim)
    local ped = anim and seatPed(L, s)
    if not ped or not amount or amount <= 0 then return stackChips(L, s, spot, amount) end
    CreateThread(function()
        watchDrop(ped, PLAY_DICT, anim, LY.playerHand, GetEntityCoords(L.obj).z + LY.surface, nil, 0.12)
        local m = L.model.seats[s]
        if m and m[spot] == amount then stackChips(L, s, spot, amount) end
    end)
end

-- ============================================
-- The deck
-- ============================================

local function deckProp(L)
    if L.deck and DoesEntityExist(L.deck) then return L.deck end
    local at, heading = DeckSpot(L)
    L.deck = makeProp(L, LY.deckModel, at, heading, false)
    return L.deck
end

--- Lying on the felt.
local function deckOnTable(L)
    local ent = deckProp(L)
    if not ent then return end
    L.deckHeld = false
    DetachEntity(ent, false, false)
    local at, heading = DeckSpot(L)
    moveTo(ent, at, heading, false)
    FreezeEntityPosition(ent, true)
    SetEntityVisible(ent, true, false)
end

--- In the dealer's hand.
local function deckInHand(L, ped, hold)
    local ent = deckProp(L)
    ped = ped or L.dealer
    if not ent or not ped or not DoesEntityExist(ped) then return end
    L.deckHeld = true
    local h = hold or DeckHold(L)
    FreezeEntityPosition(ent, false)
    AttachEntityToEntity(ent, ped, GetPedBoneIndex(ped, LY.deckHand), h[1], h[2], h[3], h[4], h[5], h[6],
        false, false, false, false, 2, true)
end

--- Runs `fn` once the dealer is `phase` (0-1) into `anim`, or after a few seconds if it never plays.
local function atPhase(L, dict, anim, phase, fn)
    local ped = L.dealer
    CreateThread(function()
        local t0 = GetGameTimer()
        while GetGameTimer() - t0 < 6000 do
            if not ped or not DoesEntityExist(ped) then break end
            if IsEntityPlayingAnim(ped, dict, anim, 3) and GetEntityAnimCurrentTime(ped, dict, anim) >= phase then break end
            Wait(0)
        end
        fn()
    end)
end

--- Everything at a table put where it belongs now (a new layout arrived).
local function refresh(L)
    for key, c in pairs(L.cards) do
        local s, i = key:match('^(%d+):(%d+)$')
        s, i = tonumber(s), tonumber(i)
        if s and DoesEntityExist(c.ent) then
            c.at, c.heading = CardSpot(L, s, i)
            moveTo(c.ent, c.at, c.heading, not c.card)
        end
    end
    for s, m in pairs(L.model.seats) do
        for _, spot in ipairs(SPOTS) do stackChips(L, s, spot, m[spot]) end
    end
    if L.dealer and DoesEntityExist(L.dealer) then
        local at, heading, lift = DealerSpot(L)
        SetEntityCoordsNoOffset(L.dealer, at.x, at.y, at.z + lift, false, false, false)
        SetEntityHeading(L.dealer, heading)
    end
    if L.deckHeld then deckInHand(L) else deckOnTable(L) end
end

-- Every saved layout, once at start (and after a whip_core restart).
Whip.register(function()
    CreateThread(function()
        -- Asked again if the server wasn't ready (both restarting at once).
        for _ = 1, 10 do
            local all = exports.whip_core:Callback('whip_threecard:layouts')
            if type(all) == 'table' then
                for m, data in pairs(all) do Layouts[m] = data end
                for _, L in pairs(Live) do refresh(L) end
                return
            end
            Wait(3000)
        end
        print('[whip_threecard] could not get the saved layouts from the server: tables use them once you go near')
    end)
end)

RegisterNetEvent('whip_threecard:layout', function(model, data)
    if type(model) ~= 'string' then return end
    Layouts[model] = type(data) == 'table' and data or nil
    for _, L in pairs(Live) do
        if L.def.model == model then refresh(L) end
    end
end)

local function clearSeat(L, s)
    for i = 1, 3 do dropCard(L, s, i) end
    for _, spot in ipairs(SPOTS) do stackChips(L, s, spot, 0) end
    if s == 0 then L.model.dealer = {} else L.model.seats[s] = nil end
end

local function clearAll(L)
    for s = 0, SEATS do clearSeat(L, s) end
end

-- ============================================
-- The dealer
-- ============================================

local function dealerIdle(L)
    local n, only = 0, nil
    for s = 1, SEATS do if L.model.taken[s] then n, only = n + 1, s end end
    if n == 1 then return 'idle_single_p0' .. Cards.animSeat(only) end
    return 'dealer_idle'
end

local function dictsFor(female)
    local d = { tcp = DICT.tcp, shared = DICT.shared }
    if female then
        for k, name in pairs(FEMALE) do
            if DoesAnimDictExist(name) then d[k] = name end
        end
    end
    return d
end

--- One of the dealer's moves, then back to standing at the table. loop: keep playing it until the next.
local function playDealer(L, anim, dictKey, loop)
    local ped = L.dealer
    if not ped or not DoesEntityExist(ped) then return end
    local D = L.dicts or DICT
    L.token = (L.token or 0) + 1
    local mine = L.token
    CreateThread(function()
        local dict = D[dictKey or 'tcp'] or D.tcp
        if anim == 'idle' then anim, dict, loop = dealerIdle(L), D.shared, true end
        if not exports.whip_core:LoadAnimDict(dict) then return end
        if L.token ~= mine or not DoesEntityExist(ped) then return end
        TaskPlayAnim(ped, dict, anim, 3.0, -3.0, -1, loop and 1 or 0, 0.0, false, false, false)
        if loop then return end
        local ms = math.floor(GetAnimDuration(dict, anim) * 1000)
        Wait(math.max(500, ms - 150))
        if L.token ~= mine then return end
        if exports.whip_core:LoadAnimDict(D.shared) and DoesEntityExist(ped) then
            TaskPlayAnim(ped, D.shared, dealerIdle(L), 3.0, -3.0, -1, 1, 0.0, false, false, false)
        end
    end)
end

local function speak(L, line)
    if L.dealer and DoesEntityExist(L.dealer) then
        PlayPedAmbientSpeechWithVoiceNative(L.dealer, line, L.voice, 'SPEECH_PARAMS_FORCE_NORMAL_CLEAR', false)
    end
end

-- The same numbers from the same seed in every game (math.random would differ from game to game).
local function seeded(seed)
    local state = (tonumber(seed) or 1) % 2147483647
    if state <= 0 then state = state + 2147483646 end
    return function(n)
        state = (state * 48271) % 2147483647
        return (state % n) + 1
    end
end

-- A face, hair and the textures of the rest from the seed: a different dealer, in the model's own uniform.
local function dress(ped, seed)
    SetPedDefaultComponentVariation(ped)
    local roll = seeded(seed)
    for _, c in ipairs({ 0, 2 }) do   -- head, hair: any of the model's
        local n = GetNumberOfPedDrawableVariations(ped, c)
        if n > 0 then
            local d = roll(n) - 1
            local t = GetNumberOfPedTextureVariations(ped, c, d)
            SetPedComponentVariation(ped, c, d, t > 0 and (roll(t) - 1) or 0, 0)
        end
    end
    for _, c in ipairs({ 3, 4 }) do   -- torso, legs: their colour only, so the uniform stays a uniform
        local d = GetPedDrawableVariation(ped, c)
        local t = GetNumberOfPedTextureVariations(ped, c, d)
        if t > 1 then SetPedComponentVariation(ped, c, d, roll(t) - 1, 0) end
    end
end

local function makeDealer(L, look)
    look = type(look) == 'table' and look or { pick = ((L.id - 1) % #Config.Dealers) + 1, seed = L.id }
    local pick = Config.Dealers[look.pick] or Config.Dealers[1]
    local hash = model(pick.model)
    if not hash then
        return print(('[whip_threecard] table %d: the dealer model %s would not load'):format(L.id, pick.model))
    end
    local at, heading, lift = DealerSpot(L)
    -- A ped's position is its hips, not its feet: the floor is the table's origin, so up by the hips' height.
    local z = at.z + lift
    local ped = CreatePed(4, hash, at.x, at.y, z, heading, false, false)
    SetModelAsNoLongerNeeded(hash)
    if not ped or ped == 0 then
        return print(('[whip_threecard] table %d: the dealer could not be made'):format(L.id))
    end
    intoRoom(L, ped)
    SetEntityCoordsNoOffset(ped, at.x, at.y, z, false, false, false)
    SetEntityHeading(ped, heading)
    dress(ped, look.seed)
    SetEntityInvincible(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedCanRagdoll(ped, false)
    SetPedCanBeTargetted(ped, false)
    SetPedFleeAttributes(ped, 0, false)
    FreezeEntityPosition(ped, true)
    L.dealer, L.voice = ped, pick.voice
    L.dicts = dictsFor(pick.female)
    playDealer(L, 'idle')
end

-- ============================================
-- What the server says
-- ============================================

local function apply(L, kind, d, live)
    if kind == 'seat' then
        L.model.taken[d.seat] = d.src or nil
    elseif kind == 'chips' then
        local m = seatModel(L, d.seat)
        m[d.spot] = d.amount
        chipsAt(L, d.seat, d.spot, d.amount, live and d.anim or nil)
    elseif kind == 'deal' then
        local cards = type(d.cards) == 'table' and d.cards or {}
        if d.seat == 0 then L.model.dealer = { cards = cards } else seatModel(L, d.seat).cards = cards end
        dealCards(L, d.seat, cards, live and d.anim or nil)
    elseif kind == 'reveal' then
        local cards = type(d.cards) == 'table' and d.cards or {}
        if d.seat == 0 then L.model.dealer = { cards = cards } else seatModel(L, d.seat).cards = cards end
        revealCards(L, d.seat, cards)
    elseif kind == 'clear' then
        if d.all then clearAll(L) else clearSeat(L, d.seat) end
    elseif kind == 'dealer' then
        playDealer(L, d.anim, d.dict, d.loop)
        -- The deck goes into his hand as he picks it up, and back onto the felt as he puts it down.
        local dict = (L.dicts or DICT).tcp
        if d.anim == 'deck_pick_up' then
            if live then atPhase(L, dict, d.anim, LY.deckPickPhase, function() if Live[L.id] == L then deckInHand(L) end end)
            else deckInHand(L) end
        elseif d.anim == 'deck_put_down' then
            if live then atPhase(L, dict, d.anim, LY.deckPutPhase, function() if Live[L.id] == L then deckOnTable(L) end end)
            else deckOnTable(L) end
        end
    elseif kind == 'deck' then
        if d.held then deckInHand(L) else deckOnTable(L) end
    elseif kind == 'speech' then
        speak(L, d.line)
    end
end

RegisterNetEvent('whip_threecard:fx', function(id, kind, d)
    local L = Live[id]
    if not L or type(d) ~= 'table' then return end
    if not L.ready then
        L.queue[#L.queue + 1] = { kind, d }
        return
    end
    apply(L, kind, d, true)
end)

local function fromSnapshot(L, snap)
    clearAll(L)
    L.model.taken = {}
    for _, e in ipairs(snap.seats or {}) do L.model.taken[e.seat] = e.src end
    for _, e in ipairs(snap.hands or {}) do
        for _, spot in ipairs(SPOTS) do
            if e[spot] then apply(L, 'chips', { seat = e.seat, spot = spot, amount = e[spot] }, false) end
        end
        if e.cards then apply(L, 'deal', { seat = e.seat, cards = e.cards }, false) end
    end
    if snap.dealer then apply(L, 'deal', { seat = 0, cards = snap.dealer }, false) end
end

-- ============================================
-- Near and far
-- ============================================

local function findTable(def)
    if def.spawn then
        local h = model(def.model)
        if not h then return nil end
        local obj = CreateObject(h, def.coords.x, def.coords.y, def.coords.z, false, false, false)
        SetModelAsNoLongerNeeded(h)
        SetEntityHeading(obj, def.heading or 0.0)
        FreezeEntityPosition(obj, true)
        if def.texture then SetObjectTextureVariation(obj, def.texture) end
        return obj, true
    end
    local obj = GetClosestObjectOfType(def.coords.x, def.coords.y, def.coords.z, 1.5, joaat(def.model), false, false, false)
    if obj ~= 0 then
        if def.texture then SetObjectTextureVariation(obj, def.texture) end
        return obj, false
    end
    return nil
end

-- The seat a chair is.
local function seatAtChair(L, c)
    for s = 1, SEATS do if chairOf(L, s) == c then return s end end
    return c
end

-- A "Sit down" on each chair, while it's free.
local function chairPrompts(L)
    for c = 1, SEATS do
        local p = L.frame.chairs[c]
        local at = world(L, p.x, p.y, p.z + 0.85)
        exports.whip_core:AddAction({
            id = ('threecard_%d_%d'):format(L.id, c),
            group = 'threecard_' .. L.id,
            at = { coords = at },
            label = 'Sit down',
            icon = 'dollar',
            reach = 1.6,
            focusMode = 'aim',
            canInteract = function()
                return Seated == nil and not L.model.taken[seatAtChair(L, c)]
            end,
            onSelect = function() SitDown(L.id, seatAtChair(L, c)) end,
        })
    end
end

local function goLive(id, def)
    local obj, owned = findTable(def)
    if not obj then return end
    local L = {
        id = id, def = def, obj = obj, owned = owned,
        model = { seats = {}, dealer = {}, taken = {} }, cards = {}, chips = {},
        ready = false, queue = {},
    }
    Live[id] = L
    buildFrame(L)
    chairPrompts(L)
    local snap = exports.whip_core:Callback('whip_threecard:snapshot', id)
    if Live[id] ~= L then return end
    if type(snap) == 'table' and type(snap.layout) == 'table' then Layouts[def.model] = snap.layout end
    -- The dealer the server chose for this table this time (the same in every game).
    makeDealer(L, type(snap) == 'table' and snap.look or nil)
    if type(snap) == 'table' and snap.deckHeld then deckInHand(L) else deckOnTable(L) end
    if type(snap) == 'table' then fromSnapshot(L, snap) end
    L.ready = true
    for _, q in ipairs(L.queue) do apply(L, q[1], q[2], false) end
    L.queue = {}
end

local function goDark(id)
    local L = Live[id]
    if not L then return end
    Live[id] = nil
    exports.whip_core:RemoveActionGroup('threecard_' .. id)
    clearAll(L)
    gone(L.deck)
    gone(L.dealer)
    if L.owned then gone(L.obj) end
end

CreateThread(function()
    while true do
        local here = GetEntityCoords(PlayerPedId())
        for id, def in ipairs(Config.Tables) do
            local d = #(here - vector3(def.coords.x, def.coords.y, def.coords.z))
            if d <= Config.DrawRange and not Live[id] then
                goLive(id, def)
            elseif d > Config.DrawRange + 10.0 and Live[id] and not (Seated and Seated.table == id) then
                goDark(id)
            end
        end
        Wait(1000)
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for id in pairs(Live) do goDark(id) end
end)

-- For client/editor.lua.
TCP = {
    world = world, toLocal = toLocal, makeProp = makeProp, gone = gone, moveTo = moveTo,
    chairOf = chairOf, refresh = refresh, SPOTS = SPOTS,
    playDealer = playDealer, deckInHand = deckInHand, deckOnTable = deckOnTable,
}
