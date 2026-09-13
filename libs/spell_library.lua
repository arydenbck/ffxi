-- ============================================================
-- SkillUp addon -- spell library
-- ============================================================
-- Builds the full candidate spell list for every skill-up category,
-- pulled live from res.spells (Windower's resource database) rather than
-- hand-typed here -- this way it always matches whatever spell data your
-- Windower install actually has, including any private-server-specific
-- additions.
--
-- (Self vs. Enemy) -- the same real game-data field this addon already
-- uses elsewhere (spell_allowed_by_user_list's offensive-spell check),
-- not a name guess.

-- Same category -> skill id mapping already used in skillup.lua's
-- self_command 'start' handler.
SKILL_ID_MAP = {
    ["Divine"]=32, ["Healing"]=33, ["Enhancing"]=34, ["Enfeebling"]=35,
    ["Elemental"]=36, ["Dark"]=37, ["Summoning"]=38, ["Ninjutsu"]=39,
    ["Singing"]=40, ["Blue"]=43, ["Geomancy"]=44,
}

-- Ordered list of {name, match(spell)} per category, where match()
-- receives the FULL res.spells entry (not just the name) so rules can
-- use any field, e.g. Blue Magic's targets-based split below. First
-- match wins; anything matching nothing falls into "Other".
SUB_CATEGORY_RULES = {
    -- Confidence: high (small, well-known, stable spell families).
    Healing = {
        {name="Cure",           match=function(s) return s.en:find('^Cure') or s.en:find('^Curaga') end},
        {name="Status Removal", match=function(s) return s.en:find('na$') end},
        {name="Raise",          match=function(s) return s.en:find('^Raise') or s.en:find('^Reraise') or s.en:find('^Arise') end},
        {name="Regen",          match=function(s) return s.en:find('^Regen') end},
    },
    -- Confidence: high for Protect/Shell/Bar/En-spell families. Buffs
    -- (which now also covers Regen/Refresh, merged per request) is a
    -- coarser catch-all bucket.
    Enhancing = {
        {name="Protect/Shell", match=function(s) return s.en:find('^Protect') or s.en:find('^Shell') end},
        {name="Bar-spells",    match=function(s) return s.en:find('^Bar') end},
        {name="En-spells",     match=function(s) return s.en:find('^Enfire') or s.en:find('^Enblizzard') or s.en:find('^Enaero') or s.en:find('^Enstone') or s.en:find('^Enthunder') or s.en:find('^Enwater') end},
        {name="Buffs",         match=function(s) return s.en:find('^Regen') or s.en:find('^Refresh') or s.en:find('^Haste') or s.en:find('^Flurry') or s.en:find('^Phalanx') or s.en:find('^Stoneskin') or s.en:find('^Aquaveil') or s.en:find('^Blink') or s.en:find('^Boost%-') or s.en:find('^Gain%-') or s.en:find('^Temper') end},
    },
  
    Enfeebling = {},
   
    Elemental = {},
    
    Dark = {},
   
    Divine = {},
    
    Summoning = {
        {name="Elemental Spirits", match=function(s) return s.en:find('Spirit$') end},
        {name="Avatars", match=function(s)
            local n = s.en
            return n=='Carbuncle' or n=='Fenrir' or n=='Ifrit' or n=='Titan' or n=='Leviathan'
                or n=='Garuda' or n=='Shiva' or n=='Ramuh' or n=='Diabolos' or n=='Odin'
                or n=='Alexander' or n=='Atomos' or n=='Cait Sith' or n=='Siren'
        end},
    },
    -- Confidence: high (Ninjutsu families are rigidly named, already
    -- confirmed in NINJUTSU_TOOL_MAP earlier in this project).
    Ninjutsu = {
        {name="Elemental",      match=function(s) return s.en:find('^Katon') or s.en:find('^Hyoton') or s.en:find('^Huton') or s.en:find('^Doton') or s.en:find('^Raiton') or s.en:find('^Suiton') end},
        {name="Foe-Enfeebling", match=function(s) return s.en:find('^Jubaku') or s.en:find('^Kurayami') or s.en:find('^Dokumori') or s.en:find('^Hojo') or s.en:find('^Aisha') or s.en:find('^Yurin') end},
        {name="Self-Enhancing", match=function(s) return s.en:find('^Utsusemi') or s.en:find('^Tonko') or s.en:find('^Monomi') or s.en:find('^Migawari') or s.en:find('^Myoshu') or s.en:find('^Gekka') or s.en:find('^Yain') or s.en:find('^Kakka') end},
    },
    
    Singing = {
        {name="Offensive", match=function(s) return s.targets and s.targets:contains('Enemy') end},
        {name="Defensive", match=function(s) return not (s.targets and s.targets:contains('Enemy')) end},
    },
    -- Confidence: high (Indi-/Geo- prefix is mechanically guaranteed).
    Geomancy = {
        {name="Indi-spells", match=function(s) return s.en:find('^Indi%-') end},
        {name="Geo-spells",  match=function(s) return s.en:find('^Geo%-') end},
    },
    -- Confidence: high -- this is real game data (spell.targets), not a
    -- name guess. Enemy-targeted = Offensive, everything else (Self,
    -- Party, etc.) = Defensive.
    Blue = {
        {name="Offensive", match=function(s) return s.targets and s.targets:contains('Enemy') end},
        {name="Defensive", match=function(s) return not (s.targets and s.targets:contains('Enemy')) end},
    },
}


local function is_excluded(name)
    return name:wmatch('Teleport-*|Warp*|Tractor*|Retrace|Escape|Geo-*|Sacrifice|Odin|Alexander|Recall-*')
end

-- Returns { [category] = { [sub_category] = { {id=, name=}, ... }, ... }, ... }
-- Categories with no SUB_CATEGORY_RULES entry get everything under a
-- single "All" sub-category.
function build_spell_library()
    local library = {}
    for category, skill_id in pairs(SKILL_ID_MAP) do
        library[category] = {}
        local rules = SUB_CATEGORY_RULES[category]
        for id, spell in pairs(res.spells) do
            if spell.skill == skill_id and spell.en and not is_excluded(spell.en) then
                local sub_name = "Other"
                if rules then
                    for _, rule in ipairs(rules) do
                        if rule.match(spell) then
                            sub_name = rule.name
                            break
                        end
                    end
                else
                    sub_name = "All"
                end
                library[category][sub_name] = library[category][sub_name] or {}
                table.insert(library[category][sub_name], {id = id, name = spell.en})
            end
        end
        for _, sub in pairs(library[category]) do
            table.sort(sub, function(a, b) return a.name < b.name end)
        end
    end
    return library
end

-- ============================================================
-- Ninjutsu tool reference data
-- ============================================================
-- Which physical item(s) cast each Ninjutsu spell: a specific "primary"
-- tool plus a "universal"/master-level tool that works across a wider
-- range of spells in the same category but is pricier, so primary is
-- always tried first. Master-level tools by category: Inoshishinofuda
-- for the six elemental damage spells, Chonofuda for foe-enfeebling
-- spells, Shikanofuda for self-enhancing spells
-- (bg-wiki.com/ffxi/Category:Ninja_Tools).
--
-- Master Level (78-93) spells, sourced from their individual BG-Wiki
-- pages (bg-wiki.com/ffxi/Kakka:_Ichi, /Aisha:_Ichi, /Yurin:_Ichi,
-- /Migawari:_Ichi, /Gekka:_Ichi, /Yain:_Ichi).
--

NINJUTSU_TOOL_MAP = {
    -- Self-enhancing
    ['Tonko: Ichi'] = {primary = 'Shinobi-Tabi', universal = 'Shikanofuda'},
    ['Tonko: Ni'] = {primary = 'Shinobi-Tabi', universal = 'Shikanofuda'},
    ['Monomi: Ichi'] = {primary = 'Sanjaku-Tenugui', universal = 'Shikanofuda'},
    ['Utsusemi: Ichi'] = {primary = 'Shihei', universal = 'Shikanofuda'},
    ['Utsusemi: Ni'] = {primary = 'Shihei', universal = 'Shikanofuda'},
    ['Utsusemi: San'] = {primary = 'Shihei', universal = 'Shikanofuda'},
    ['Myoshu: Ichi'] = {primary = 'Kabenro', universal = 'Shikanofuda'},
    ['Migawari: Ichi'] = {primary = 'Mokujin', universal = 'Shikanofuda'},
    ['Gekka: Ichi'] = {primary = 'Ranka', universal = 'Shikanofuda'},
    ['Yain: Ichi'] = {primary = 'Furusumi', universal = 'Shikanofuda'},
    ['Kakka: Ichi'] = {primary = 'Ryuno', universal = 'Shikanofuda'},
    -- Elemental
    ['Katon: Ichi'] = {primary = 'Uchitake', universal = 'Inoshishinofuda'},
    ['Katon: Ni'] = {primary = 'Uchitake', universal = 'Inoshishinofuda'},
    ['Katon: San'] = {primary = 'Uchitake', universal = 'Inoshishinofuda'},
    ['Hyoton: Ichi'] = {primary = 'Tsurara', universal = 'Inoshishinofuda'},
    ['Hyoton: Ni'] = {primary = 'Tsurara', universal = 'Inoshishinofuda'},
    ['Hyoton: San'] = {primary = 'Tsurara', universal = 'Inoshishinofuda'},
    ['Huton: Ichi'] = {primary = 'Kawahori-Ogi', universal = 'Inoshishinofuda'},
    ['Huton: Ni'] = {primary = 'Kawahori-Ogi', universal = 'Inoshishinofuda'},
    ['Huton: San'] = {primary = 'Kawahori-Ogi', universal = 'Inoshishinofuda'},
    ['Doton: Ichi'] = {primary = 'Makibishi', universal = 'Inoshishinofuda'},
    ['Doton: Ni'] = {primary = 'Makibishi', universal = 'Inoshishinofuda'},
    ['Doton: San'] = {primary = 'Makibishi', universal = 'Inoshishinofuda'},
    ['Raiton: Ichi'] = {primary = 'Hiraishin', universal = 'Inoshishinofuda'},
    ['Raiton: Ni'] = {primary = 'Hiraishin', universal = 'Inoshishinofuda'},
    ['Raiton: San'] = {primary = 'Hiraishin', universal = 'Inoshishinofuda'},
    ['Suiton: Ichi'] = {primary = 'Mizu-Deppo', universal = 'Inoshishinofuda'},
    ['Suiton: Ni'] = {primary = 'Mizu-Deppo', universal = 'Inoshishinofuda'},
    ['Suiton: San'] = {primary = 'Mizu-Deppo', universal = 'Inoshishinofuda'},
    -- Foe-enfeebling
    ['Jubaku: Ichi'] = {primary = 'Jusatsu', universal = 'Chonofuda'},
    ['Jubaku: Ni'] = {primary = 'Jusatsu', universal = 'Chonofuda'},
    ['Kurayami: Ichi'] = {primary = 'Sairui-Ran', universal = 'Chonofuda'},
    ['Kurayami: Ni'] = {primary = 'Sairui-Ran', universal = 'Chonofuda'},
    ['Dokumori: Ichi'] = {primary = 'Kodoku', universal = 'Chonofuda'},
    ['Hojo: Ichi'] = {primary = 'Kaginawa', universal = 'Chonofuda'},
    ['Hojo: Ni'] = {primary = 'Kaginawa', universal = 'Chonofuda'},
    ['Aisha: Ichi'] = {primary = 'Soshi', universal = 'Chonofuda'},
    ['Yurin: Ichi'] = {primary = 'Jinko', universal = 'Chonofuda'},
}

-- Item resource IDs for each loose Ninjutsu tool, used to resolve the
-- localized item name via res.items for inventory checks.
NINJUTSU_TOOL_ITEM_IDS = {
    ['Sanjaku-Tenugui']=5417,['Soshi']=5734,['Uchitake']=5308,['Tsurara']=5309,['Kawahori-Ogi']=5310,['Makibishi']=5311,['Hiraishin']=5312,
    ['Mizu-Deppo']=5313,['Shihei']=5314,['Jusatsu']=5315,['Kaginawa']=5316,['Sairui-Ran']=5317,['Kodoku']=5318,['Shinobi-Tabi']=5319,['Ranka']=6265,
    ['Furusumi']=6266,['Kabenro']=5863,['Jinko']=5864,['Ryuno']=5865,['Mokujin']=5866,["Chonofuda"]=5869,["Inoshishinofuda"]=5867,["Shikanofuda"]=5868,
}

-- Toolbag item names for each tool -- using one converts it into a full
-- stack (99) of the loose tool, added directly to inventory. Source:
-- BG-Wiki's Ninja Tools category. Note: a couple of wikis/servers list

TOOLBAG_MAP = {
    ['Chonofuda']='Toolbag (Cho)', ['Furusumi']='Toolbag (Furu)', ['Hiraishin']='Toolbag (Hira)',
    ['Inoshishinofuda']='Toolbag (Ino)', ['Jinko']='Toolbag (Jinko)', ['Jusatsu']='Toolbag (Jusa)',
    ['Kabenro']='Toolbag (Kaben)', ['Kaginawa']='Toolbag (Kagi)', ['Kawahori-Ogi']='Toolbag (Kawa)',
    ['Kodoku']='Toolbag (Kodo)', ['Makibishi']='Toolbag (Maki)', ['Mizu-Deppo']='Toolbag (Mizu)',
    ['Mokujin']='Toolbag (Moku)', ['Ranka']='Toolbag (Ranka)', ['Ryuno']='Toolbag (Ryuno)',
    ['Sairui-Ran']='Toolbag (Sai)', ['Sanjaku-Tenugui']='Toolbag (Sanja)', ['Shihei']='Toolbag (Shihe)',
    ['Shikanofuda']='Toolbag (Shika)', ['Shinobi-Tabi']='Toolbag (Shino)', ['Soshi']='Toolbag (Soshi)',
    ['Tsurara']='Toolbag (Tsura)', ['Uchitake']='Toolbag (Uchi)',
}