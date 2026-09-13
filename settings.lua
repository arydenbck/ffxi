-- ============================================================
-- SkillUp addon -- player settings TEMPLATE DO NOT EDIT
-- ============================================================



user_settings = {
    user_spells = {
        Healing = T{'Cure','Cure II'},
        Geomancy = T{'Indi-Poison','Indi-DEX','Indi-Fury','Indi-Focus','Indi-Wilt'},
        Enhancing = T{'Enfire','Enthunder','Enblizzard','Protect','Shell'},
        Ninjutsu = T{'Tonko: Ichi', 'Monomi: Ichi'},
        Singing = T{'Advancing March','Victory March','Valor Minuet V','Mages Ballad III', "Army's Paeon", "Army's Paeon II"},
        Blue = T{'Pollen'},
        Summoning = T{'Dark Spirit','Water Spirit','Light Spirit','Air Spirit', 'Garuda'},
        Elemental = T{'Stone', 'Fire'},
        Dark = T{'Bio'},
        Divine = T{'Banish', 'Holy'},
        Enfeebling = T{'Dia', 'Silence', 'Paralyze'},
        Offensive = T{'Foot Kick', 'Power Attack', 'Wild Oats', 'Stone', 'Fire', 'Bio', 'Banish', 'Holy', 'Dia', 'Silence', 'Paralyze'},
    },
    save_settings = false, -- change this to true if you wish to save the last position of your skillup window
    mp_ws_threshold = 50,  -- with "Use MP Regain WS" toggled on, it'll try Energy Drain (etc.) whenever your MP% drops to or below this number, regardless of the next spell's cost

    -- These 6 are also editable from the in-game Settings menu (Globals
    -- tab) -- changes made there overwrite this file on Save.
    use_trust = false,        -- Use Moogle Trust
    use_geo = false,          -- Use Geo's Refresh
    use_item = false,         -- Use Skill Up Item
    use_mp_ws = false,        -- Use MP Regain WS
    use_offensive = false,    -- Use Offensive Spells
    require_engaged = true,   -- Require Engaged Target

    -- Which instrument skill(s) Singing waits on before stopping. Also
    -- editable from the Settings menu's Singing tab.
    track_wind_instrument = true,
    track_string_instrument = true,

    -- If a Ninjutsu spell's tool isn't in inventory, allow opening a
    -- Toolbag (if one is available) to unpack it instead. Off by default
    -- since Toolbags are a valuable, limited resource.
    use_toolbags = false,

    -- Opt-in workaround for Windower having no real z-index control:
    -- periodically rebuilds the panel so it reclaims top render priority
    -- if another addon draws over it. Causes a brief visible flash each
    -- time it runs, which is why this defaults off. Toggle with
    -- //skillup zfix.
    periodic_ui_refresh = false,
}