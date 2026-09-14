-- ============================================================
-- SkillUp addon -- FFXI/Windower player-state helpers
-- ============================================================
-- Read-only helpers for player, pet, party, buff, weather, and
-- inventory state, all built on raw Windower calls (windower.ffxi.*,
-- res.*) rather than GearSwap's injected globals (player, pet,
-- buffactive) which don't exist in a standalone addon. These carry no
-- SkillUp-specific decision logic -- just data readers any addon could
-- reuse -- so they live here rather than in skillup.lua itself.

-- Function: get_own_mob
-- Description: Gets the live mob object for the player's own character,
--   resolved via their party index. This is the standalone equivalent
--   of GearSwap's implicit player-as-mob access.
-- Parameters: none
-- Returns: mob (table) or nil - the player's own mob object, or nil if
--   player data isn't available yet
function get_own_mob()
    local p = windower.ffxi.get_player()
    return p and windower.ffxi.get_mob_by_index(p.index)
end

-- Function: get_player_status_string
-- Description: Gets the player's current status (e.g. "Idle",
--   "Engaged", "Resting") as an English string, resolved from the
--   player's numeric status ID via res.statuses.
-- Parameters: none
-- Returns: string or nil - the status name, or nil if player/status
--   data isn't available
function get_player_status_string()
    local p = windower.ffxi.get_player()
    local st = p and res.statuses[p.status]
    return st and (st.english or st.en) or nil
end

-- Function: get_pet_mob
-- Description: Gets the live mob object for the player's current pet
--   (avatar, wyvern, automaton, trust, etc.), resolved via the owner
--   mob's pet_index field.
-- Parameters: none
-- Returns: mob (table) or nil - the pet's mob object, or nil if there's
--   no active pet or player data isn't available
function get_pet_mob()
    local me = get_own_mob()
    if not me or not me.pet_index or me.pet_index == 0 then return nil end
    return windower.ffxi.get_mob_by_index(me.pet_index)
end

-- Function: pet_is_valid
-- Description: Checks whether the player currently has a pet that's a
--   valid, live target (as opposed to e.g. a released or despawned
--   pet whose mob entry may briefly still exist).
-- Parameters: none
-- Returns: boolean - true if there's a pet and it's a valid target
function pet_is_valid()
    local pet_mob = get_pet_mob()
    return pet_mob ~= nil and pet_mob.valid_target
end

-- buffactive[id_or_name] = true for every buff currently active on the
-- player, keyed by both numeric buff ID and English name for
-- convenience. Kept in sync live by the 'gain buff'/'lose buff' event
-- handlers registered in skillup.lua, and rebuilt from scratch on
-- addon load via rebuild_buffactive() below (in case buffs were already
-- active before the addon started tracking them).
buffactive = {}

-- Function: rebuild_buffactive
-- Description: Rebuilds the buffactive table from scratch by reading
--   the player's current buff list. Called once at addon load, since
--   the 'gain buff'/'lose buff' events only fire for buffs that change
--   AFTER the addon starts listening -- any buffs already active
--   beforehand would otherwise never appear in buffactive at all.
-- Parameters: none
-- Returns: none (mutates the global buffactive table in place)
function rebuild_buffactive()
    buffactive = {}
    local p = windower.ffxi.get_player()
    if p and p.buffs then
        for _, buff_id in ipairs(p.buffs) do
            local name = res.buffs[buff_id] and res.buffs[buff_id].english
            buffactive[buff_id] = true
            if name then buffactive[name] = true end
        end
    end
end

-- Function: get_current_weather_element
-- Description: Gets the elemental affinity of the current weather
--   (e.g. "Fire" during a firestorm), used for checking Summoning Pact
--   elemental-match bonuses.
-- Parameters: none
-- Returns: string or nil - the weather's element name, or nil if
--   weather info isn't available or the current weather has no
--   elemental affinity
function get_current_weather_element()
    local info = windower.ffxi.get_info()
    local w = info and res.weather and res.weather[info.weather]
    return w and w.element
end

-- Function: has_item_name
-- Description: Checks whether a specific item (by its localized name)
--   is anywhere in the player's inventory. Depends on the global
--   `language` variable (set in skillup.lua) to resolve the correct
--   localized item name from res.items.
-- Parameters:
--   name (string) - the localized item name to search for, e.g.
--     "Toolbag (Cho)" or "Fish Mithkabob"
-- Returns: boolean - true if at least one matching item is in inventory
function has_item_name(name)
    if not name then return false end
    local items = windower.ffxi.get_items()
    if not items or not items.inventory then return false end
    for _, slot in pairs(items.inventory) do
        if slot and slot.id and slot.id ~= 0 then
            local res_item = res.items[slot.id]
            local item_name = res_item and (res_item[language] or res_item.en or res_item.english)
            if item_name == name then
                return true
            end
        end
    end
    return false
end

-- Function: trust_already_present
-- Description: Checks whether a party member with the given name is
--   currently present -- used to detect an already-summoned Trust
--   before trying to summon it again (Trusts occupy regular party
--   slots, not the pet_index pet slot, so pet_is_valid() can't see
--   them).
-- Parameters:
--   name (string) - the Trust's in-game name, e.g. "Moogle"
-- Returns: boolean - true if a party slot (p1-p5) currently holds a
--   live member with that name
function trust_already_present(name)
    local pt = windower.ffxi.get_party()
    if not pt or not name then return false end
    for i = 1, 5 do
        local member = pt['p'..i]
        if member and member.mob and member.mob.name == name then
            return true
        end
    end
    return false
end

-- Function: has_rdm_sub
-- Description: Checks whether the player has Red Mage as their
--   sub job at a high enough level to access Refresh (level 41+).
-- Parameters: none
-- Returns: boolean - true if RDM sub job level is 41 or higher
function has_rdm_sub()
    return windower.ffxi.get_player().sub_job == 'RDM' and windower.ffxi.get_player().sub_job_level >= 41
end

-- Function: has_haste_sub
-- Description: Checks whether the player's sub job can cast Haste
--   (Red Mage or White Mage).
-- Parameters: none
-- Returns: boolean - true if sub job is RDM or WHM
function has_haste_sub()
    return windower.ffxi.get_player().sub_job == 'RDM' or windower.ffxi.get_player().sub_job == 'WHM'
end