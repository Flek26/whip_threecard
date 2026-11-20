-- ============================================
-- whip_threecard — client: playing
-- ============================================
--
-- Sitting down (the casino's own seat animations, played as networked scenes at the chair so everyone sees them),
-- the keys while seated, the camera over your shoulder, and the panel (html/). The server decides everything: this
-- game only says what the player chose.

local SEAT_DICT = 'anim_casino_b@amb@casino@games@shared@player@'
local PLAY_DICT = 'anim_casino_b@amb@casino@games@threecardpoker@player'
local K = Config.Keys

Seated = nil   -- { table, seat, chair, heading, bet, hud, camera, hint }

local function notify(msg, kind) exports.whip_core:Notify(msg, kind or 'inform') end
local function nui(msg) SendNUIMessage(msg) end

-- ============================================
-- The chair
-- ============================================

local function scene(dict, anim, loop)
    local S = Seated
    if not S then return end
    local c = S.chair
    local s = NetworkCreateSynchronisedScene(c.x, c.y, c.z, 0.0, 0.0, S.heading, 2, not loop, loop, 1.0, 0.0, 1.0)
    NetworkAddPedToSynchronisedScene(PlayerPedId(), s, dict, anim, 2.0, -2.0, 13, 16, 1000.0, 0)
    NetworkStartSynchronisedScene(s)
    return s
end

local function idle()
    if Seated then scene(SEAT_DICT, 'idle_cardgames', true) end
end

local animToken = 0

--- One of the table's moves (a bet, play, fold, a reaction), then back to sitting.
local function seatAnim(anim, dictKey)
    if not Seated then return end
    local dict = dictKey == 'shared' and SEAT_DICT or PLAY_DICT
    animToken = animToken + 1
    local mine = animToken
    CreateThread(function()
        if not exports.whip_core:LoadAnimDict(dict) or not Seated then return end
        scene(dict, anim, false)
        Wait(math.max(400, math.floor(GetAnimDuration(dict, anim) * 1000) - 100))
        if animToken == mine then idle() end
    end)
end

RegisterNetEvent('whip_threecard:anim', function(anim, dictKey) seatAnim(anim, dictKey) end)

-- ============================================
-- The camera
-- ============================================

local function cameraOn()
    local S = Seated
    local L = S and Live[S.table]
    if not L then return end
    local h = math.rad(S.heading)
    local fx, fy = -math.sin(h), math.cos(h)
    local pos = vector3(S.chair.x - fx * Config.Camera.back, S.chair.y - fy * Config.Camera.back, S.chair.z + Config.Camera.up)
    local look = FeltMiddle(L)
    local d = look - pos
    local pitch = math.deg(math.atan(d.z, math.sqrt(d.x * d.x + d.y * d.y)))
    local yaw = GetHeadingFromVector_2d(d.x, d.y)
    exports.whip_core:PlayCamera({
        pos = pos, rot = vector3(pitch, 0.0, yaw), fov = Config.Camera.fov,
        exitKey = false, async = true, transitionIn = 600, transitionOut = 600,
    })
    S.camera = true
end

local function cameraOff()
    if Seated and Seated.camera then
        exports.whip_core:StopCamera()
        Seated.camera = false
    end
end

-- ============================================
-- What the keys say
-- ============================================

local function key(k) return exports.whip_core:KeyHint(k.text, k.button) end

local function betting(H) return H.phase == 'idle' or H.phase == 'betting' or H.phase == nil end

local function hintFor(S)
    local H = S.hud or {}
    local parts = {}
    if H.ask == 'decide' then
        parts[#parts + 1] = key(K.accept) .. ' Play ' .. Cards.money(H.cost or 0)
        parts[#parts + 1] = key(K.fold) .. ' Fold'
    elseif betting(H) and not H.ante then
        parts[#parts + 1] = key(K.up) .. key(K.down) .. ' Bet'
        parts[#parts + 1] = key(K.min) .. key(K.max) .. ' Min / Max'
        parts[#parts + 1] = key(K.accept) .. ' Ante ' .. Cards.money(S.bet)
        parts[#parts + 1] = key(K.leave) .. ' Leave'
    elseif betting(H) and not H.plus then
        parts[#parts + 1] = key(K.up) .. key(K.down) .. ' Bet'
        parts[#parts + 1] = key(K.accept) .. ' Pair Plus ' .. Cards.money(S.bet)
        parts[#parts + 1] = key(K.leave) .. ' Take bets back'
    elseif betting(H) then
        parts[#parts + 1] = key(K.leave) .. ' Take bets back'
    else
        parts[#parts + 1] = key(K.leave) .. ' Leave'
    end
    parts[#parts + 1] = key(K.camera) .. ' Table camera'
    local v = exports.whip_core:KeyHint('V', nil)   -- keyboard only: on a pad that button is the table camera's
    if v ~= '' then parts[#parts + 1] = v .. ' View' end
    return table.concat(parts, '  |  ')
end

local function refreshHint()
    local S = Seated
    if not S then return end
    local text = hintFor(S)
    if text ~= S.hint then
        S.hint = text
        exports.whip_core:ShowText(text, { icon = 'dollar' })
    end
end

-- The server's word on this player arrives while they're still walking to the chair: kept until they've sat.
local lastHud = nil

RegisterNetEvent('whip_threecard:hud', function(d)
    if type(d) ~= 'table' then return end
    lastHud = d
    local S = Seated
    if not S or d.table ~= S.table then return end
    S.hud = d
    nui({ type = 'hud', hud = d, bet = S.bet })
    refreshHint()
end)

-- ============================================
-- Up and down
-- ============================================

local function standUp(tell)
    local S = Seated
    if not S then return end
    if tell then TriggerServerEvent('whip_threecard:leave') end
    cameraOff()
    exports.whip_core:HideText()
    exports.whip_core:UnblockControls('whip_threecard')
    nui({ type = 'hide' })
    local ped = PlayerPedId()
    if not IsEntityDead(ped) and exports.whip_core:LoadAnimDict(SEAT_DICT) then
        local s = scene(SEAT_DICT, 'sit_exit_left', false)
        Seated = nil
        -- Up off the chair, then free: once they're on their feet, or sooner if they set off walking.
        local t0 = GetGameTimer()
        local total = math.max(800, math.floor(GetAnimDuration(SEAT_DICT, 'sit_exit_left') * 1000))
        while GetGameTimer() - t0 < total * 0.75 do
            local phase = 0.0
            local loc = s and NetworkGetLocalSceneFromNetworkId(s) or -1
            if loc ~= -1 then phase = GetSynchronizedScenePhase(loc) end
            if phase >= 0.7 then break end
            local moving = math.abs(GetControlNormal(0, 30)) > 0.3 or math.abs(GetControlNormal(0, 31)) > 0.3
            if moving and GetGameTimer() - t0 > total * 0.35 then break end
            Wait(0)
        end
        if s then NetworkStopSynchronisedScene(s) end
    end
    Seated = nil
    ClearPedTasks(ped)
end

RegisterNetEvent('whip_threecard:stand', function() standUp(false) end)

local function controls(S)
    local T = Config.Tables[S.table]
    local step = T.step or T.min
    local function pressed(k) return exports.whip_core:IsKeyPressed(k.key, k.pad) end
    while Seated == S do
        local H = S.hud or {}

        if pressed(K.camera) then
            if S.camera then cameraOff() else cameraOn() end
        end
        -- V: GTA's own views (first person and the rest), so the table camera steps aside.
        if S.camera and IsControlJustPressed(0, 0) then cameraOff() end

        if H.ask == 'decide' then
            if pressed(K.accept) then TriggerServerEvent('whip_threecard:act', 'play')
            elseif pressed(K.fold) then TriggerServerEvent('whip_threecard:act', 'fold') end
        elseif betting(H) and not (H.ante and H.plus) then
            local bet = S.bet
            if pressed(K.up) then bet = bet + step
            elseif pressed(K.down) then bet = bet - step
            elseif pressed(K.min) then bet = T.min
            elseif pressed(K.max) then bet = T.max end
            bet = math.max(T.min, math.min(T.max, bet))
            if bet ~= S.bet then
                S.bet = bet
                nui({ type = 'bet', bet = bet })
                refreshHint()
            end
            if pressed(K.accept) then TriggerServerEvent('whip_threecard:bet', H.ante and 'plus' or 'ante', S.bet) end
        end

        if pressed(K.leave) then
            if betting(H) and H.ante then
                TriggerServerEvent('whip_threecard:unbet')
            else
                if H.cards and not H.result and H.ask == 'decide' then
                    notify('You fold: your Pair Plus still plays, and is paid to you', 'inform')
                end
                standUp(true)
            end
        end

        -- Knocked off the chair.
        if #(GetEntityCoords(PlayerPedId()) - S.chair) > Config.LeaveDistance then standUp(true) end
        Wait(0)
    end
end

--- Sits in one seat at a table: client/table.lua's chair prompts call it.
function SitDown(tableId, seat)
    if Seated then return end
    local L = Live[tableId]
    if not L then return notify('The table isn\'t ready yet', 'error') end
    local res, why = exports.whip_core:Callback('whip_threecard:sit', tableId, seat)
    if not res then return notify(why or 'You can\'t sit here', 'error') end

    local chair, heading = ChairSpot(L, res.seat)
    local ped = PlayerPedId()
    -- Walk to where the sit-down animation starts (beside the chair), not into the chair itself: the chair's
    -- in the way, and they'd walk on the spot. Close enough, or stopped getting closer, and the animation takes over.
    if exports.whip_core:LoadAnimDict(SEAT_DICT) then
        local start = GetAnimInitialOffsetPosition(SEAT_DICT, 'sit_enter_left', chair.x, chair.y, chair.z, 0.0, 0.0, heading, 0.0, 2)
        local turn = GetAnimInitialOffsetRotation(SEAT_DICT, 'sit_enter_left', chair.x, chair.y, chair.z, 0.0, 0.0, heading, 0.0, 2)
        if #(GetEntityCoords(ped) - start) > 0.35 then
            TaskGoStraightToCoord(ped, start.x, start.y, start.z, 1.0, 3000, turn.z, 0.05)
            local t0, best, still = GetGameTimer(), math.huge, 0
            while GetGameTimer() - t0 < 3000 do
                Wait(100)
                local d = #(GetEntityCoords(ped).xy - start.xy)
                if d < 0.3 then break end
                if d < best - 0.02 then best, still = d, 0 else still = still + 1 end
                if still >= 4 then break end   -- 0.4 s without getting closer: blocked
            end
        end
    end

    local T = Config.Tables[tableId]
    if lastHud and lastHud.table ~= tableId then lastHud = nil end
    Seated = { table = tableId, seat = res.seat, chair = chair, heading = heading, bet = T.min }
    local S = Seated
    -- Left free: looking (1, 2), GTA's views on V (0, first person among them), pause, chat, push-to-talk.
    exports.whip_core:BlockControls('whip_threecard', { all = true, except = { 0, 1, 2, 199, 200, 245, 249 }, mode = true })
    if exports.whip_core:LoadAnimDict(SEAT_DICT) then
        scene(SEAT_DICT, 'sit_enter_left', false)
        Wait(math.max(1000, math.floor(GetAnimDuration(SEAT_DICT, 'sit_enter_left') * 1000) - 150))
    end
    if Seated ~= S then return end
    idle()
    nui({ type = 'show', label = T.label or 'Three Card Poker', min = T.min, max = T.max, bet = S.bet })
    if lastHud and lastHud.table == tableId then
        S.hud = lastHud
        nui({ type = 'hud', hud = lastHud, bet = S.bet })
    end
    if Config.Camera.enabled then cameraOn() end
    refreshHint()
    CreateThread(function() controls(S) end)
end

AddEventHandler('whip_core:player:died', function()
    if Seated then standUp(true) end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() or not Seated then return end
    cameraOff()
    exports.whip_core:HideText()
    ClearPedTasks(PlayerPedId())
end)
