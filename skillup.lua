_addon.name = 'SkillUp'
_addon.author = 'Aryden'
_addon.version = '0.0.1.0'
_addon.commands = {'skillup', 'su'}

packets = require('packets')
res = require 'resources'
texts = require('texts')
images = require('images')

-- Player-configurable options (spell whitelists, MP-WS threshold, etc.)
-- now live per-character at data/<character>/settings.lua, loaded via
-- load_user_settings() at 'load' time (see get_sets()) rather than
-- require()'d here -- require() resolves at parse time, before the
-- character name is known, so it can't build a per-character path.

language = 'en'
skill_packet_log_count = 0

-- Blue Magic shield spells skill up via their linked job ability
-- (Convergence/Diffusion) rather than being cast directly. 
BLUE_SHIELD_SPELL_JA = {['Harden Shell']=737,['Pyric Bulwark']=741,['Carcharian Verve']=745}

-- Item IDs used for the "Use Skill Up Item" toggle. Also relocated
-- unchanged from the original file.
SKILL_UP_ITEM_IDS = T{5889,5890,5891,5892}

-- ============================================================
-- Menu (built into the Main tab of the always-on settings UI)
-- ============================================================
ICON_DIR = 'icons/'  -- asset folder for background.png (used for panel backdrops)

-- The 11 skill-up categories, as plain button data.
CATEGORY_BUTTON_DEFS = {
    {id='HEL', command='start Healing',    label="Start Healing Magic"},
    {id='ENH', command='start Enhancing',  label="Start Enhancing Magic"},
    {id='NIN', command='start Ninjutsu',   label="Start Ninjutsu"},
    {id='SIN', command='start Singing',    label="Start Singing"},
    {id='BLU', command='start Blue',       label="Start Blue Magic"},
    {id='SMN', command='start Summoning',  label="Start Summoning Magic"},
    {id='GEO', command='start Geomancy',   label="Start Geomancy"},
    {id='ELE', command='start Elemental',  label="Start Elemental Magic"},
    {id='DRK', command='start Dark',       label="Start Dark Magic"},
    {id='DIV', command='start Divine',     label="Start Divine Magic"},
    {id='ENF', command='start Enfeebling', label="Start Enfeebling Magic"},
}

TOGGLE_BUTTON_DEFS = {
    {id='STOP',       label="Stop Skillups",            command='skillstop'},
    {id='TESTMODE',   label="Test Mode (Ignore Cap)",   command='settestmode'},
}

function find_toggle_def(id)
    for _, def in ipairs(TOGGLE_BUTTON_DEFS) do
        if def.id == id then return def end
    end
end

-- The Main tab's left-column menu: every category plus Stop/Test Mode, as
-- plain button entries. `false` entries are non-interactive divider rows.
function main_menu_layout()
    local layout = L{}
    for _, def in ipairs(CATEGORY_BUTTON_DEFS) do
        layout:append(def)
    end
    layout:append(false)
    layout:append(find_toggle_def('STOP'))
    layout:append(false)
    layout:append(find_toggle_def('TESTMODE'))
    return layout
end

function get_own_mob()
    local p = windower.ffxi.get_player()
    return p and windower.ffxi.get_mob_by_index(p.index)
end

function get_player_status_string()
    local p = windower.ffxi.get_player()
    local st = p and res.statuses[p.status]
    return st and (st.english or st.en) or nil
end

function get_pet_mob()
    local me = get_own_mob()
    if not me or not me.pet_index or me.pet_index == 0 then return nil end
    return windower.ffxi.get_mob_by_index(me.pet_index)
end
function pet_is_valid()
    local pet_mob = get_pet_mob()
    return pet_mob ~= nil and pet_mob.valid_target
end

function get_party_count()
    local pt = windower.ffxi.get_party()
    local count = 1
    if pt then
        for i = 1, 5 do
            if pt['p'..i] then count = count + 1 end
        end
    end
    return count
end

buffactive = {}
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
windower.register_event('gain buff', function(buff_id)
    local name = res.buffs[buff_id] and res.buffs[buff_id].english
    buffactive[buff_id] = true
    if name then buffactive[name] = true end
end)
windower.register_event('lose buff', function(buff_id)
    local name = res.buffs[buff_id] and res.buffs[buff_id].english
    buffactive[buff_id] = nil
    if name then buffactive[name] = nil end
end)

function get_current_weather_element()
    local info = windower.ffxi.get_info()
    local w = info and res.weather and res.weather[info.weather]
    return w and w.element
end

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

function get_sets()
    load_user_settings()
    skilluprun = false
    gs_skill = {skillup_table = {"Healing","Geomancy","Enhancing","Ninjutsu","Singing","Blue","Summoning","Elemental","Dark","Divine","Enfeebling"},skillup_type = 'None',skillup_spells = T{},skillup_target = T{},skillup_party_ok = T{},
        skillup_count=1,party_cycle_index=0,last_cast_target=nil}
    local init_use_trust = (user_settings.use_trust ~= nil) and user_settings.use_trust or false
    local init_use_geo = (user_settings.use_geo ~= nil) and user_settings.use_geo or false
    local init_use_item = (user_settings.use_item ~= nil) and user_settings.use_item or false
    local init_use_mp_ws = (user_settings.use_mp_ws ~= nil) and user_settings.use_mp_ws or false
    local init_use_offensive = (user_settings.use_offensive ~= nil) and user_settings.use_offensive or false
    local init_require_engaged = (user_settings.require_engaged ~= nil) and user_settings.require_engaged or (user_settings.require_engaged == nil)
    local init_track_wind = (user_settings.track_wind_instrument ~= nil) and user_settings.track_wind_instrument or (user_settings.track_wind_instrument == nil)
    local init_track_string = (user_settings.track_string_instrument ~= nil) and user_settings.track_string_instrument or (user_settings.track_string_instrument == nil)
    local init_use_toolbags = (user_settings.use_toolbags ~= nil) and user_settings.use_toolbags or false
    local init_periodic_ui_refresh = (user_settings.periodic_ui_refresh ~= nil) and user_settings.periodic_ui_refresh or false
    gs_skillup = {color={GEO=true,HEL=true,ENH=true,NIN=true,SIN=true,BLU=true,SMN=true,STOP=true,ELE=true,DRK=true,DIV=true,ENF=true,TESTMODE=true},
                skill_ups={},total_skill_ups=0,skill={},use_trust=init_use_trust,use_item=init_use_item,use_geo=init_use_geo,use_mp_ws=init_use_mp_ws,use_offensive=init_use_offensive,require_engaged=init_require_engaged,track_wind_instrument=init_track_wind,track_string_instrument=init_track_string,use_toolbags=init_use_toolbags,periodic_ui_refresh=init_periodic_ui_refresh,test_mode=false,skipped_spells=T{},debug_action_msg=false,debug_action_capture=false,skill_ph_cache=0,skill_ph_last_update=0,last_missing_msg_time=0,resting_recovery_sent=false}

    ensure_spell_library_loaded()
    init_settings_selection()
    settings_state.active_main = SETTINGS_MAIN_TABS[1]  -- "Main"

    local screen = windower.get_windower_settings()
    if screen then
        settings_origin_x = math.max(20, (screen.x_res - 750) / 2)
        settings_origin_y = math.max(20, (screen.y_res - 400) / 2)
    end

    pcall(dofile, windower.addon_path..'data/'..windower.ffxi.get_player().name..'/Saves/skillup_data.lua')

    create_settings_ui()
end
function file_unload()
    if user_settings.save_settings then
        file_write()
    end
    destroy_settings_ui()
end
windower.register_event('load', function()
    get_sets()
    rebuild_buffactive()
end)

windower.register_event('unload', function()
    file_unload()
end)

windower.register_event('addon command', function(...)
    local command = table.concat({...}, ' ')
    self_command(command)
end)

pending_cast = {
    active = false,
    cast_type = nil,   -- 'spell' | 'ja' | 'ws' | 'item'
    name = nil,
    target = nil,
    sent_time = nil,
    saw_start = false,  -- category-8 'starts casting' seen for this cast (spells only, confirmed empirically)
}

function begin_pending_cast(cast_type, name, target)
    pending_cast.active = true
    pending_cast.cast_type = cast_type
    pending_cast.name = name
    pending_cast.target = target
    pending_cast.sent_time = os.clock()
    pending_cast.saw_start = false
end

function clear_pending_cast()
    pending_cast.active = false
    pending_cast.cast_type = nil
    pending_cast.name = nil
    pending_cast.target = nil
    pending_cast.sent_time = nil
    pending_cast.saw_start = false
end

-- Dumps a Windower 'action' event table to skillup_debug.log in enough
-- detail to read off the real category and message IDs this server uses.
function dump_action_event(act)
    log_debug_line('=== action event ===')
    log_debug_line('actor_id='..tostring(act.actor_id)..' category='..tostring(act.category)..' param='..tostring(act.param))
    log_debug_line('pending_cast: active='..tostring(pending_cast.active)..' type='..tostring(pending_cast.cast_type)..' name='..tostring(pending_cast.name))
    for ti, t in ipairs(act.targets or {}) do
        log_debug_line('  target['..ti..'] id='..tostring(t.id))
        for ai, a in ipairs(t.actions or {}) do
            log_debug_line('    action['..ai..'] message='..tostring(a.message)..' param='..tostring(a.param)..
                ' add_effect_message='..tostring(a.add_effect_message)..' has_add_effect='..tostring(a.has_add_effect))
        end
    end
end

function handle_cast_success()
    local was_name = pending_cast.name
    local was_type = pending_cast.cast_type
    clear_pending_cast()
    if not skilluprun then return end
    if pet_is_valid() and check_skill_cap() then
        if get_pet_mob() and get_pet_mob().name == "Luopan" then
            cast_ja(345, 1.0)
        else
            cast_ja(90, 1.0)
        end
        return
    end
    if check_skill_cap() then
        shutdown_logoff()
        return
    end
    local spell_res = was_type == 'spell' and get_spell_by_name(was_name)
    if spell_res and spell_res.type == "SummonerPact" then
        local spell_element = (type(spell_res.element)=='number' and res.elements[spell_res.element] and res.elements[spell_res.element][language] or spell_res.element)
        if was_name:contains('Spirit') and spell_element == get_current_weather_element() then
            cast_ja(232, 4.0)
        elseif not was_name:contains('Spirit') then
            cast_ja(250, 4.0)
        else
            cast_ja(90, 3.0)
        end
        return
    end
    if was_name == "Avatar's Favor" or was_name == "Elemental Siphon" then
        cast_ja(90, 1.0)
        return
    end
    advance_skillup_count()
    decide_and_act(3.0)
end

function handle_cast_interrupted()
    local was_name = pending_cast.name
    clear_pending_cast()
    if not skilluprun then return end
    if check_skill_cap() then
        shutdown_logoff()
        return
    end
    if was_name == "Release" then
        cast_ja(90, 0.5)
        return
    elseif skillup_cast_target(was_name) == '<t>' and not offensive_spell_castable() then
        -- Needed a target we no longer have (died mid-cast, offensive
        -- toggle turned off mid-run) -- don't retry it, advance instead.
        advance_and_cast_skillup_spell(3.0)
        return
    elseif party_index_of_target(gs_skill.last_cast_target) and not is_party_member_targetable(party_index_of_target(gs_skill.last_cast_target)) then
        advance_and_cast_skillup_spell(3.0)
        return
    else
        -- Re-run the full decision pipeline instead of blindly retrying
        -- the same spell verbatim. This matters most for MP: GearSwap's
        -- precast() automatically re-ran before every cast attempt,
        -- including retries, so a spell interrupted for insufficient MP
        -- always got another chance to trigger the auto-heal fallback.
        -- Going straight back to cast_named_skillup_spell here skipped
        -- that check entirely, which is why auto-heal stopped happening.
        decide_and_act(3.0)
        return
    end
end

windower.register_event('action', function(act)
    local me = windower.ffxi.get_player()
    if not me or act.actor_id ~= me.id then return end
    if gs_skillup.debug_action_capture then
        windower.add_to_chat(167, 'actioncapture: action event fired, category='..tostring(act.category)..' -- logging to Saves/skillup_debug.log')
        dump_action_event(act)
    end
    if not pending_cast.active or not skilluprun then return end
    if pending_cast.cast_type ~= 'spell' then
        return
    end
    if act.category == 8 then
        if not pending_cast.saw_start then
            pending_cast.saw_start = true
            return
        end
        handle_cast_interrupted()
        return
    elseif act.category == 4 then
        handle_cast_success()
        return
    end
end)

function spell_allowed_by_user_list(v)
    local is_offensive = not v.targets:contains('Self')
    if is_offensive then
        return #user_settings.user_spells.Offensive > 0 and user_settings.user_spells.Offensive:contains(v.name)
    end
    local list = user_settings.user_spells[gs_skill.skillup_type]
    return #list == 0 or list:contains(v.name)
end
function register_skillup_spell(v)
    local name = v[language]
    gs_skill.skillup_spells:append(name)
    gs_skill.skillup_target[name] = v.targets:contains('Self') and '<me>' or '<t>'
    gs_skill.skillup_party_ok[name] = v.targets:contains('Party')
end
function self_command(command)
    local commandArgs = command
    if #commandArgs:split(' ') >= 2 then
        commandArgs = T(commandArgs:split(' '))
    end
    if type(commandArgs) == 'table' and commandArgs[1] == 'start' then
        for i,v in ipairs(gs_skill.skillup_table) do
            if v:lower() == commandArgs[2]:lower() then
                gs_skill.skillup_type = v
                skilluprun = true
                if #gs_skill.skillup_spells > 0 then
                    gs_skill.skillup_spells:clear()
                end
                gs_skill.skillup_target = T{}
                gs_skill.skillup_party_ok = T{}
                gs_skill.party_cycle_index = 0
                gs_skill.skillup_count = 1
                local skill_id = {["Divine"]=32,["Healing"]=33,["Enhancing"]=34,["Enfeebling"]=35,["Elemental"]=36,["Dark"]=37,["Summoning"]=38,["Ninjutsu"]=39,["Singing"]=40,["Blue"]=43,["Geomancy"]=44}
                local spells_have = windower.ffxi.get_spells()
                local missing_spells = T{}
                for i,v in pairs(res.spells) do
                    if v.skill == skill_id[gs_skill.skillup_type] and spell_valid(v) and spell_allowed_by_user_list(v) then
                        if spells_have[v.id] then
                            register_skillup_spell(v)
                        else
                            missing_spells:append(v[language])
                        end
                    end
                end
                if not (#gs_skill.skillup_spells > 0) then
                    if os.clock() - (gs_skillup.last_missing_msg_time or 0) > 2 then
                        gs_skillup.last_missing_msg_time = os.clock()
                        if #missing_spells > 0 then
                            windower.add_to_chat(123, "You do not have the following "..gs_skill.skillup_type.." spell(s): "..missing_spells:concat(', '))
                        end
                        if #user_settings.user_spells[gs_skill.skillup_type] == 0 then
                            windower.add_to_chat(123, "Note: your "..gs_skill.skillup_type.." whitelist (user_spells."..gs_skill.skillup_type..") is empty.")
                        end
                        if #user_settings.user_spells.Offensive == 0 then
                            windower.add_to_chat(123, "Note: your Offensive spell whitelist (user_spells.Offensive) is empty -- required for any category that relies on enemy-targeted spells.")
                        end
                        if #missing_spells == 0 then
                            windower.add_to_chat(123,"Current Job Can Not Use Spells From "..gs_skill.skillup_type)
                        end
                    end
                    skilluprun = false
                    return
                end
                decide_and_act()
            end
        end
    end
    if type(commandArgs) == 'table' and commandArgs[1] == 'setthreshold' then
        local n = tonumber(commandArgs[2])
        if n then
            user_settings.mp_ws_threshold = math.floor(n)
            windower.add_to_chat(123, 'MP Regain WS threshold set to '..tostring(user_settings.mp_ws_threshold))
        end
    end
    if command == "skillstop" then
        skilluprun = false
    elseif command == 'settrust' then
        gs_skillup.use_trust = not gs_skillup.use_trust
    elseif command == 'setitem' then
        gs_skillup.use_item = not gs_skillup.use_item
    elseif command == 'setgeo' then
        gs_skillup.use_geo = not gs_skillup.use_geo
    elseif command == 'setmpws' then
        gs_skillup.use_mp_ws = not gs_skillup.use_mp_ws
    elseif command == 'setoffensive' then
        gs_skillup.use_offensive = not gs_skillup.use_offensive
    elseif command == 'setengaged' then
        gs_skillup.require_engaged = not gs_skillup.require_engaged
    elseif command == 'settrackwind' then
        gs_skillup.track_wind_instrument = not gs_skillup.track_wind_instrument
    elseif command == 'settrackstring' then
        gs_skillup.track_string_instrument = not gs_skillup.track_string_instrument
    elseif command == 'settoolbags' then
        gs_skillup.use_toolbags = not gs_skillup.use_toolbags
    elseif command == 'settestmode' then
        gs_skillup.test_mode = not gs_skillup.test_mode
        windower.add_to_chat(123, 'Test mode (ignore skill cap): '..tostring(gs_skillup.test_mode))
        -- If skillup already auto-stopped from hitting the cap, turning
        -- test mode on wouldn't otherwise do anything visible until the
        -- category was manually restarted -- resume it automatically.
        if gs_skillup.test_mode and not skilluprun and gs_skill.skillup_type ~= 'None' then
            self_command('start '..gs_skill.skillup_type)
        end
    elseif command == 'zfix' then
        gs_skillup.periodic_ui_refresh = not gs_skillup.periodic_ui_refresh
        if gs_skillup.periodic_ui_refresh then
            windower.add_to_chat(123, 'Periodic UI refresh ON -- the panel will rebuild itself every '..UI_REFRESH_INTERVAL..'s to reclaim top render priority if another addon draws over it (Windower has no real z-index control). This causes a brief visible flash each time.')
            last_ui_refresh_time = os.clock()
        else
            windower.add_to_chat(123, 'Periodic UI refresh OFF.')
        end
    elseif command == 'show' then
        show_settings_panel()
    elseif command == 'hide' then
        hide_settings_panel()
    elseif command == 'mpwsdebug' then
        windower.add_to_chat(123, 'use_mp_ws: '..tostring(gs_skillup.use_mp_ws))
        windower.add_to_chat(123, 'windower.ffxi.get_player().vitals.mpp: '..tostring(windower.ffxi.get_player().vitals.mpp)..' (threshold='..tostring(user_settings.mp_ws_threshold)..')')
        windower.add_to_chat(123, 'has_valid_enemy_target: '..tostring(has_valid_enemy_target())..' (status='..tostring(get_player_status_string())..')')
        windower.add_to_chat(123, 'windower.ffxi.get_player().vitals.tp: '..tostring(windower.ffxi.get_player().vitals.tp)..' (need >= 1000)')
        windower.add_to_chat(123, 'main_weapon_skill_type: '..tostring(main_weapon_skill_type())..' | Dagger='..tostring(get_skill_id_by_name('Dagger'))..' Club='..tostring(get_skill_id_by_name('Club'))..' Staff='..tostring(get_skill_id_by_name('Staff')))
        for _,name in ipairs(mp_regain_ws_candidates()) do
            windower.add_to_chat(123, 'weapon_skill_available('..name..'): '..tostring(weapon_skill_available(name)))
        end
        windower.add_to_chat(123, 'get_ready_mp_ws(): '..tostring(get_ready_mp_ws()))
    elseif command == 'partydebug' then
        log_debug_line('=== partydebug ===')
        local pt = windower.ffxi.get_party()
        log_debug_line('windower.ffxi.get_party() exists: '..tostring(pt ~= nil))
        for i = 1, 5 do
            local member = pt and pt['p'..i]
            if member then
                local mob = member.mob
                log_debug_line('p'..i..': name='..tostring(member.name)..' party_hp='..tostring(member.hp)..
                    ' | mob_present='..tostring(mob ~= nil)..' mob_hpp='..tostring(mob and mob.hpp)..' mob_valid_target='..tostring(mob and mob.valid_target)..
                    ' | targetable='..tostring(is_party_member_targetable(i)))
            else
                log_debug_line('p'..i..': (empty slot)')
            end
        end
        local live = get_live_party_targets()
        log_debug_line('get_live_party_targets(): '..tostring(#live)..' found: '..table.concat(live, ', '))
        log_debug_line('party_cycle_index: '..tostring(gs_skill.party_cycle_index))
        local cur_name = gs_skill.skillup_spells[gs_skill.skillup_count]
        log_debug_line('current spell: '..tostring(cur_name)..' | party_ok='..tostring(gs_skill.skillup_party_ok[cur_name])..' | base_target='..tostring(gs_skill.skillup_target[cur_name]))
        log_debug_line('skillup_cast_target(current): '..tostring(skillup_cast_target(cur_name)))
        windower.add_to_chat(123, 'Party debug logged to Saves/skillup_debug.log')
    elseif command == 'skilldebug' then
        log_debug_line('=== skilldebug ===')
        log_debug_line('gs_skillup.skill is nil: '..tostring(gs_skillup.skill == nil))
        if gs_skillup.skill then
            local keys = {}
            for k, v in pairs(gs_skillup.skill) do
                table.insert(keys, tostring(k)..' = '..tostring(v))
            end
            table.sort(keys)
            for _, line in ipairs(keys) do
                log_debug_line(line)
            end
        end
        log_debug_line('current category: '..tostring(gs_skill.skillup_type))
        local expected_key = tostring(gs_skill.skillup_type)..' Magic Level'
        log_debug_line('key this addon looks up: "'..expected_key..'" -> '..tostring(gs_skillup.skill and gs_skillup.skill[expected_key]))
        windower.add_to_chat(123, 'Skill packet dumped to Saves/skillup_debug.log -- compare the field list there against what this addon looks up.')
    elseif command == 'actionmsgdebug' then
        gs_skillup.debug_action_msg = not gs_skillup.debug_action_msg
        windower.add_to_chat(123, 'Action message debug: '..tostring(gs_skillup.debug_action_msg)..'. Logging to Saves/skillup_debug.log -- skill up a spell now, then check that file.')
    elseif command == 'actioncapture' then
        gs_skillup.debug_action_capture = not gs_skillup.debug_action_capture
        windower.add_to_chat(123, 'Action event capture: '..tostring(gs_skillup.debug_action_capture)..'. Logging to Saves/skillup_debug.log -- start a skill-up category, let it cast once (or interrupt one, e.g. by moving), then check that file.')
    end
    updatedisplay()
end
function spell_usable(spell)
    if windower.ffxi.get_spells()[spell.id] and windower.ffxi.get_spell_recasts()[spell.recast_id] == 0 then
        return true
    end
end
function has_rdm_sub()
    return windower.ffxi.get_player().sub_job == 'RDM' and windower.ffxi.get_player().sub_job_level >= 41
end
function has_haste_sub()
    return windower.ffxi.get_player().sub_job == 'RDM' or windower.ffxi.get_player().sub_job == 'WHM'
end
function get_spell_by_name(name)
    for id,v in pairs(res.spells) do
        if v.en == name then
            return v
        end
    end
end
function get_skill_id_by_name(name)
    for id,v in pairs(res.skills) do
        if v.en == name then
            return id
        end
    end
end
-- The combat skill (Dagger, Club, Staff, etc.) of whatever is in the main slot.
function main_weapon_skill_type()
    local equipment = windower.ffxi.get_items().equipment
    local main_index = equipment.main
    if not main_index or main_index == 0 then return nil end
    local item = windower.ffxi.get_items(equipment.main_bag or 0, main_index)
    if not item or item.id == 0 then return nil end
    local item_res = res.items[item.id]
    return item_res and item_res.skill
end
function weapon_skill_available(name)
    local ws_list = windower.ffxi.get_abilities().weapon_skills
    if not ws_list then return false end
    for id,v in pairs(res.weapon_skills) do
        if v.en == name then
            for i,available_id in pairs(ws_list) do
                if available_id == id then
                    return true
                end
            end
        end
    end
    return false
end
function use_weapon_skill(name, target)
    if windower.ffxi.get_player().vitals.tp < 1000 then
        return
    end
    gs_skill.skillup_target[name] = target or '<t>'
    begin_pending_cast('ws', name, target or '<t>')
    windower.send_command(action_prefix()..' /ws "'..name..'" '..(target or '<t>'))
end
function mp_regain_ws_candidates()
    local skill_type = main_weapon_skill_type()
    if skill_type == get_skill_id_by_name('Dagger') then
        return {'Energy Drain', 'Energy Steal'}
    elseif skill_type == get_skill_id_by_name('Club') then
        return {'Mystic Boon', 'Starlight', 'Moonlight'}
    elseif skill_type == get_skill_id_by_name('Staff') then
        return {'Spirit Taker'}
    end
    return {}
end
function get_ready_mp_ws()
    if not gs_skillup.use_mp_ws then return nil end
    if windower.ffxi.get_player().vitals.mpp > user_settings.mp_ws_threshold then return nil end
    if not has_valid_enemy_target() then return nil end
    if windower.ffxi.get_player().vitals.tp < 1000 then return nil end
    for _,name in ipairs(mp_regain_ws_candidates()) do
        if weapon_skill_available(name) then
            return name
        end
    end
    return nil
end
-- The skill packet marks "Capped=true" even for skills sitting at
-- Level=0 (untouched/inactive for the current job setup) -- confirmed
-- via live packet dump (Blue Magic, Geomancy, Singing, Handbell, and
-- both instrument skills all showed Capped=true at Level=0). A level-0
-- skill can't be genuinely capped, so trusting Capped alone made
-- check_skill_cap() stop a freshly-started category immediately, before
-- ever attempting a single cast.
function skill_is_genuinely_capped(skill_name)
    local capped = gs_skillup.skill[skill_name..' Capped']
    local level = gs_skillup.skill[skill_name..' Level'] or 0
    return capped and level > 0
end

function check_skill_cap()
    if S{'Healing','Enhancing','Blue','Summoning','Elemental','Dark','Divine','Enfeebling'}:contains(gs_skill.skillup_type) then
        if skill_is_genuinely_capped(gs_skill.skillup_type..' Magic') and not gs_skillup.test_mode then
            skilluprun = false
            return true
        end
    elseif gs_skill.skillup_type == "Ninjutsu" then
        if skill_is_genuinely_capped(gs_skill.skillup_type) and not gs_skillup.test_mode then
            skilluprun = false
            return true
        end
    elseif gs_skill.skillup_type == "Geomancy" then
        if skill_is_genuinely_capped('Geomancy') and skill_is_genuinely_capped('Handbell') and not gs_skillup.test_mode then
            skilluprun = false
            return true
        end
    elseif gs_skill.skillup_type == "Singing" then
        local wind_ok = not gs_skillup.track_wind_instrument or skill_is_genuinely_capped('Wind Instrument')
        local string_ok = not gs_skillup.track_string_instrument or skill_is_genuinely_capped('Stringed Instrument')
        if skill_is_genuinely_capped('Singing') and wind_ok and string_ok and not gs_skillup.test_mode then
            skilluprun = false
            return true
        end
    else
        return false
    end
end
function spell_valid(tab)
    local valid_target = tab.targets:contains('Self') or (gs_skillup.use_offensive and tab.targets:contains('Enemy'))
    if (tab.levels[windower.ffxi.get_player().main_job_id] and tab.levels[windower.ffxi.get_player().main_job_id] <= windower.ffxi.get_player().main_job_level or tab.levels[windower.ffxi.get_player().sub_job_id] and tab.levels[windower.ffxi.get_player().sub_job_id] <= windower.ffxi.get_player().main_job_level) and valid_target and
        not tab.en:wmatch('Teleport-*|Warp*|Tractor*|Retrace|Escape|Geo-*|Sacrifice|Odin|Alexander|Recall-*') then
        return true
    end
end
function party_index_of_target(target)
    local idx = target and target:match('^<p(%d)>$')
    return idx and tonumber(idx)
end
function is_party_member_targetable(i)
    local pt = windower.ffxi.get_party()
    local member = pt and pt['p'..i]
    if not member or not member.mob then
        return false
    end
    local mob = member.mob
    if not mob.valid_target then
        return false
    end
    return (mob.hpp == nil) or (mob.hpp > 0)
end
function get_live_party_targets()
    local live = T{}
    for i = 1, 5 do
        if is_party_member_targetable(i) then
            live:append('<p'..i..'>')
        end
    end
    return live
end
function skillup_cast_target(name)
    local base = gs_skill.skillup_target[name] or '<me>'
    if base == '<me>' and gs_skill.skillup_party_ok[name] then
        local party_targets = get_live_party_targets()
        if #party_targets > 0 then
            local idx = (gs_skill.party_cycle_index or 0) % (#party_targets + 1)
            if idx > 0 then
                return party_targets[idx]
            end
        end
    end
    return base
end
function has_valid_enemy_target()
    if windower.ffxi.get_mob_by_target('t') == nil then
        return false
    end
    return (not gs_skillup.require_engaged) or get_player_status_string() == 'Engaged'
end
function offensive_spell_castable()
    return gs_skillup.use_offensive and has_valid_enemy_target()
end
function skip_to_valid_target_spell()
    local attempts = 0
    while skillup_cast_target(gs_skill.skillup_spells[gs_skill.skillup_count]) == '<t>'
        and not offensive_spell_castable()
        and attempts < #gs_skill.skillup_spells do
        gs_skill.skillup_count = (gs_skill.skillup_count % #gs_skill.skillup_spells) + 1
        attempts = attempts + 1
    end
end
MIN_ACTION_DELAY = 0.2
function action_prefix(wait_time)
    wait_time = math.max(wait_time or 0, MIN_ACTION_DELAY)
    return 'wait '..wait_time..';input'
end
function cast_ja(id, wait_time)
    local name = res.job_abilities[id][language]
    begin_pending_cast('ja', name, '<me>')
    windower.send_command(action_prefix(wait_time)..' /ja "'..name..'" <me>')
end
function cast_self_spell(spell_tab)
    local name = spell_tab[language]
    begin_pending_cast('spell', name, '<me>')
    windower.send_command(action_prefix()..' /ma "'..name..'" <me>')
end
-- Uses an item on self by its localized name.
function use_self_item(name)
    begin_pending_cast('item', name, '<me>')
    windower.send_command(action_prefix()..' /item "'..name..'" <me>')
end

function decide_and_act(wait_time)
    if not skilluprun then return end
    if check_skill_cap() then shutdown_logoff() return end

    skip_to_valid_target_spell()
    local upcoming = gs_skill.skillup_spells[gs_skill.skillup_count]

    
    if gs_skill.skillup_type == "Summoning" then
        if not pet_is_valid() then
            if get_player_status_string() ~= 'Engaged' then
                windower.send_command('input /heal on')
            end
            return
        else
            local favor_recast = windower.ffxi.get_ability_recasts()[90]
            local favor_ready = (not favor_recast or favor_recast == 0) and not buffactive["Avatar's Favor"]
            if favor_ready and windower.ffxi.get_player().vitals.mpp <= 75 then
                cast_ja(90, wait_time)
                return
            end
        end
    end

    -- MP Regain WS: fire if ready, instead of the next rotation spell.
    local ready_ws = get_ready_mp_ws()
    if ready_ws then
        use_weapon_skill(ready_ws)
        return
    end

    -- Skip the upcoming rotation spell if we can't afford it, with a
    -- skip-tracking flag so this can't loop forever if every remaining
    -- spell is also too expensive.
    local upcoming_res = upcoming and get_spell_by_name(upcoming)
    if upcoming_res and upcoming_res.mp_cost and (upcoming_res.mp_cost + 25) > windower.ffxi.get_player().vitals.mp then
        if gs_skillup.skipped_spells:contains(upcoming) then
            gs_skillup.skipped_spells:clear()
            if get_player_status_string() ~= 'Engaged' then
                windower.send_command('input /heal on')
            end
            return
        end
        gs_skillup.skipped_spells:append(upcoming)
        advance_and_cast_skillup_spell(wait_time)
        return
    end

    -- Moogle Trust: solo only.
    if gs_skillup.use_trust and get_party_count() == 1 and spell_usable(res.spells[931]) and upcoming ~= "Moogle" then
        cast_self_spell(res.spells[931])
        return
    end

    -- Skill-up item and Geo's Refresh are mutually exclusive (item takes
    -- priority), matching the original file.
    if gs_skillup.use_item and not buffactive[251] then
        for _, item_id in ipairs(SKILL_UP_ITEM_IDS) do
            local res_item = res.items[item_id]
            local item_name = res_item and (res_item[language] or res_item.en or res_item.english)
            if item_name and has_item_name(item_name) then
                use_self_item(item_name)
                return
            end
        end
    elseif gs_skillup.use_geo then
        if windower.ffxi.get_player().main_job == "GEO" and spell_usable(res.spells[800]) and not pet_is_valid() and upcoming ~= "Geo-Refresh" then
            cast_self_spell(res.spells[800])
            return
        elseif windower.ffxi.get_player().sub_job == "GEO" and spell_usable(res.spells[770])
            and buffactive[541] ~= (gs_skillup.use_trust and 2 or 1) and upcoming ~= "Indi-Refresh" then
            cast_self_spell(res.spells[770])
            return
        end
    end

    -- RDM sub auto-Refresh/Haste.
    if has_rdm_sub() then
        local refresh = get_spell_by_name('Refresh')
        if refresh and upcoming ~= 'Refresh' and spell_usable(refresh) and not buffactive['Refresh'] then
            cast_self_spell(refresh)
            return
        end
    end
    if has_haste_sub() then
        local haste = get_spell_by_name('Haste')
        if haste and upcoming ~= 'Haste' and spell_usable(haste) and not buffactive['Haste'] then
            cast_self_spell(haste)
            return
        end
    end

    cast_upcoming_rotation_spell(wait_time)
end

-- Actually casts the current rotation entry, routing Blue Magic shield
-- spells and Ninjutsu through their special handling first 
function cast_upcoming_rotation_spell(wait_time)
    skip_to_valid_target_spell()
    local name = gs_skill.skillup_spells[gs_skill.skillup_count]
    if not name then
        cast_current_skillup_spell(wait_time)
        return
    end
    if BLUE_SHIELD_SPELL_JA[name] then
        if windower.ffxi.get_ability_recasts()[81] and windower.ffxi.get_ability_recasts()[81] == 0 then
            cast_ja(298, wait_time)
        elseif windower.ffxi.get_ability_recasts()[254] and windower.ffxi.get_ability_recasts()[254] == 0 then
            cast_ja(338, wait_time)
        else
            advance_and_cast_skillup_spell(wait_time)
        end
        return
    end
    local spell_res = get_spell_by_name(name)
    if spell_res and spell_res.skill == "Ninjutsu" then
        local status, bag_name = nin_tool_status(name)
        if status == 'cast' then
            cast_current_skillup_spell(wait_time)
        elseif status == 'unpack' then
            windower.add_to_chat(123, 'Opening '..bag_name..' for '..name)
            use_self_item(bag_name)
        else
            windower.add_to_chat(123, 'No tool available for '..name..' -- skipping')
            advance_and_cast_skillup_spell(wait_time)
        end
        return
    end
    cast_current_skillup_spell(wait_time)
end

function cast_current_skillup_spell(wait_time)
    skip_to_valid_target_spell()
    if #gs_skill.skillup_spells == 0 then
        skilluprun = false
        return
    end
    if not gs_skill.skillup_spells[gs_skill.skillup_count] then
        gs_skill.skillup_count = 1
    end
    local target = skillup_cast_target(gs_skill.skillup_spells[gs_skill.skillup_count])
    gs_skill.last_cast_target = target
    begin_pending_cast('spell', gs_skill.skillup_spells[gs_skill.skillup_count], target)
    windower.send_command(action_prefix(wait_time)..' /ma "'..gs_skill.skillup_spells[gs_skill.skillup_count]..'" '..target)
end
function advance_skillup_count()
    gs_skill.skillup_count = (gs_skill.skillup_count % #gs_skill.skillup_spells) + 1
    local name = gs_skill.skillup_spells[gs_skill.skillup_count]
    if gs_skill.skillup_party_ok[name] then
        gs_skill.party_cycle_index = (gs_skill.party_cycle_index or 0) + 1
    end
end
-- Advances the rotation to the next spell, then casts it (see above).
function advance_and_cast_skillup_spell(wait_time)
    advance_skillup_count()
    decide_and_act(wait_time)
end
-- Retries a specific named spell (not necessarily the current rotation index --
-- used when retrying whatever spell was actually interrupted) on its own target.
function shutdown_logoff()
    windower.add_to_chat(123,"Stopping skillup")
    updatedisplay()
end
function nin_tool_status(name)
    local tools = NINJUTSU_TOOL_MAP[name]
    if not tools then
        windower.add_to_chat(123, 'nin_tool_status: no tool data for '..tostring(name)..' -- add a verified entry to NINJUTSU_TOOL_MAP before whitelisting it')
        return 'none'
    end
    local tb = res.items[NINJUTSU_TOOL_ITEM_IDS[tools.primary]] and res.items[NINJUTSU_TOOL_ITEM_IDS[tools.primary]][language]
    local utb = res.items[NINJUTSU_TOOL_ITEM_IDS[tools.universal]] and res.items[NINJUTSU_TOOL_ITEM_IDS[tools.universal]][language]
    if (tb and has_item_name(tb)) or (utb and has_item_name(utb)) then
        return 'cast'
    end
    if not gs_skillup.use_toolbags then
        return 'none'
    end
    local primary_bag = TOOLBAG_MAP[tools.primary]
    local universal_bag = TOOLBAG_MAP[tools.universal]
    if primary_bag and has_item_name(primary_bag) then
        return 'unpack', primary_bag
    elseif universal_bag and has_item_name(universal_bag) then
        return 'unpack', universal_bag
    end
    return 'none'
end
function build_output_status_text()
    local lines = L{}
    if gs_skillup.test_mode then
        lines:append('--TEST MODE--')
    end
    lines:append('--Skill Up--')
    if gs_skillup.use_trust then lines:append('Using Moogle Trust') end
    if gs_skillup.use_geo then lines:append("Using Geo's Refresh") end
    if gs_skillup.use_item then lines:append('Using Skill Up Item') end
    if gs_skillup.use_mp_ws then lines:append('Using MP Regain WS') end
    if gs_skillup.use_offensive then lines:append('Using Offensive Spells') end
    if not gs_skillup.require_engaged then lines:append('Not Requiring Engaged Target') end
    if gs_skillup.test_mode then lines:append('TEST MODE: Skill Cap Ignored') end
    lines:append('')
    lines:append('Mode: '..(gs_skill.skillup_type or 'None'))

    local skill = {
        Healing = (skill_is_genuinely_capped('Healing Magic') and "Capped" or gs_skillup.skill['Healing Magic Level']) or 0,
        Enhancing = (skill_is_genuinely_capped('Enhancing Magic') and "Capped" or gs_skillup.skill['Enhancing Magic Level']) or 0,
        Summoning = (skill_is_genuinely_capped('Summoning Magic') and "Capped" or gs_skillup.skill['Summoning Magic Level']) or 0,
        Ninjutsu = (skill_is_genuinely_capped('Ninjutsu') and "Capped" or gs_skillup.skill['Ninjutsu Level']) or 0,
        Blue = (skill_is_genuinely_capped('Blue Magic') and "Capped" or gs_skillup.skill['Blue Magic Level']) or 0,
        Elemental = (skill_is_genuinely_capped('Elemental Magic') and "Capped" or gs_skillup.skill['Elemental Magic Level']) or 0,
        Dark = (skill_is_genuinely_capped('Dark Magic') and "Capped" or gs_skillup.skill['Dark Magic Level']) or 0,
        Divine = (skill_is_genuinely_capped('Divine Magic') and "Capped" or gs_skillup.skill['Divine Magic Level']) or 0,
        Enfeebling = (skill_is_genuinely_capped('Enfeebling Magic') and "Capped" or gs_skillup.skill['Enfeebling Magic Level']) or 0,
    }

    if gs_skill.skillup_type == 'Singing' then
        lines:append('Singing Skill LVL: '..tostring(skill_is_genuinely_capped('Singing') and "Capped" or (gs_skillup.skill['Singing Level'] or 0)))
        lines:append('String Skill LVL: '..tostring(skill_is_genuinely_capped('Stringed Instrument') and "Capped" or (gs_skillup.skill['Stringed Instrument Level'] or 0)))
        lines:append('Wind Skill LVL: '..tostring(skill_is_genuinely_capped('Wind Instrument') and "Capped" or (gs_skillup.skill['Wind Instrument Level'] or 0)))
    elseif gs_skill.skillup_type == 'Geomancy' then
        lines:append('Geomancy Skill LVL: '..tostring(skill_is_genuinely_capped('Geomancy') and "Capped" or (gs_skillup.skill['Geomancy Level'] or 0)))
        lines:append('Handbell Skill LVL: '..tostring(skill_is_genuinely_capped('Handbell') and "Capped" or (gs_skillup.skill['Handbell Level'] or 0)))
    else
        lines:append('Skilling LVL: '..tostring(skill[gs_skill.skillup_type] or 0))
    end
    lines:append('')
    lines:append('Will Stop When Skillup Done')
    lines:append('Skillup '..(skilluprun and '\\cs(46,204,113)Started\\cr' or '\\cs(231,76,60)Stopped\\cr'))
    if os.clock() - gs_skillup.skill_ph_last_update >= 30 then
        gs_skillup.skill_ph_cache = get_rate(gs_skillup.skill_ups) or 0
        gs_skillup.skill_ph_last_update = os.clock()
    end
    lines:append('Skillups Per Hour \\cs(241,196,15)'..string.format('%.1f', gs_skillup.skill_ph_cache)..'\\cr')
    lines:append('Total Skillups \\cs(241,196,15)'..string.format('%.1f', gs_skillup.total_skill_ups or 0)..'\\cr')
    return lines:concat('\n')
end


function updatedisplay()
    if not settings_state.hidden and settings_state.active_main == "Main" and settings_ui.backdrop and settings_ui.output_window then
        settings_ui.output_window:text(build_output_status_text())
    end
end
function ensure_dir_path(path)
    local accum = nil
    for part in path:gmatch('[^/\\]+') do
        accum = accum and (accum..'/'..part) or part
        if not windower.dir_exists(accum) then
            windower.create_dir(accum)
        end
    end
end

function file_exists(path)
    local f = io.open(path, 'r')
    if f then
        f:close()
        return true
    end
    return false
end

function copy_file(src, dst)
    local sf = io.open(src, 'r')
    if not sf then return false end
    local content = sf:read('*a')
    sf:close()
    local df = io.open(dst, 'w')
    if not df then return false end
    df:write(content)
    df:close()
    return true
end

-- Loads this character's own settings.lua from
-- data/<character>/settings.lua (creating it by copying this addon's
-- root settings.lua as a starting template, the first time this
-- character ever runs the addon). This sets the global user_settings
-- table, same as require('settings') used to.
function load_user_settings()
    local char_name = windower.ffxi.get_player() and windower.ffxi.get_player().name
    local dir = windower.addon_path..'data/'..tostring(char_name)
    local path = dir..'/settings.lua'
    ensure_dir_path(dir)
    if not file_exists(path) then
        if not copy_file(windower.addon_path..'settings.lua', path) then
            windower.add_to_chat(167, 'load_user_settings: failed to seed '..path..' from the template -- check file permissions')
        end
    end
    dofile(path)
end

function file_write()
    ensure_dir_path(windower.addon_path..'data/'..windower.ffxi.get_player().name..'/Saves')
    local file = io.open(windower.addon_path..'data/'..windower.ffxi.get_player().name..'/Saves/skillup_data.lua',"w")
    file:write(
        'settings_origin_x = '..tostring(settings_origin_x)..
        '\nsettings_origin_y = '..tostring(settings_origin_y)..
        '')
    file:close() 
end
-- Manual hit-test against a text object's known padded bounds (the same
-- padding used for the tab highlight rectangles), since inactive tabs no
-- longer have their own background object to hover-test against.
function point_in_padded_bounds(t, x, y, width, height)
    local tx, ty = t:pos()
    return x >= tx - 4 and x <= tx - 4 + width and y >= ty - 2 and y <= ty - 2 + height
end

function set_color(name)
    for i, v in pairs(gs_skillup.color) do
        if i == name then
            gs_skillup.color[i] = false
        else
            gs_skillup.color[i] = true
        end
    end
end

-- Shows a brief confirmation next to Save/Cancel (e.g. "Saved!"),
-- auto-hidden after a few seconds by the prerender check further down.
function show_footer_notice(text, r, g, b)
    if not settings_ui.footer_notice then return end
    settings_ui.footer_notice:text('\\cs('..r..','..g..','..b..')'..text..'\\cr')
    settings_ui.footer_notice:show()
    settings_ui.footer_notice_expire = os.clock() + 2.5
end
function get_rate(tab)
    local t = os.clock()
    local running_total = 0
    local oldest = nil
    for ts,points in pairs(tab) do
        if t - ts > 3600 then
            tab[ts] = nil
        else
            running_total = running_total + points
            if not oldest or ts < oldest then
                oldest = ts
            end
        end
    end
    if not oldest or running_total == 0 then
        return 0
    end
    
    local elapsed = math.max(t - oldest, 1)
    return running_total * (3600 / elapsed)
end
windower.register_event('incoming chunk', function(id, data, modified, injected, blocked)
    if id == 0x062 then
        local ok, packet = pcall(packets.parse, 'incoming', data)
        if not ok then
            log_debug_line('0x062 packets.parse ERROR: '..tostring(packet))
            return
        end
        -- Logs the first several 0x062 packets in full (field names and
        -- values), then stops -- confirms both that the packet actually
        -- arrives and exactly what field names this server's version of
        -- it produces, without spamming the log indefinitely.
        if skill_packet_log_count < 5 then
            skill_packet_log_count = skill_packet_log_count + 1
            local count = 0
            for _ in pairs(packet or {}) do count = count + 1 end
            log_debug_line('0x062 received (#'..skill_packet_log_count..'): parsed '..tostring(count)..' fields')
            local keys = {}
            for k, v in pairs(packet or {}) do
                table.insert(keys, tostring(k)..' = '..tostring(v))
            end
            table.sort(keys)
            for _, line in ipairs(keys) do
                log_debug_line('  '..line)
            end
        end
        gs_skillup.skill = packet
        updatedisplay()
    end
end)
-- ============================================================
-- Settings window (spell picker)
-- ============================================================
-- Loads libs/spell_library.lua 
SETTINGS_MAIN_TABS = {"Main","Globals","Healing","Geomancy","Enhancing","Ninjutsu","Singing","Blue","Summoning","Elemental","Dark","Divine","Enfeebling","Help"}
SETTINGS_TAB_GAP = 20   -- gap between tabs (uniform width = largest tab)
SETTINGS_COL_GAP = 24   -- gap between grid columns, laid out by estimated width

-- Globals tab: simple boolean toggles 
GLOBAL_TOGGLE_DEFS = {
    {id='TRUST', label="Use Moogle Trust",          command='settrust',      field='use_trust'},
    {id='REF',   label="Use Geo's Refresh",         command='setgeo',        field='use_geo'},
    {id='ITEM',  label="Use Skill Up Item",         command='setitem',       field='use_item'},
    {id='MPWS',  label="Use MP Regain WS",          command='setmpws',       field='use_mp_ws'},
    {id='OFF',   label="Use Offensive Spells",      command='setoffensive',  field='use_offensive'},
    {id='ENG',   label="Require Engaged Target",    command='setengaged',    field='require_engaged'},
}
-- Radio-button style options for MP Regain WS threshold: 5, then 10-100
-- by 10s. Selecting one calls 'setthreshold <value>' directly.
MP_WS_THRESHOLD_OPTIONS = {5, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100}
-- Windower has no z-index/render-priority API -- render order across
-- ALL addons is purely "whoever created their primitives most recently
-- draws on top", global and out of any single addon's control. Rebuilding
-- our own UI periodically is the only way to reclaim top priority if
-- another addon draws over it later. Opt-in (see 'zfix' command) since
-- it causes a brief visible flash each time it runs.
UI_REFRESH_INTERVAL = 45
-- Which instrument skill(s) gate Singing's stop condition. Both default
-- true (matches the original always-require-all-3 behavior). Unchecking
-- one means check_skill_cap() no longer waits on that instrument.
SINGING_TRACK_DEFS = {
    {id='TRACKWIND',   label="Track Wind Instrument",   command='settrackwind',   field='track_wind_instrument'},
    {id='TRACKSTRING', label="Track String Instrument", command='settrackstring', field='track_string_instrument'},
}

-- Help tab content -- covers every entry in the menu. {title, text} pairs,
-- rendered as two lines each (title in gold, description plain).
HELP_ENTRIES = {
    {title="-- Main tab --", text=""},
    {title="Start Healing/Enhancing/etc.", text="Begins the skill-up rotation for that"},
    {title="", text="magic type, using the spells checked"},
    {title="Stop Skillups", text="Stops skillups after the current rotation."},
    {title="Test Mode (Ignore Cap)", text="Ignores the skill cap so skillup keeps"},
    {title="", text="running past capping. For testing only."},

    {title="-- Globals tab --", text=""},
    {title="Use Moogle Trust", text="Summons Moogle to assist."},
    {title="Use Geo's Refresh", text="Casts Geo-Refresh (main GEO) or"},
    {title="", text="Indi-Refresh (sub GEO) to help with MP."},
    {title="Use Skill Up Item", text="Uses a configured skill-up item if"},
    {title="", text="in inventory and not already active."},
    {title="Use MP Regain WS", text="Fires an MP-restoring weapon skill"},
    {title="", text="(Energy Drain, Spirit Taker, etc.) once"},
    {title="", text="MP drops to the threshold below."},
    {title="MP Regain WS Threshold", text="MP% at/below which the WS fires."},
    {title="", text="Only shown when MP Regain WS is on."},
    {title="Use Offensive Spells", text="Allows enemy-targeted spells from your"},
    {title="", text="Offensive whitelist (in settings.lua)."},
    {title="Require Engaged Target", text="Requires combat before offensive"},
    {title="", text="spells/weapon skills are used."},

    {title="-- Ninjutsu tab --", text=""},
    {title="Allow Ninja Tool Toolbag Use", text="If the tool isn't in your"},
    {title="", text="inventory, allows opening a Toolbag to"},
    {title="", text="unpack it instead, when one's available. Primary tools"},
    {title="", text="are tried first, then MLVL universal tools"},

    {title="-- Singing tab --", text=""},
    {title="Track Wind/String Instrument", text="Which instrument skill(s) must cap"},
    {title="", text="before Singing stops. Skillup does NOT"},
    {title="", text="auto-swap instruments -- equip the one"},
    {title="", text="you're tracking yourself."},

    {title="-- Every category tab --", text=""},
    {title="Checkboxes", text="Check any spells you want in the"},
    {title="", text="rotation. Saved per character."},
    {title="Save", text="Writes ALL tabs' selections to"},
    {title="", text="settings.lua. Restarts skillup with the"},
    {title="", text="new list if it was already running."},
    {title="Cancel", text="Discards unsaved changes on this visit"},
    {title="", text="and reloads the last-saved selections."},

    {title="-- Panel --", text=""},
    {title="[X] button", text="Hides the whole panel."},
    {title="//skillup show", text="Shows the panel again if hidden."},
    {title="//skillup hide", text="Hides the panel (same as [X])."},
    {title="//skillup zfix", text="Windower has no real z-index control."},
    {title="", text="Toggles periodically rebuilding the panel so"},
    {title="", text="it reclaims top priority if another addon"},
    {title="", text="draws over it. Off by default -- causes a"},
    {title="", text="brief visible flash each time it runs."},
}
-- Halved from the original 22 -- blank-line padding between rows roughly
-- doubles each column's actual rendered height, so this keeps total
-- column height in the same ballpark as before the padding was added.
SETTINGS_MAX_ROWS = 12
SETTINGS_PAD = 18
-- This is now the ONE persistent panel's position -- always visible,
-- draggable via the title bar, and saved/restored across sessions like
-- the old window position was.
settings_origin_x = 20
settings_origin_y = 20

settings_state = {
    library = nil,       
    selection = {},       -- selection[category][spell_name] = true
    active_main = SETTINGS_MAIN_TABS[1],
    active_sub = nil,
    hidden = false,
}
settings_ui = {
    content_right = 0,  -- real default so rebuild_settings_grid() never sees nil, even if called before create_settings_ui() has run
    border = nil,
    backdrop = nil,
    header_panel = nil,
    sep_tabs = nil,
    sep_subtabs = nil,
    sep_footer = nil,
    title = nil,
    output_window = nil,  -- persistent Main-tab status display, updated in place (not rebuilt) to avoid flicker
    hide_button = nil,
    footer_notice = nil,
    footer_notice_expire = nil,
    main_tabs = {},      -- category -> texts object
    main_tab_highlight = nil,  -- single image, moved behind whichever main tab is active
    main_tab_highlight_w = 0,
    main_tab_highlight_h = 0,
    sub_tabs = {},        -- sub_name -> texts object (rebuilt per active_main)
    sub_tab_highlight = nil,  -- single image, moved/resized behind whichever sub-tab is active
    sub_tab_width = 0,
    sub_tab_height = 0,
    singing_options = nil, -- {wind=, string=, note=} texts objects, only when Singing is active
    ninjutsu_options = nil, -- {toolbags=, note=} texts objects, only when Ninjutsu is active
    columns = {},          -- list of texts objects (rebuilt per active_main/active_sub)
    column_data = {},      -- parallel list of spell-entry-lists, for hit-testing
    save_button = nil,
    cancel_button = nil,
}

-- Estimates rendered text width/height from character count rather than
-- texts.extents() 
function estimate_text_size(str, font_size)
    local visible = str:gsub('\\cs%(%d+,%d+,%d+%)', ''):gsub('\\cr', '')
    local longest = 0
    local line_count = 0
    for line in (visible..'\n'):gmatch('([^\n]*)\n') do
        line_count = line_count + 1
        if #line > longest then longest = #line end
    end
    local width = longest * font_size * 0.9 + 20
    local height = math.max(line_count, 1) * font_size * 2.0
    return width, height
end

-- Keeps the panel on-screen. Called whenever it's dragged.
function clamp_panel_position(x, y)
    local screen = windower.get_windower_settings()
    if not screen then return x, y end
    local x_max = math.max(0, screen.x_res - 200)
    local y_max = math.max(0, screen.y_res - 200)
    x = math.min(math.max(x, 0), x_max)
    y = math.min(math.max(y, 0), y_max)
    return x, y
end

function ensure_spell_library_loaded()
    if not build_spell_library then
        dofile(windower.addon_path..'libs/spell_library.lua')
    end
    if not settings_state.library then
        settings_state.library = build_spell_library()
    end
end

function init_settings_selection()
    settings_state.selection = {}
    for _, category in ipairs(SETTINGS_MAIN_TABS) do
        if category ~= "Globals" and category ~= "Main" and category ~= "Help" then
            settings_state.selection[category] = {}
            local list = user_settings.user_spells[category]
            if list then
                for _, name in ipairs(list) do
                    settings_state.selection[category][name] = true
                end
            end
        end
    end
end

function destroy_settings_ui()
    if settings_ui.border then settings_ui.border:destroy() end
    if settings_ui.backdrop then settings_ui.backdrop:destroy() end
    if settings_ui.header_panel then settings_ui.header_panel:destroy() end
    if settings_ui.sep_tabs then settings_ui.sep_tabs:destroy() end
    if settings_ui.sep_subtabs then settings_ui.sep_subtabs:destroy() end
    if settings_ui.sep_footer then settings_ui.sep_footer:destroy() end
    if settings_ui.title then settings_ui.title:destroy() end
    if settings_ui.output_window then settings_ui.output_window:destroy() end
    if settings_ui.hide_button then settings_ui.hide_button:destroy() end
    for _, t in pairs(settings_ui.main_tabs) do t:destroy() end
    if settings_ui.main_tab_highlight then settings_ui.main_tab_highlight:destroy() end
    for _, t in pairs(settings_ui.sub_tabs) do t:destroy() end
    if settings_ui.sub_tab_highlight then settings_ui.sub_tab_highlight:destroy() end
    if settings_ui.singing_options then
        for _, t in pairs(settings_ui.singing_options) do t:destroy() end
    end
    if settings_ui.ninjutsu_options then
        for _, t in pairs(settings_ui.ninjutsu_options) do t:destroy() end
    end
    for _, t in ipairs(settings_ui.columns) do t:destroy() end
    if settings_ui.save_button then settings_ui.save_button:destroy() end
    if settings_ui.footer_notice then settings_ui.footer_notice:destroy() end
    if settings_ui.cancel_button then settings_ui.cancel_button:destroy() end
    settings_ui = {content_right=0, border=nil, backdrop=nil, header_panel=nil, sep_tabs=nil, sep_subtabs=nil, sep_footer=nil, title=nil, output_window=nil, hide_button=nil, main_tabs={}, main_tab_highlight=nil, sub_tabs={}, sub_tab_highlight=nil, singing_options=nil, ninjutsu_options=nil, columns={}, column_data={}, save_button=nil, cancel_button=nil}
end

function sorted_sub_tab_names(category)
    local names = {}
    for sub_name, _ in pairs(settings_state.library[category]) do
        table.insert(names, sub_name)
    end
    table.sort(names, function(a, b)
        if a == "Other" then return false end
        if b == "Other" then return true end
        return a < b
    end)
    return names
end

-- Resizes the backdrop draw-box to contain whatever's currently on
-- screen (main tabs, sub tabs, and however many grid columns there are).
-- Sizes/positions the backdrop to actually contain everything currently
-- on screen, computed from real measured positions/extents of every
-- element 
function resize_settings_backdrop()
    local bx = settings_origin_x - SETTINGS_PAD
    local by = settings_origin_y - SETTINGS_PAD
    local width = (settings_ui.content_right - settings_origin_x) + SETTINGS_PAD*2
    local height = (settings_ui.footer_bottom_y - settings_origin_y) + SETTINGS_PAD*2

    settings_ui.border:pos(bx - 3, by - 3)
    settings_ui.border:size(width + 6, height + 6)

    settings_ui.backdrop:pos(bx, by)
    settings_ui.backdrop:size(width, height)

    -- Header shading covers title + tab rows, stopping just before the
    -- first separator line -- a lighter band across the top of the panel.
    local header_h = (settings_ui.tabs_y + settings_ui.tab_row_h) - settings_origin_y + SETTINGS_PAD
    settings_ui.header_panel:pos(bx, by)
    settings_ui.header_panel:size(width, header_h)

    settings_ui.sep_tabs:pos(bx, settings_ui.tabs_y + settings_ui.tab_row_h + 3)
    settings_ui.sep_tabs:size(width, 2)

    settings_ui.sep_subtabs:pos(bx, settings_ui.subtabs_bottom_y - 6)
    settings_ui.sep_subtabs:size(width, 2)

    settings_ui.sep_footer:pos(bx, settings_ui.grid_bottom_y + 14)
    settings_ui.sep_footer:size(width, 2)

    -- Hide button, top-right corner, aligned with the title's row.
    if settings_ui.hide_button then
        local hide_w = estimate_text_size('[X]', 13)
        settings_ui.hide_button:pos(bx + width - hide_w - 4, settings_origin_y)
    end
end

-- Positions Save/Cancel just below the grid's bottom edge, and records
-- where the content ends for resize_settings_backdrop.
function position_settings_footer()
    local footer_y = settings_ui.grid_bottom_y + 28
    local save_w, save_h = estimate_text_size('[ Save ]', 13)
    settings_ui.save_button:pos(settings_origin_x, footer_y)
    local cancel_x = settings_origin_x + save_w + 30
    local cancel_w, cancel_h = estimate_text_size('[ Cancel ]', 13)
    settings_ui.cancel_button:pos(cancel_x, footer_y)
    local notice_x = cancel_x + cancel_w + 20
    settings_ui.footer_notice:pos(notice_x, footer_y)
    settings_ui.content_right = math.max(settings_ui.content_right, notice_x + 100, cancel_x + cancel_w)
    settings_ui.footer_bottom_y = footer_y + math.max(save_h, cancel_h)
end

function rebuild_settings_grid()
    for _, t in ipairs(settings_ui.columns) do t:destroy() end
    settings_ui.columns = {}
    settings_ui.column_data = {}
    local grid_y = settings_ui.subtabs_bottom_y
    if settings_ui.output_window then settings_ui.output_window:hide() end

    if settings_state.active_main == "Main" then
        -- Left column: the menu (categories + Stop/Test Mode), clickable.
        local menu_lines = L{}
        local menu_entries = {}
        for _, entry in ipairs(main_menu_layout()) do
            if entry then
                local label = (gs_skillup.color[entry.id] and entry.label) or ('\\cs(94,160,255)'..entry.label..'\\cr')
                menu_lines:append(label)
                menu_entries[#menu_entries+1] = entry
            else
                menu_lines:append('\\cs(100,100,100)------------------------\\cr')
                menu_entries[#menu_entries+1] = {command=nil}
            end
            menu_lines:append('')
            menu_entries[#menu_entries+1] = {command=nil}
        end
        local menu_text = menu_lines:concat('\n')
        local menu_t = texts.new({
            pos = {x = settings_origin_x, y = grid_y},
            text = {font='Segoe UI Symbol', size=11},
            bg = {alpha=0},
            flags = {draggable=false},
        })
        menu_t:text(menu_text)
        menu_t:show()
        table.insert(settings_ui.columns, menu_t)
        table.insert(settings_ui.column_data, menu_entries)
        local menu_w, menu_h = estimate_text_size(menu_text, 11)

        -- Right side: read-only status output. Persistent object, updated
        -- via :text() only 
        local output_text = build_output_status_text()
        local output_x = settings_origin_x + menu_w + SETTINGS_COL_GAP
        settings_ui.output_window:pos(output_x, grid_y)
        settings_ui.output_window:text(output_text)
        settings_ui.output_window:show()
        local output_w, output_h = estimate_text_size(output_text, 11)

        settings_ui.content_right = math.max(settings_ui.content_right, output_x + output_w)
        settings_ui.grid_bottom_y = grid_y + math.max(menu_h, output_h)
        position_settings_footer()
        resize_settings_backdrop()
        return
    end

    if settings_state.active_main == "Help" then
        local rows_per_col = 20
        local num_cols = math.max(1, math.ceil(#HELP_ENTRIES / rows_per_col))
        local col_x = settings_origin_x
        local max_col_h = 0
        for col = 1, num_cols do
            local lines = L{}
            local has_content = false
            for row = 1, rows_per_col do
                local idx = (col-1)*rows_per_col + row
                local entry = HELP_ENTRIES[idx]
                if entry then
                    has_content = true
                    if entry.title ~= "" and entry.text ~= "" then
                        lines:append('\\cs(220,180,80)'..entry.title..'\\cr: '..entry.text)
                    elseif entry.title ~= "" then
                        lines:append('\\cs(94,160,255)'..entry.title..'\\cr')
                    else
                        lines:append('   '..entry.text)
                    end
                end
            end
            if has_content then
                local text_str = lines:concat('\n')
                local t = texts.new({
                    pos = {x = col_x, y = grid_y},
                    text = {font='Segoe UI Symbol', size=10},
                    bg = {alpha=0},
                    flags = {draggable=false},
                })
                t:text(text_str)
                t:show()
                table.insert(settings_ui.columns, t)
                table.insert(settings_ui.column_data, {})  -- not clickable
                local w, h = estimate_text_size(text_str, 10)
                max_col_h = math.max(max_col_h, h)
                col_x = col_x + w + SETTINGS_COL_GAP
            end
        end
        settings_ui.content_right = math.max(settings_ui.content_right, col_x - SETTINGS_COL_GAP)
        settings_ui.grid_bottom_y = grid_y + max_col_h
        position_settings_footer()
        resize_settings_backdrop()
        return
    end

    if settings_state.active_main == "Globals" then
        local lines = L{}
        local entries = {}
        for _, def in ipairs(GLOBAL_TOGGLE_DEFS) do
            local checked = gs_skillup[def.field]
            lines:append(checked and ('\\cs(46,204,113)[✓] '..def.label..'\\cr') or ('[ ] '..def.label))
            table.insert(entries, def)
            lines:append('')
            table.insert(entries, {command=nil})
        end
        if gs_skillup.use_mp_ws then
            lines:append('')
            table.insert(entries, {command=nil})
            lines:append('\\cs(150,155,165)MP Regain WS Threshold -- with "Use MP Regain WS" on, fires the ready weapon skill once your MP% drops to or below this value:\\cr')
            table.insert(entries, {command=nil})
            for _, val in ipairs(MP_WS_THRESHOLD_OPTIONS) do
                local selected = (user_settings.mp_ws_threshold == val)
                lines:append(selected and ('\\cs(46,204,113)(o) '..tostring(val)..'\\cr') or ('( ) '..tostring(val)))
                table.insert(entries, {command='setthreshold '..tostring(val)})
                lines:append('')
                table.insert(entries, {command=nil})
            end
        end
        local text_str = lines:concat('\n')
        local t = texts.new({
            pos = {x = settings_origin_x, y = grid_y},
            text = {font='Segoe UI Symbol', size=11},
            bg = {alpha=0},
            flags = {draggable=false},
        })
        t:text(text_str)
        t:show()
        table.insert(settings_ui.columns, t)
        table.insert(settings_ui.column_data, entries)
        local w, h = estimate_text_size(text_str, 11)
        settings_ui.content_right = math.max(settings_ui.content_right, settings_origin_x + w)
        settings_ui.grid_bottom_y = grid_y + h
        position_settings_footer()
        resize_settings_backdrop()
        return
    end

    local spells = settings_state.library[settings_state.active_main][settings_state.active_sub] or {}
    local num_cols = math.max(1, math.ceil(#spells / SETTINGS_MAX_ROWS))
    local col_x = settings_origin_x
    local max_col_h = 0
    for col = 1, num_cols do
        local col_spells = {}
        local lines = L{}
        for row = 1, SETTINGS_MAX_ROWS do
            local idx = (col-1)*SETTINGS_MAX_ROWS + row
            local entry = spells[idx]
            if entry then
                local checked = settings_state.selection[settings_state.active_main][entry.name]
                lines:append(checked and ('\\cs(46,204,113)[✓] '..entry.name..'\\cr') or ('[ ] '..entry.name))
                table.insert(col_spells, entry)
                lines:append('')
                table.insert(col_spells, {name=nil})
            end
        end
        local text_str = lines:concat('\n')
        local t = texts.new({
            pos = {x = col_x, y = grid_y},
            text = {font='Segoe UI Symbol', size=11},
            bg = {alpha=0},
            flags = {draggable=false},
        })
        t:text(text_str)
        t:show()
        table.insert(settings_ui.columns, t)
        table.insert(settings_ui.column_data, col_spells)
        local w, h = estimate_text_size(text_str, 11)
        max_col_h = math.max(max_col_h, h)
        col_x = col_x + w + SETTINGS_COL_GAP
    end
    settings_ui.content_right = math.max(settings_ui.content_right, col_x - SETTINGS_COL_GAP)
    settings_ui.grid_bottom_y = grid_y + max_col_h
    position_settings_footer()
    resize_settings_backdrop()
end

function rebuild_settings_sub_tabs()
    for _, t in pairs(settings_ui.sub_tabs) do t:destroy() end
    settings_ui.sub_tabs = {}
    if settings_ui.singing_options then
        for _, t in pairs(settings_ui.singing_options) do t:destroy() end
        settings_ui.singing_options = nil
    end
    if settings_ui.ninjutsu_options then
        for _, t in pairs(settings_ui.ninjutsu_options) do t:destroy() end
        settings_ui.ninjutsu_options = nil
    end
    local sub_y = settings_ui.tabs_y + settings_ui.tab_row_h + 10

    if settings_state.active_main == "Ninjutsu" then
        settings_ui.ninjutsu_options = {}
        local checked = gs_skillup.use_toolbags
        local display = (checked and '\\cs(46,204,113)[✓] Allow Ninja Tool Toolbag Use\\cr' or '[ ] Allow Ninja Tool Toolbag Use')
        local check_t = texts.new({pos={x=settings_origin_x, y=sub_y}, text={font='Segoe UI Symbol', size=11}, bg={alpha=0}, flags={draggable=false}})
        check_t:text(display)
        check_t:show()
        local check_w, check_h = estimate_text_size(display, 11)
        settings_ui.ninjutsu_options.toolbags = check_t

        local note_str = "Checking this allows skillup to open a Toolbag to unpack the needed tool when you don't have the loose ninja tool in your inventory."
        local note_y = sub_y + check_h + 4
        local note_t = texts.new({pos={x=settings_origin_x, y=note_y}, text={font='Segoe UI Symbol', size=9}, bg={alpha=0}, flags={draggable=false}})
        note_t:text('\\cs(150,155,165)'..note_str..'\\cr')
        note_t:show()
        local note_w, note_h = estimate_text_size(note_str, 9)
        settings_ui.ninjutsu_options.note = note_t

        settings_ui.content_right = math.max(settings_ui.content_right, settings_origin_x + check_w, settings_origin_x + note_w)
        sub_y = note_y + note_h + 10
    end

    if settings_state.active_main == "Singing" then
        settings_ui.singing_options = {}
        local wind_checked = gs_skillup.track_wind_instrument
        local string_checked = gs_skillup.track_string_instrument
        local wind_display = (wind_checked and '\\cs(46,204,113)[✓] Track Wind Instrument\\cr' or '[ ] Track Wind Instrument')
        local string_display = (string_checked and '\\cs(46,204,113)[✓] Track String Instrument\\cr' or '[ ] Track String Instrument')
        local wind_t = texts.new({pos={x=settings_origin_x, y=sub_y}, text={font='Segoe UI Symbol', size=11}, bg={alpha=0}, flags={draggable=false}})
        wind_t:text(wind_display)
        wind_t:show()
        local wind_w = estimate_text_size(wind_display, 11)
        local string_t = texts.new({pos={x=settings_origin_x + wind_w + 20, y=sub_y}, text={font='Segoe UI Symbol', size=11}, bg={alpha=0}, flags={draggable=false}})
        string_t:text(string_display)
        string_t:show()
        local string_w, opt_h = estimate_text_size(string_display, 11)
        settings_ui.singing_options.wind = wind_t
        settings_ui.singing_options.string = string_t

        local note_str = "Skillup no longer auto-swaps instruments -- equip the matching instrument yourself, or a checked skill here will never cap."
        local note_y = sub_y + opt_h + 4
        local note_t = texts.new({pos={x=settings_origin_x, y=note_y}, text={font='Segoe UI Symbol', size=9}, bg={alpha=0}, flags={draggable=false}})
        note_t:text('\\cs(150,155,165)'..note_str..'\\cr')
        note_t:show()
        local note_w, note_h = estimate_text_size(note_str, 9)
        settings_ui.singing_options.note = note_t

        settings_ui.content_right = math.max(settings_ui.content_right, settings_origin_x + wind_w + 20 + string_w, settings_origin_x + note_w)
        sub_y = note_y + note_h + 10
    end

    if settings_state.active_main == "Globals" or settings_state.active_main == "Main" or settings_state.active_main == "Help" then
        settings_state.active_sub = nil
        settings_ui.subtabs_bottom_y = sub_y
        settings_ui.sub_tab_highlight:hide()
        rebuild_settings_grid()
        return
    end
    local sub_names = sorted_sub_tab_names(settings_state.active_main)
    settings_state.active_sub = sub_names[1]
    local max_sub_w, max_h = 0, 0
    for _, sub_name in ipairs(sub_names) do
        local w, h = estimate_text_size(sub_name, 13)
        max_sub_w = math.max(max_sub_w, w)
        max_h = math.max(max_h, h)
    end
    local sub_x = settings_origin_x
    settings_ui.sub_tab_width = max_sub_w + 8
    settings_ui.sub_tab_height = max_h + 4
    for i, sub_name in ipairs(sub_names) do
        if sub_name == settings_state.active_sub then
            settings_ui.sub_tab_highlight:pos(sub_x - 4, sub_y - 2)
            settings_ui.sub_tab_highlight:size(max_sub_w + 8, max_h + 4)
            settings_ui.sub_tab_highlight:show()
        end

        local display = sub_name == settings_state.active_sub and ('\\cs(94,160,255)'..sub_name..'\\cr') or sub_name
        local t = texts.new({
            pos = {x = sub_x, y = sub_y},
            text = {font='Segoe UI Symbol', size=13},
            bg = {alpha=0},
            flags = {draggable=false},
        })
        t:text(display)
        t:show()
        settings_ui.sub_tabs[sub_name] = t
        sub_x = sub_x + max_sub_w + SETTINGS_TAB_GAP
    end
    settings_ui.content_right = math.max(settings_ui.content_right, sub_x - SETTINGS_TAB_GAP)
    settings_ui.subtabs_bottom_y = sub_y + max_h + 10
    rebuild_settings_grid()
end

function select_settings_main_tab(category)
    settings_state.active_main = category
    for cat, t in pairs(settings_ui.main_tabs) do
        t:text(cat == category and ('\\cs(94,160,255)'..cat..'\\cr') or cat)
        if cat == category then
            local tx, ty = t:pos()
            settings_ui.main_tab_highlight:pos(tx - 4, ty - 2)
        end
    end
    rebuild_settings_sub_tabs()
end

function select_settings_sub_tab(sub_name)
    settings_state.active_sub = sub_name
    for name, t in pairs(settings_ui.sub_tabs) do
        t:text(name == sub_name and ('\\cs(94,160,255)'..name..'\\cr') or name)
        if name == sub_name then
            local tx, ty = t:pos()
            settings_ui.sub_tab_highlight:pos(tx - 4, ty - 2)
        end
    end
    rebuild_settings_grid()
end

function toggle_settings_spell(spell_name)
    local sel = settings_state.selection[settings_state.active_main]
    sel[spell_name] = not sel[spell_name] or nil
    rebuild_settings_grid()
end

function create_settings_ui()
    settings_ui.content_right = settings_origin_x

    
    settings_ui.border = images.new({
        pos = {x = settings_origin_x - SETTINGS_PAD - 3, y = settings_origin_y - SETTINGS_PAD - 3},
        size = {width = 400, height = 300},
        texture = {path = windower.addon_path..ICON_DIR..'background.png', fit = false},
        draggable = false,
    })
    settings_ui.border:color(88, 101, 242)
    settings_ui.border:alpha(255)
    settings_ui.border:show()

    
    settings_ui.backdrop = images.new({
        pos = {x = settings_origin_x - SETTINGS_PAD, y = settings_origin_y - SETTINGS_PAD},
        size = {width = 400, height = 300},
        texture = {path = windower.addon_path..ICON_DIR..'background.png', fit = false},
        draggable = true,
    })
    settings_ui.backdrop:color(26, 28, 34)
    settings_ui.backdrop:alpha(255)
    settings_ui.backdrop:show()

    
    settings_ui.header_panel = images.new({
        pos = {x = settings_origin_x - SETTINGS_PAD, y = settings_origin_y - SETTINGS_PAD},
        size = {width = 400, height = 60},
        texture = {path = windower.addon_path..ICON_DIR..'background.png', fit = false},
        draggable = false,
    })
    settings_ui.header_panel:color(40, 44, 54)
    settings_ui.header_panel:alpha(255)
    settings_ui.header_panel:show()

    -- Separator lines between sections (tabs/sub-tabs/grid/footer).
    -- Created now so they render on top of the backdrop; positioned and
    -- sized later in resize_settings_backdrop() once section boundaries
    -- are known. Muted slate instead of the old gold.
    settings_ui.sep_tabs = images.new({pos={x=0,y=0}, size={width=10,height=2}, texture={path=windower.addon_path..ICON_DIR..'background.png', fit=false}, draggable=false})
    settings_ui.sep_tabs:color(70, 75, 90)
    settings_ui.sep_tabs:show()
    settings_ui.sep_subtabs = images.new({pos={x=0,y=0}, size={width=10,height=2}, texture={path=windower.addon_path..ICON_DIR..'background.png', fit=false}, draggable=false})
    settings_ui.sep_subtabs:color(70, 75, 90)
    settings_ui.sep_subtabs:show()
    settings_ui.sep_footer = images.new({pos={x=0,y=0}, size={width=10,height=2}, texture={path=windower.addon_path..ICON_DIR..'background.png', fit=false}, draggable=false})
    settings_ui.sep_footer:color(70, 75, 90)
    settings_ui.sep_footer:show()

    local title_str = 'Skill-Up Spell Settings'
    settings_ui.title = texts.new({
        pos = {x = settings_origin_x, y = settings_origin_y},
        text = {font='Segoe UI Symbol', size=14},
        bg = {alpha=0},
        flags = {draggable=false},
    })
    settings_ui.title:text(title_str)
    settings_ui.title:show()
    local title_w, title_h = estimate_text_size(title_str, 14)
    settings_ui.content_right = math.max(settings_ui.content_right, settings_origin_x + title_w)

    -- Persistent output status display (Main tab's right side). Created
    -- once and updated via :text() only -- never destroyed/recreated on
    -- refresh -- to avoid flicker on the periodic status update.
    settings_ui.output_window = texts.new({
        pos = {x = 0, y = 0},
        text = {font='Segoe UI Symbol', size=11},
        bg = {alpha=0},
        flags = {draggable=false},
    })
    settings_ui.output_window:hide()

    -- Hide/minimize button, top-right corner. Positioned in
    -- resize_settings_backdrop() once the panel's actual width is known.
    settings_ui.hide_button = texts.new({
        pos = {x = 0, y = 0},
        text = {font='Segoe UI Symbol', size=13},
        bg = {alpha=0},
        flags = {draggable=false},
    })
    settings_ui.hide_button:text('\\cs(231,76,60)[X]\\cr')
    settings_ui.hide_button:show()

    settings_ui.tabs_y = settings_origin_y + title_h + 8
    settings_ui.main_tabs = {}
    -- All tabs use the width of the longest name, so they line up evenly
    -- instead of each being sized to its own text.
    local max_tab_w, max_tab_h = 0, 0
    for _, category in ipairs(SETTINGS_MAIN_TABS) do
        local w, h = estimate_text_size(category, 13)
        max_tab_w = math.max(max_tab_w, w)
        max_tab_h = math.max(max_tab_h, h)
    end
    -- One highlight rectangle, moved behind whichever tab is active,
    -- instead of one background image per tab (13 static images for
    -- something only one of which is ever visually "on" at a time --
    -- also meaningfully fewer objects to reposition while dragging).
    settings_ui.main_tab_highlight_w = max_tab_w + 8
    settings_ui.main_tab_highlight_h = max_tab_h + 4
    settings_ui.main_tab_highlight = images.new({
        pos = {x = settings_origin_x - 4, y = settings_origin_y - 2},
        size = {width = settings_ui.main_tab_highlight_w, height = settings_ui.main_tab_highlight_h},
        texture = {path = windower.addon_path..ICON_DIR..'background.png', fit = false},
        draggable = false,
    })
    settings_ui.main_tab_highlight:color(26, 28, 34)
    settings_ui.main_tab_highlight:alpha(255)
    settings_ui.main_tab_highlight:show()
    -- Sub-tab highlight, same idea -- one persistent image, resized and
    -- repositioned as needed since sub-tab widths vary by category.
    settings_ui.sub_tab_highlight = images.new({
        pos = {x = settings_origin_x - 4, y = settings_origin_y - 2},
        size = {width = 60, height = 20},
        texture = {path = windower.addon_path..ICON_DIR..'background.png', fit = false},
        draggable = false,
    })
    settings_ui.sub_tab_highlight:color(26, 28, 34)
    settings_ui.sub_tab_highlight:alpha(255)
    settings_ui.sub_tab_highlight:hide()
    -- Everything after Singing wraps to a second row.
    local wrap_after_index = nil
    for i, category in ipairs(SETTINGS_MAIN_TABS) do
        if category == "Singing" then wrap_after_index = i break end
    end
    local row_gap = 10
    local tab_x = settings_origin_x
    local tab_y = settings_ui.tabs_y
    local row2_max_x = settings_origin_x
    for i, category in ipairs(SETTINGS_MAIN_TABS) do
        if wrap_after_index and i == wrap_after_index + 1 then
            tab_x = settings_origin_x
            tab_y = settings_ui.tabs_y + max_tab_h + row_gap
        end
        if category == settings_state.active_main then
            settings_ui.main_tab_highlight:pos(tab_x - 4, tab_y - 2)
        end

        local display = category == settings_state.active_main and ('\\cs(94,160,255)'..category..'\\cr') or category
        local t = texts.new({
            pos = {x = tab_x, y = tab_y},
            text = {font='Segoe UI Symbol', size=13},
            bg = {alpha=0},
            flags = {draggable=false},
        })
        t:text(display)
        t:show()
        settings_ui.main_tabs[category] = t
        tab_x = tab_x + max_tab_w + SETTINGS_TAB_GAP
        row2_max_x = math.max(row2_max_x, tab_x)
    end
    settings_ui.content_right = math.max(settings_ui.content_right, row2_max_x - SETTINGS_TAB_GAP)
    -- Two rows of tabs now, so the block below (sub-tabs) starts after both.
    settings_ui.tab_row_h = (max_tab_h * 2) + row_gap

    settings_ui.save_button = texts.new({pos={x=0,y=0}, text={font='Segoe UI Symbol', size=13}, bg={alpha=0}, flags={draggable=false}})
    settings_ui.save_button:text('\\cs(46,204,113)[ Save ]\\cr')
    settings_ui.save_button:show()

    settings_ui.cancel_button = texts.new({pos={x=0,y=0}, text={font='Segoe UI Symbol', size=13}, bg={alpha=0}, flags={draggable=false}})
    settings_ui.cancel_button:text('\\cs(231,76,60)[ Cancel ]\\cr')
    settings_ui.cancel_button:show()

    settings_ui.footer_notice = texts.new({pos={x=0,y=0}, text={font='Segoe UI Symbol', size=13}, bg={alpha=0}, flags={draggable=false}})
    settings_ui.footer_notice:hide()

    rebuild_settings_sub_tabs()  -- cascades: sub-tabs -> grid -> footer -> backdrop resize
end

function serialize_spell_names(names)
    local sorted = {}
    for _, n in ipairs(names) do table.insert(sorted, n) end
    table.sort(sorted)
    local parts = {}
    for _, name in ipairs(sorted) do
        table.insert(parts, "'"..name:gsub("'", "\\'").."'")
    end
    return 'T{'..table.concat(parts, ',')..'}'
end

-- Commits the working selection into the live in-memory user_settings
-- (so the change takes effect immediately, no reload needed) and
-- rewrites settings.lua so it persists across restarts. This regenerates
-- the whole file -- any hand-added comments beyond the standard header
-- won't survive a save from this UI.
function save_settings_file()
    local was_running = skilluprun
    local running_category = gs_skill.skillup_type
    if was_running then
        self_command('skillstop')
    end
    for _, category in ipairs(SETTINGS_MAIN_TABS) do
        if category ~= "Globals" and category ~= "Main" and category ~= "Help" then
            local names = {}
            for name, checked in pairs(settings_state.selection[category]) do
                if checked then table.insert(names, name) end
            end
            table.sort(names)
            local list = T{}
            for _, name in ipairs(names) do list:append(name) end
            user_settings.user_spells[category] = list
        end
    end

    local lines = {}
    table.insert(lines, "-- ============================================================")
    table.insert(lines, "-- SkillUp addon -- player settings")
    table.insert(lines, "-- ============================================================")
    table.insert(lines, "-- Regenerated by the in-game Settings menu (Toggle Menu -> Settings).")
    table.insert(lines, "-- Hand-editing this file still works too -- //lua reload skillup")
    table.insert(lines, "-- after changing it. Saving from the in-game menu will overwrite")
    table.insert(lines, "-- any comments you've added here, beyond this header.")
    table.insert(lines, "")
    table.insert(lines, "user_settings = {")
    table.insert(lines, "    user_spells = {")
    for _, category in ipairs(SETTINGS_MAIN_TABS) do
        if category ~= "Globals" and category ~= "Main" and category ~= "Help" then
            local names = {}
            for _, n in ipairs(user_settings.user_spells[category]) do table.insert(names, n) end
            table.insert(lines, "        "..category.." = "..serialize_spell_names(names)..",")
        end
    end
    local offensive_names = {}
    for _, n in ipairs(user_settings.user_spells.Offensive or T{}) do table.insert(offensive_names, n) end
    table.insert(lines, "        Offensive = "..serialize_spell_names(offensive_names)..",")
    table.insert(lines, "    },")
    table.insert(lines, "    save_settings = "..tostring(user_settings.save_settings)..",")
    table.insert(lines, "    mp_ws_threshold = "..tostring(user_settings.mp_ws_threshold)..",")
    for _, def in ipairs(GLOBAL_TOGGLE_DEFS) do
        table.insert(lines, "    "..def.field.." = "..tostring(gs_skillup[def.field])..",")
    end
    for _, def in ipairs(SINGING_TRACK_DEFS) do
        table.insert(lines, "    "..def.field.." = "..tostring(gs_skillup[def.field])..",")
    end
    table.insert(lines, "    use_toolbags = "..tostring(gs_skillup.use_toolbags)..",")
    table.insert(lines, "    periodic_ui_refresh = "..tostring(gs_skillup.periodic_ui_refresh)..",")
    table.insert(lines, "}")

    local dir = windower.addon_path..'data/'..tostring(windower.ffxi.get_player() and windower.ffxi.get_player().name)
    ensure_dir_path(dir)
    local path = dir..'/settings.lua'
    local file, err = io.open(path, 'w')
    if not file then
        windower.add_to_chat(167, 'save_settings_file: failed to open '..path..' for writing -- '..tostring(err))
        return false
    end
    file:write(table.concat(lines, '\n')..'\n')
    file:close()
    windower.add_to_chat(123, 'Settings saved to '..path)
    if was_running then
        -- Restart the same category so the rotation rebuilds from the
        -- spell list we just saved -- otherwise it'd keep running with
        -- whatever list was active before Save was clicked.
        windower.add_to_chat(123, 'Restarting '..running_category..' skill-up with the updated spell list.')
        self_command('start '..running_category)
    end
    rebuild_settings_grid()
    return true
end

function handle_settings_click(x, y)
    if settings_state.hidden then return end
    if settings_ui.hide_button and settings_ui.hide_button:hover(x, y) then
        hide_settings_panel()
        return
    end
    for category, t in pairs(settings_ui.main_tabs) do
        if point_in_padded_bounds(t, x, y, settings_ui.main_tab_highlight_w, settings_ui.main_tab_highlight_h) then
            select_settings_main_tab(category)
            return
        end
    end
    for sub_name, t in pairs(settings_ui.sub_tabs) do
        if point_in_padded_bounds(t, x, y, settings_ui.sub_tab_width, settings_ui.sub_tab_height) then
            select_settings_sub_tab(sub_name)
            return
        end
    end
    if settings_ui.singing_options then
        if settings_ui.singing_options.wind:hover(x, y) then
            self_command('settrackwind')
            rebuild_settings_sub_tabs()
            return
        end
        if settings_ui.singing_options.string:hover(x, y) then
            self_command('settrackstring')
            rebuild_settings_sub_tabs()
            return
        end
    end
    if settings_ui.ninjutsu_options then
        if settings_ui.ninjutsu_options.toolbags:hover(x, y) then
            self_command('settoolbags')
            rebuild_settings_sub_tabs()
            return
        end
    end
    for col_idx, t in ipairs(settings_ui.columns) do
        if t:hover(x, y) then
            local entries = settings_ui.column_data[col_idx]
            local tw, th = texts.extents(t)
            local col_x, col_y = t:pos()
            if th > 0 and #entries > 0 then
                local line_h = th / #entries
                local row = math.floor((y - col_y) / line_h) + 1
                local entry = entries[row]
                if entry then
                    if settings_state.active_main == "Globals" or settings_state.active_main == "Main" or settings_state.active_main == "Help" then
                        if entry.command then
                            self_command(entry.command)
                            updatedisplay()
                            rebuild_settings_grid()
                        end
                    else
                        if entry.name then
                            toggle_settings_spell(entry.name)
                        end
                    end
                end
            end
            return
        end
    end
    if settings_ui.save_button:hover(x, y) then
        save_settings_file()
        show_footer_notice('Saved!', 46, 204, 113)
        return
    end
    if settings_ui.cancel_button:hover(x, y) then
        -- Discard unsaved spell-selection changes by reloading from
        -- whatever's currently persisted, and refresh the visible tab.
        init_settings_selection()
        rebuild_settings_grid()
        show_footer_notice('Canceled', 231, 76, 60)
        return
    end
end

-- Moves every settings UI element by the same delta -- used when the
-- title (the drag handle) is dragged, so the whole panel moves as one
-- unit even though each piece is a separate Windower primitive.
-- Hides the whole panel (not destroyed -- just hidden, so showing it
-- again doesn't need a full rebuild). //skillup hide, or the [X] button.
function hide_settings_panel()
    local function hide(obj) if obj then obj:hide() end end
    hide(settings_ui.border)
    hide(settings_ui.backdrop)
    hide(settings_ui.header_panel)
    hide(settings_ui.sep_tabs)
    hide(settings_ui.sep_subtabs)
    hide(settings_ui.sep_footer)
    hide(settings_ui.title)
    hide(settings_ui.output_window)
    hide(settings_ui.hide_button)
    for _, t in pairs(settings_ui.main_tabs) do hide(t) end
    hide(settings_ui.main_tab_highlight)
    for _, t in pairs(settings_ui.sub_tabs) do hide(t) end
    hide(settings_ui.sub_tab_highlight)
    if settings_ui.singing_options then
        for _, t in pairs(settings_ui.singing_options) do hide(t) end
    end
    if settings_ui.ninjutsu_options then
        for _, t in pairs(settings_ui.ninjutsu_options) do hide(t) end
    end
    for _, t in ipairs(settings_ui.columns) do hide(t) end
    hide(settings_ui.save_button)
    hide(settings_ui.footer_notice)
    hide(settings_ui.cancel_button)
    settings_state.hidden = true
end

-- Shows the panel again. Re-shows the persistent pieces directly, then
-- lets rebuild_settings_sub_tabs() re-derive which tab-specific elements
-- (sub-tabs, columns, output window) should be visible for whichever tab
-- is currently active, rather than tracking that separately.
function show_settings_panel()
    local function show(obj) if obj then obj:show() end end
    show(settings_ui.border)
    show(settings_ui.backdrop)
    show(settings_ui.header_panel)
    show(settings_ui.sep_tabs)
    show(settings_ui.sep_subtabs)
    show(settings_ui.sep_footer)
    show(settings_ui.title)
    show(settings_ui.hide_button)
    for _, t in pairs(settings_ui.main_tabs) do show(t) end
    show(settings_ui.main_tab_highlight)
    show(settings_ui.save_button)
    show(settings_ui.cancel_button)
    settings_state.hidden = false
    rebuild_settings_sub_tabs()
end

-- Captures each element's offset from the current origin, once per drag
-- session, so every subsequent frame of that same drag can reposition
-- everything with a single setter call (no getter) per element.
function build_drag_offsets_cache()
    local cache = {}
    local function record(key, obj)
        if not obj then return end
        local x, y = obj:pos()
        cache[key] = {obj=obj, dx=x-settings_origin_x, dy=y-settings_origin_y}
    end
    record('border', settings_ui.border)
    -- backdrop is the drag driver -- already moved by the OS-level drag,
    -- don't reposition it again.
    record('header_panel', settings_ui.header_panel)
    record('sep_tabs', settings_ui.sep_tabs)
    record('sep_subtabs', settings_ui.sep_subtabs)
    record('sep_footer', settings_ui.sep_footer)
    record('title', settings_ui.title)
    record('hide_button', settings_ui.hide_button)
    record('main_tab_highlight', settings_ui.main_tab_highlight)
    record('sub_tab_highlight', settings_ui.sub_tab_highlight)
    for id, t in pairs(settings_ui.main_tabs) do record('mt_'..id, t) end
    for id, t in pairs(settings_ui.sub_tabs) do record('st_'..id, t) end
    if settings_ui.singing_options then
        for id, t in pairs(settings_ui.singing_options) do record('sing_'..id, t) end
    end
    if settings_ui.ninjutsu_options then
        for id, t in pairs(settings_ui.ninjutsu_options) do record('nin_'..id, t) end
    end
    for i, t in ipairs(settings_ui.columns) do record('col_'..i, t) end
    record('save_button', settings_ui.save_button)
    record('footer_notice', settings_ui.footer_notice)
    record('cancel_button', settings_ui.cancel_button)
    record('output_window', settings_ui.output_window)
    return cache
end

-- Repositions every cached element via a single setter call each (no
-- getters), and shifts the stored ABSOLUTE coordinates (content_right,
-- tabs_y, etc. -- bookkeeping numbers, not positioned objects) by the
-- same delta. Skipping that second part would leave them stale, so any
-- rebuild triggered mid-drag (e.g. hovering a tab) would recompute sizes
-- against the new origin combined with old values, visibly separating
-- the title/tabs from the rest of the panel.
function apply_drag_offsets_cache(cache, dx, dy)
    for _, entry in pairs(cache) do
        entry.obj:pos(settings_origin_x + entry.dx, settings_origin_y + entry.dy)
    end
    settings_ui.content_right = settings_ui.content_right + dx
    if settings_ui.tabs_y then settings_ui.tabs_y = settings_ui.tabs_y + dy end
    if settings_ui.subtabs_bottom_y then settings_ui.subtabs_bottom_y = settings_ui.subtabs_bottom_y + dy end
    if settings_ui.grid_bottom_y then settings_ui.grid_bottom_y = settings_ui.grid_bottom_y + dy end
    if settings_ui.footer_bottom_y then settings_ui.footer_bottom_y = settings_ui.footer_bottom_y + dy end
end

-- Only rebuilds the visible tab when the hovered target actually changes
-- (not on every mouse-move pixel), since a rebuild recreates texts
-- objects rather than cheaply updating an existing one.
last_hovered_settings_id = nil
function handle_settings_hover(x, y)
    if settings_state.hidden then return end
    local hovered_id = nil
    for col_idx, t in ipairs(settings_ui.columns) do
        if t:hover(x, y) then
            local entries = settings_ui.column_data[col_idx]
            local tw, th = texts.extents(t)
            local col_x, col_y = t:pos()
            if th > 0 and #entries > 0 then
                local line_h = th / #entries
                local row = math.floor((y - col_y) / line_h) + 1
                local entry = entries[row]
                if entry and entry.id and type(entry.id) == 'string' then
                    hovered_id = entry.id
                end
            end
            break
        end
    end
    if hovered_id ~= last_hovered_settings_id then
        set_color(hovered_id or "none")
        last_hovered_settings_id = hovered_id
        if settings_state.active_main == "Main" or settings_state.active_main == "Globals" then
            rebuild_settings_grid()
        end
    end
end

windower.register_event('mouse', function(type, x, y, delta, blocked)
    if type == 0 then
        handle_settings_hover(x, y)
    elseif type == 2 then
        handle_settings_click(x, y)
    end
end)
function log_debug_line(line)
    local ok, dir = pcall(function() return windower.addon_path..'data/'..windower.ffxi.get_player().name..'/Saves' end)
    if not ok then
        windower.add_to_chat(167, 'log_debug_line: failed to build path -- '..tostring(dir))
        return
    end
    if not windower.dir_exists(dir) then
        ensure_dir_path(dir)
        if not windower.dir_exists(dir) then
            windower.add_to_chat(167, 'log_debug_line: failed to create dir '..dir)
            return
        end
    end
    local file, err = io.open(dir..'/skillup_debug.log', 'a')
    if file then
        file:write('['..os.date('%Y-%m-%d %H:%M:%S')..'] '..line..'\n')
        file:close()
    else
        windower.add_to_chat(167, 'log_debug_line: io.open failed for '..dir..'/skillup_debug.log -- '..tostring(err))
    end
end
windower.register_event('incoming text', function(original, modified, original_mode, modified_mode, block)
    if gs_skillup.debug_action_msg and modified and modified:lower():find('skill') then
        log_debug_line('incoming text: '..modified)
    end
    if modified then
        -- FFXI/Windower embeds \30<byte> color-code control sequences between
        -- individual words in chat text (e.g. right between "Player" and
        -- "'s"), which breaks a literal match like windower.ffxi.get_player().name.."'s" -- strip
        -- them out before matching.
        local clean = modified:gsub('\30.', '')
        -- e.g. "Player's blue magic skill rises 0.3 points."
        local amount = clean:match(windower.ffxi.get_player().name.."'s .- skill rises ([%d%.]+) points")
        if gs_skillup.debug_action_msg and clean:lower():find('rises') then
            log_debug_line('match attempt: windower.ffxi.get_player().name="'..tostring(windower.ffxi.get_player().name)..'" clean="'..clean..'" amount='..tostring(amount)..' total_before='..tostring(gs_skillup.total_skill_ups))
        end
        if amount then
            local points = tonumber(amount)
            local ts = os.clock()
            gs_skillup.total_skill_ups = gs_skillup.total_skill_ups + points
            gs_skillup.skill_ups[ts] = points
            if gs_skillup.debug_action_msg then
                log_debug_line('counted: points='..tostring(points)..' total_after='..tostring(gs_skillup.total_skill_ups))
            end
            updatedisplay()
        end
    end
end)
windower.register_event('action message', function(actor_id, target_id, actor_index, target_index, message_id, param_1, param_2, param_3)
    if gs_skillup.debug_action_msg then
        log_debug_line('action message: actor='..tostring(actor_id)..' target='..tostring(target_id)..' windower.ffxi.get_player().id='..tostring(windower.ffxi.get_player().id)..' id='..tostring(message_id)..' p1='..tostring(param_1)..' p2='..tostring(param_2)..' p3='..tostring(param_3))
    end
    updatedisplay()
end)
frame_count = 0
last_drag_pos_x = nil
last_drag_pos_y = nil
drag_offsets_cache = nil
last_ui_refresh_time = nil
last_drag_activity_time = nil
windower.register_event('prerender',function()
    if frame_count%30 == 0 then
        updatedisplay()
    end
    if gs_skillup.periodic_ui_refresh and not settings_state.hidden and not drag_offsets_cache then
        if not last_ui_refresh_time then
            last_ui_refresh_time = os.clock()
        elseif os.clock() - last_ui_refresh_time >= UI_REFRESH_INTERVAL then
            destroy_settings_ui()
            create_settings_ui()
            last_ui_refresh_time = os.clock()
        end
    end
    if settings_ui.footer_notice_expire and os.clock() >= settings_ui.footer_notice_expire then
        settings_ui.footer_notice:hide()
        settings_ui.footer_notice_expire = nil
    end
    
    -- The backdrop is the drag handle for the whole panel (click anywhere
    -- on the container background); everything else follows it by
    -- translation. Previously this did a getter+setter round trip for
    -- every element on EVERY frame of the drag, which was visibly
    -- laggier for text objects than images -- now each element's offset
    -- from the origin is captured once (one getter each) at the start of
    -- a drag session, and every subsequent frame just does a single
    -- setter call per element (origin + cached offset), no getters.
    if settings_ui.backdrop then
        local bx, by = settings_ui.backdrop:pos()
        bx, by = clamp_panel_position(bx, by)
        settings_ui.backdrop:pos(bx, by)
        if last_drag_pos_x and (bx ~= last_drag_pos_x or by ~= last_drag_pos_y) then
            if not drag_offsets_cache then
                drag_offsets_cache = build_drag_offsets_cache()
            end
            local dx, dy = bx - last_drag_pos_x, by - last_drag_pos_y
            settings_origin_x = settings_origin_x + dx
            settings_origin_y = settings_origin_y + dy
            apply_drag_offsets_cache(drag_offsets_cache, dx, dy)
            last_drag_activity_time = os.clock()
        elseif drag_offsets_cache and last_drag_activity_time and os.clock() - last_drag_activity_time > 0.3 then
            -- No reported movement for a genuine pause (not just one
            -- frame with no delta, which can happen from position
            -- rounding during a slow, smooth drag) -- the drag has
            -- actually ended.
            drag_offsets_cache = nil
        end
        last_drag_pos_x, last_drag_pos_y = bx, by
    end
    if get_player_status_string() == 'Resting' then
        if skilluprun and windower.ffxi.get_player().vitals.mp >= windower.ffxi.get_player().vitals.max_mp and not gs_skillup.resting_recovery_sent then
            gs_skillup.resting_recovery_sent = true
            windower.send_command('input /heal off')
            -- Resting never resumed casting on its own -- nothing else
            -- calls back into the decision pipeline once /heal off fires,
            -- so the rotation just silently stopped after MP recovered.
            decide_and_act(2.0)
        end
    else
        gs_skillup.resting_recovery_sent = false
    end
    -- Safety net: ja/ws/item resolution categories aren't confirmed yet
    -- (only spells are, via the 'action' event above), so those pending
    -- casts would otherwise never clear and the rotation would stall.
    -- Treat a still-active non-spell pending cast as resolved after a
    -- generous timeout rather than hang indefinitely.
    if pending_cast.active and pending_cast.cast_type ~= 'spell' and pending_cast.sent_time
        and os.clock() - pending_cast.sent_time > 8 then
        handle_cast_success()
    end
    frame_count = frame_count + 1
end)