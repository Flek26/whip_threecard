-- ============================================
-- whip_threecard — client: /tcpedit, the layout editor
-- ============================================
--
-- At a table: every card, chip stack and the dealer shown where they go now, as ghosts. Pick one, move it with the
-- arrows (the way you're looking), turn it, raise it; say which chair each seat is. Enter saves it for the table's
-- model (Shift+Enter: every table model) to layout.json on the server, and every game uses it at once.
-- Saving needs whip.devtools.

local SEATS = 4
local LY = Config.Layout

local E = nil   -- { L, items, sel, data, ghosts = { [item] = ent }, dirty, hint, warnExit, group }

local CARD_MODEL = 'vw_prop_cas_card_hrt_ace'
local CHIP_MODEL = { ante = 'vw_prop_chip_500dollar_st', play = 'vw_prop_chip_1kdollar_st', plus = 'vw_prop_chip_100dollar_st' }
local SPOT_NAME = { ante = 'Ante chips', play = 'Play chips', plus = 'Pair Plus chips' }

-- ============================================
-- What can be set
-- ============================================

local function buildItems()
    local list = {}
    local function add(t) list[#list + 1] = t end
    add({ kind = 'dealer', block = 0, label = 'Dealer: where he stands' })
    for i = 1, 3 do add({ kind = 'card', s = 0, i = i, block = 0, label = ('Dealer: card %d'):format(i) }) end
    add({ kind = 'deck', block = 0, label = 'Dealer: the deck on the table' })
    add({ kind = 'hold', block = 0, label = 'Dealer: the deck in his hand' })
    for s = 1, SEATS do
        add({ kind = 'chair', s = s, block = s, label = ('Seat %d: which chair'):format(s) })
        for _, spot in ipairs(TCP.SPOTS) do
            add({ kind = 'chips', s = s, spot = spot, block = s, label = ('Seat %d: %s'):format(s, SPOT_NAME[spot]) })
        end
        for i = 1, 3 do add({ kind = 'card', s = s, i = i, block = s, label = ('Seat %d: card %d'):format(s, i) }) end
    end
    return list
end

local function cardKey(s, i) return ('%d:%d'):format(s, i) end
local function chipKey(s, spot) return ('%d:%s'):format(s, spot) end

-- Where everything is now, in the table's frame: what the editor starts from.
local function readNow(L)
    local base = GetEntityHeading(L.obj)
    local function rel(h) return ((h - base + 540.0) % 360.0) - 180.0 end
    local d = { chairs = {}, cards = {}, chips = {} }
    for s = 1, SEATS do d.chairs[tostring(s)] = TCP.chairOf(L, s) end
    for s = 0, SEATS do
        for i = 1, 3 do
            local at, heading = CardSpot(L, s, i)
            local lp = TCP.toLocal(L, at)
            d.cards[cardKey(s, i)] = { lp.x, lp.y, lp.z, rel(heading) }
        end
        if s > 0 then
            for _, spot in ipairs(TCP.SPOTS) do
                local x, y, tx, ty, z = ChipSpot(L, s, spot)
                d.chips[chipKey(s, spot)] = { x, y, z or LY.surface, math.deg(math.atan(ty, tx)) }
            end
        end
    end
    local at, heading, lift = DealerSpot(L)
    local lp = TCP.toLocal(L, at)
    d.dealer = { lp.x, lp.y, lift, rel(heading) }
    local dat, dheading = DeckSpot(L)
    local dlp = TCP.toLocal(L, dat)
    d.deck = { dlp.x, dlp.y, dlp.z, rel(dheading) }
    local h = DeckHold(L)
    d.hold = { h[1], h[2], h[3], h[4], h[5], h[6] }
    return d
end

local function spotOf(item)
    if item.kind == 'deck' then return E.data.deck end
    if item.kind == 'hold' then return E.data.hold end
    if item.kind == 'card' then return E.data.cards[cardKey(item.s, item.i)] end
    if item.kind == 'chips' then return E.data.chips[chipKey(item.s, item.spot)] end
    if item.kind == 'dealer' then return E.data.dealer end
end

-- ============================================
-- The ghosts
-- ============================================

local function place(item)
    local L = E.L
    local v = spotOf(item)
    if not v then return end
    local heading = (GetEntityHeading(L.obj) + v[4]) % 360.0
    if item.kind == 'dealer' then
        if L.dealer and DoesEntityExist(L.dealer) then
            local at = TCP.world(L, v[1], v[2], v[3])
            SetEntityCoordsNoOffset(L.dealer, at.x, at.y, at.z, false, false, false)
            SetEntityHeading(L.dealer, heading)
        end
        return
    end
    if item.kind == 'hold' then
        -- The ghost deck in the dealer's hand, as it'll be held.
        if E.held and DoesEntityExist(E.held) then TCP.deckInHand({ deck = E.held, dealer = L.dealer }, L.dealer, v) end
        return
    end
    local ent = E.ghosts[item]
    if ent and DoesEntityExist(ent) then
        if item.kind == 'deck' then return TCP.moveTo(ent, TCP.world(L, v[1], v[2], v[3]), heading, false) end
        -- The dealer's cards are shown face down, as they're dealt.
        TCP.moveTo(ent, TCP.world(L, v[1], v[2], v[3]), heading, item.kind == 'card' and item.s == 0)
    end
end

local function makeGhosts()
    local L = E.L
    -- The real deck hides while its ghosts stand in; the dealer holds one the way he does while players decide.
    if L.deck and DoesEntityExist(L.deck) then SetEntityVisible(L.deck, false, false) end
    if L.dealer and DoesEntityExist(L.dealer) then
        E.held = TCP.makeProp(L, LY.deckModel, GetEntityCoords(L.dealer), 0.0, false)
        TCP.playDealer(L, 'deck_idle', 'tcp', true)
    end
    for _, item in ipairs(E.items) do
        if item.kind == 'hold' then place(item) end
        if item.kind == 'card' or item.kind == 'chips' or item.kind == 'deck' then
            local v = spotOf(item)
            local name = item.kind == 'card' and CARD_MODEL or (item.kind == 'deck' and LY.deckModel or CHIP_MODEL[item.spot])
            local ent = TCP.makeProp(L, name, TCP.world(L, v[1], v[2], v[3]), 0.0, false)
            if ent then
                E.ghosts[item] = ent
                place(item)
            end
        end
    end
end

-- With group on (X), a card moves with the rest of its hand: the same seat, cards 1-3.
local function groupOf(item)
    if not (E.group and item.kind == 'card') then return { item } end
    local list = {}
    for _, it in ipairs(E.items) do
        if it.kind == 'card' and it.s == item.s then list[#list + 1] = it end
    end
    return list
end

local function inGroup(item, sel)
    if item == sel then return true end
    return E.group and sel.kind == 'card' and item.kind == 'card' and item.s == sel.s
end

local function shade()
    local sel = E.items[E.sel]
    for item, ent in pairs(E.ghosts) do
        if DoesEntityExist(ent) then
            -- The one being moved bright (its whole hand, grouped); its seat's others half; the rest faint.
            local a = inGroup(item, sel) and 255 or (item.block == sel.block and 170 or 70)
            if a == 255 then ResetEntityAlpha(ent) else SetEntityAlpha(ent, a, false) end
        end
    end
end

-- ============================================
-- Drawing labels
-- ============================================

local function text3d(p, words, scale, r, g, b)
    SetDrawOrigin(p.x, p.y, p.z, 0)
    SetTextFont(4)
    SetTextScale(0.0, scale or 0.32)
    SetTextCentre(true)
    SetTextOutline()
    SetTextColour(r or 255, g or 255, b or 255, 255)
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(words)
    EndTextCommandDisplayText(0.0, 0.0)
    ClearDrawOrigin()
end

local function drawChairs()
    local L = E.L
    local sel = E.items[E.sel]
    for s = 1, SEATS do
        local c = E.data.chairs[tostring(s)] or s
        local p = L.frame.chairs[c]
        local at = TCP.world(L, p.x, p.y, p.z)
        local lit = sel.kind == 'chair' and sel.s == s
        DrawMarker(1, at.x, at.y, at.z + 0.02, 0, 0, 0, 0, 0, 0, 0.45, 0.45, 0.04,
            lit and 96 or 255, lit and 165 or 255, lit and 250 or 255, lit and 200 or 90, false, false, 2, false, nil, nil, false)
        text3d(vector3(at.x, at.y, at.z + 1.25), ('Seat %d'):format(s), 0.38, lit and 96 or 255, lit and 165 or 255, lit and 250 or 255)
    end
end

local function drawSelected()
    local L = E.L
    local item = E.items[E.sel]
    local v = spotOf(item)
    local at
    if item.kind == 'chair' then
        local p = L.frame.chairs[E.data.chairs[tostring(item.s)] or item.s]
        at = TCP.world(L, p.x, p.y, p.z + 1.0)
    elseif item.kind == 'hold' then
        if E.held and DoesEntityExist(E.held) then at = GetEntityCoords(E.held) end
        if at then
            text3d(vector3(at.x, at.y, at.z + 0.22), item.label .. ('~n~x %.3f  y %.3f  z %.3f  tilt %.1f  turn %.1f'):format(v[1], v[2], v[3], v[4], v[6]), 0.3)
        end
        return
    elseif v then
        at = TCP.world(L, v[1], v[2], v[3])
        DrawMarker(2, at.x, at.y, at.z + 0.12, 0, 0, 0, 180.0, 0, 0, 0.05, 0.05, 0.05, 96, 165, 250, 220, false, false, 2, false, nil, nil, false)
    end
    if at then
        local words = item.label
        if v then words = words .. ('~n~x %.3f  y %.3f  z %.3f  turn %.1f'):format(v[1], v[2], v[3], v[4]) end
        text3d(vector3(at.x, at.y, at.z + 0.22), words, 0.3)
    end
end

-- ============================================
-- Keys
-- ============================================

local function hint()
    local item = E.items[E.sel]
    local moveWord = item.kind == 'chair' and '[Left][Right] Chair'
        or (item.kind == 'hold' and '[Arrows] Move in the hand  |  [PgUp][PgDn] Up/down  |  [Q][E] Turn  |  [Z][C] Tilt'
        or '[Arrows] Move  |  [Q][E] Turn  |  [PgUp][PgDn] Height')
    local groupWord = item.kind == 'card' and ('  |  [X] Whole hand: %s'):format(E.group and 'ON' or 'off') or ''
    local text = ('%s  (%d/%d)  |  [Scroll] Next, [Shift] seat  |  %s%s  |  [Shift] Fine  |  [G] Reset  |  [Enter] Save  [Shift+Enter] All tables  |  [Backspace] Exit')
        :format(item.label, E.sel, #E.items, moveWord, groupWord)
    if text ~= E.hint then
        E.hint = text
        exports.whip_core:ShowText(text, { icon = 'place' })
    end
end

local function held(c) return IsDisabledControlPressed(0, c) end
local function hit(c) return IsDisabledControlJustPressed(0, c) end

local function step(dir, jump)
    local n = #E.items
    if jump then
        -- Blocks: 0 the dealer, 1-4 the seats. To the first item of the next (or last) one.
        local target = (E.items[E.sel].block + dir) % (SEATS + 1)
        for i, it in ipairs(E.items) do
            if it.block == target then E.sel = i break end
        end
    else
        E.sel = ((E.sel - 1 + dir) % n) + 1
    end
    shade()
end

-- What's been set is kept on this PC too, so reopening /tcpedit brings it back even if a save didn't take.
local function draftKey(model) return 'tcpdraft:' .. model end

local function keepDraft()
    if E then SetResourceKvp(draftKey(E.L.def.model), json.encode(E.data)) end
end

local function save(all)
    keepDraft()
    local L = E.L
    local models = { [L.def.model] = true }
    if all then for _, T in ipairs(Config.Tables) do models[T.model] = true end end
    for model in pairs(models) do TriggerServerEvent('whip_threecard:saveLayout', model, E.data) end
    E.dirty, E.warnExit = false, false
end

local function stop()
    if not E then return end
    if E.dirty then keepDraft() end
    for _, ent in pairs(E.ghosts) do TCP.gone(ent) end
    TCP.gone(E.held)
    local L = E.L
    E = nil
    exports.whip_core:HideText()
    exports.whip_core:UnblockControls('whip_threecard_edit')
    if Live[L.id] == L then
        TCP.refresh(L)
        if L.deck and DoesEntityExist(L.deck) then SetEntityVisible(L.deck, true, false) end
        TCP.playDealer(L, 'idle')
    end
end

local function frame()
    local L = E.L
    if Live[L.id] ~= L then return stop() end
    local fine = held(21)
    local dt = GetFrameTime()

    if hit(15) then step(-1, fine) elseif hit(14) then step(1, fine) end
    local item = E.items[E.sel]

    if item.kind == 'hold' then
        -- In the hand bone's own frame: Up/Down x, Left/Right y, PgUp/PgDn z, Q/E turn, Z/C tilt.
        local v = E.data.hold
        local speed = (fine and 0.01 or 0.08) * dt
        local spin = (fine and 10.0 or 60.0) * dt
        local mx = (held(172) and 1 or 0) - (held(173) and 1 or 0)
        local my = (held(175) and 1 or 0) - (held(174) and 1 or 0)
        local mz = (held(10) and 1 or 0) - (held(11) and 1 or 0)
        local rz = (held(44) and 1 or 0) - (held(38) and 1 or 0)
        local rx = (held(20) and 1 or 0) - (held(26) and 1 or 0)
        if mx ~= 0 or my ~= 0 or mz ~= 0 or rz ~= 0 or rx ~= 0 then
            v[1], v[2], v[3] = v[1] + mx * speed, v[2] + my * speed, v[3] + mz * speed
            v[4] = ((v[4] + rx * spin + 540.0) % 360.0) - 180.0
            v[6] = ((v[6] + rz * spin + 540.0) % 360.0) - 180.0
            place(item)
            E.dirty = true
        end
        if hit(47) then
            E.data.hold = readNow(L).hold
            place(item)
        end
    elseif item.kind == 'chair' then
        local dir = hit(174) and -1 or (hit(175) and 1 or 0)
        if dir ~= 0 then
            local key = tostring(item.s)
            local old = E.data.chairs[key] or item.s
            local new = ((old - 1 + dir) % SEATS) + 1
            -- Two seats can't share a chair: whoever had it takes this one's old chair.
            for k, c in pairs(E.data.chairs) do if c == new then E.data.chairs[k] = old end end
            E.data.chairs[key] = new
            E.dirty = true
        end
    else
        if item.kind == 'card' and hit(73) then
            E.group = not E.group
            shade()
        end
        local members = groupOf(item)
        if spotOf(item) then
            -- The way you're looking, in the table's frame.
            local a = math.rad(GetGameplayCamRot(2).z - GetEntityHeading(L.obj))
            local fx, fy = -math.sin(a), math.cos(a)
            local rx, ry = math.cos(a), math.sin(a)
            local speed = (fine and 0.03 or 0.25) * dt
            local mf = (held(172) and 1 or 0) - (held(173) and 1 or 0)
            local mr = (held(175) and 1 or 0) - (held(174) and 1 or 0)
            local turn = (held(44) and 1 or 0) - (held(38) and 1 or 0)
            local up = (held(10) and 1 or 0) - (held(11) and 1 or 0)
            if mf ~= 0 or mr ~= 0 or turn ~= 0 or up ~= 0 then
                local dx, dy = (fx * mf + rx * mr) * speed, (fy * mf + ry * mr) * speed
                local dz = up * (fine and 0.01 or 0.1) * dt
                local dh = turn * (fine and 10.0 or 60.0) * dt
                -- A group turns as one piece, round its middle; one card turns on its own spot.
                local cx, cy, n = 0.0, 0.0, 0
                for _, m in ipairs(members) do
                    local v = spotOf(m)
                    if v then cx, cy, n = cx + v[1], cy + v[2], n + 1 end
                end
                cx, cy = cx / math.max(1, n), cy / math.max(1, n)
                -- GTA turns left for a positive heading: the same way round for the positions.
                local r = math.rad(dh)
                local cs, sn = math.cos(r), math.sin(r)
                for _, m in ipairs(members) do
                    local v = spotOf(m)
                    if v then
                        if #members > 1 and dh ~= 0 then
                            local ox, oy = v[1] - cx, v[2] - cy
                            v[1], v[2] = cx + ox * cs - oy * sn, cy + ox * sn + oy * cs
                        end
                        v[1], v[2], v[3] = v[1] + dx, v[2] + dy, v[3] + dz
                        v[4] = ((v[4] + dh + 540.0) % 360.0) - 180.0
                        place(m)
                    end
                end
                E.dirty = true
            end
        end
        if hit(47) then
            local now = readNow(L)
            for _, m in ipairs(members) do
                if m.kind == 'card' then E.data.cards[cardKey(m.s, m.i)] = now.cards[cardKey(m.s, m.i)]
                elseif m.kind == 'chips' then E.data.chips[chipKey(m.s, m.spot)] = now.chips[chipKey(m.s, m.spot)]
                elseif m.kind == 'deck' then E.data.deck = now.deck
                elseif m.kind == 'dealer' then E.data.dealer = now.dealer end
                place(m)
            end
        end
    end

    if hit(191) then save(fine) end
    if hit(194) then
        if E.dirty and not E.warnExit then
            E.warnExit = true
            exports.whip_core:Notify('Not saved: Backspace again to leave without saving, Enter to save', 'error')
        else
            return stop()
        end
    end

    drawChairs()
    drawSelected()
    hint()
end

RegisterCommand('tcpedit', function()
    if E then return stop() end
    local here = GetEntityCoords(PlayerPedId())
    local best, bestD
    for _, L in pairs(Live) do
        local d = #(here - GetEntityCoords(L.obj))
        if d < 6.0 and (not bestD or d < bestD) then best, bestD = L, d end
    end
    if not best then return exports.whip_core:Notify('Stand at a three card poker table first', 'error') end
    if Seated then return exports.whip_core:Notify('Get up first', 'error') end

    E = { L = best, items = buildItems(), sel = 1, ghosts = {}, dirty = false }
    E.data = readNow(best)
    -- A draft from last time: whatever it set wins over what the table shows now (G still resets one item).
    local raw = GetResourceKvpString(draftKey(best.def.model))
    if raw then
        local ok, draft = pcall(json.decode, raw)
        if ok and type(draft) == 'table' then
            for _, part in ipairs({ 'cards', 'chips', 'chairs' }) do
                for k, v in pairs(draft[part] or {}) do E.data[part][k] = v end
            end
            if draft.dealer then E.data.dealer = draft.dealer end
            if draft.deck then E.data.deck = draft.deck end
            if draft.hold then E.data.hold = draft.hold end
            exports.whip_core:Notify('Your last edit is back. Enter saves it.', 'inform')
        end
    end
    makeGhosts()
    shade()
    -- Walk round and look freely; everything else is the editor's.
    exports.whip_core:BlockControls('whip_threecard_edit', {
        all = true, except = { 0, 1, 2, 30, 31, 32, 33, 34, 35, 199, 200, 245, 249 }, mode = true,
    })
    CreateThread(function()
        while E do
            frame()
            Wait(0)
        end
    end)
end, false)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() and E then
        for _, ent in pairs(E.ghosts) do TCP.gone(ent) end
        TCP.gone(E.held)
    end
end)
