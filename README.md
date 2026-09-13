# SkillUp

**SkillUp** is a Windower addon for *Final Fantasy XI* that automates
magic-skill progression through configurable spell rotations. It
supports multiple magic skills, party-aware targeting, MP management,
skill-up items, job-specific handling, and an in-game settings
interface.

> **Source:** `skillup.lua` version `0.0.1.0`, authored by Aryden. The
> addon registers the `skillup` and `su` commands.


## Features

-   Automated skill-up rotations for:
    -   Healing Magic
    -   Enhancing Magic
    -   Ninjutsu
    -   Singing
    -   Blue Magic
    -   Summoning Magic
    -   Geomancy
    -   Elemental Magic
    -   Dark Magic
    -   Divine Magic
    -   Enfeebling Magic
-   Per-character spell selections and settings.
-   In-game settings UI with category tabs and spell checkboxes.
-   Main status panel showing current mode, skill level/cap status, run
    state, skill-ups per hour, and total skill-ups.
-   Optional Moogle Trust support when solo.
-   Optional Geo Refresh / Indi-Refresh support.
-   Optional skill-up item usage.
-   Optional MP-regain weapon skills.
-   Optional offensive spell rotations.
-   Optional requirement for an engaged target before offensive actions.
-   Party-aware targeting for spells that support party members.
-   Ninjutsu tool and optional toolbag handling.
-   Singing support for separately tracking Wind and String instrument
    skill caps.
-   Blue Magic shield-spell handling through linked job abilities.
-   Summoning-specific Avatar's Favor / spirit handling.
-   Automatic stopping when configured skill caps are reached.
-   Test mode that ignores skill caps.
-   Debug logging for action events, action messages, party state, and
    skill-up message matching.

The supported categories are defined directly in the addon and exposed
through the main menu. fileciteturn1file0L42-L60

## Requirements

The file is written as a Windower Lua addon and depends on Windower APIs
plus the following Lua modules:

-   `packets`
-   `resources`
-   `texts`
-   `images`

The spell library is loaded from `libs/spell_library.lua`, while the UI
uses `icons/background.png` for its panel backgrounds.


## Installation

Place the addon in your Windower addons directory so the resulting
structure is approximately:

```
addons/
└── SkillUp/
    ├── skillup.lua
    ├── settings.lua
    ├── libs/
    │   └── spell_library.lua
    └── icons/
        └── background.png
```

On first load for a character, SkillUp creates:

data/<character>/settings.lua

by copying the addon's root `settings.lua` template. This makes the
configurable spell lists and options character-specific.

The addon also uses:

data/<character>/Saves/

for saved UI position data and debugging output.

## Settings

SkillUp provides an in-game settings panel with these main tabs:


Main
Globals
Healing
Geomancy
Enhancing
Ninjutsu
Singing
Blue
Summoning
Elemental
Dark
Divine
Enfeebling
Help


Each skill category can contain selectable spells. The selected spells
become the rotation used by the addon.

### Global options

The Globals tab provides:

  -----------------------------------------------------------------------
  Option                              Purpose
  ----------------------------------- -----------------------------------
  Use Moogle Trust                    Summons Moogle when the character
                                      is solo and the Trust is available.

  Use Geo's Refresh                   Uses Geo-Refresh or Indi-Refresh to
                                      help maintain MP.

  Use Skill Up Item                   Uses configured skill-up items when
                                      available.

  Use MP Regain WS                    Uses an MP-restoring weapon skill
                                      when the configured MP threshold is
                                      reached.

  Use Offensive Spells                Enables enemy-targeted spells from
                                      the Offensive whitelist.

  Require Engaged Target              Requires the player to be engaged
                                      before offensive actions are used.
  -----------------------------------------------------------------------

These options are defined in `GLOBAL_TOGGLE_DEFS`.
fileciteturn2file0L21-L32

### Ninjutsu

Ninjutsu can optionally open a Toolbag when the required loose ninja
tool is not present in inventory. The addon checks the primary tool
first and then the universal tool. fileciteturn2file0L475-L495

The actual tool mappings are supplied by `NINJUTSU_TOOL_MAP` and
`TOOLBAG_MAP`; those tables are not included in the portions of the
source documentation represented here, so their complete contents should
be treated as project-specific configuration.

### Singing

Singing can track:

-   Singing skill
-   Wind Instrument skill
-   Stringed Instrument skill

Wind and String tracking can be individually enabled or disabled. The
addon does **not** automatically swap instruments; the appropriate
instrument must be equipped manually if that skill is being tracked.
fileciteturn2file0L33-L39 fileciteturn2file0L497-L523

### Blue Magic

Three Blue Magic spells receive special handling:

Harden Shell
Pyric Bulwark
Carcharian Verve


These spells are associated with job-ability handling rather than being
cast directly as ordinary skill-up spells. fileciteturn1file0L29-L35

### Offensive spells

Enemy-targeted spells are only accepted when offensive spell use is
enabled and the spell appears in the configured `user_spells.Offensive`
list. The addon can also require the player to be engaged before such
spells are considered castable. fileciteturn1file0L338-L350

## Spell Selection

When a category is started, SkillUp scans the game's spell resources and
filters spells according to:

1.  The selected skill category.
2.  Whether the current main job or subjob can use the spell.
3.  Whether the spell's target type is valid.
4.  Whether offensive spell use is enabled for enemy-targeted spells.
5.  Whether the spell is included in the user's whitelist.
6.  Whether the character actually owns the spell.
7.  Whether the spell is excluded because it is a
    movement/teleport/escape-style spell or another explicitly excluded
    spell.

The source explicitly excludes spells matching:


Teleport-*
Warp*
Tractor*
Retrace
Escape
Geo-*
Sacrifice
Odin
Alexander
Recall-*



## Targeting

Self-targeted spells normally use:


<me>


Spells that target enemies use:

``` text
<t>
```

Party-compatible self/party spells can cycle through live party members
using:

``` text
<p1>
<p2>
<p3>
<p4>
<p5>
```

The addon checks that the party member has a valid mob object and is
still targetable/alive before selecting them.
fileciteturn1file0L346-L350 fileciteturn1file0L593-L629

If an enemy-targeted spell is next in the rotation but no valid target
is available, the addon skips forward through the rotation until it
finds a usable target or exhausts the available spells.
fileciteturn1file0L631-L647

## MP Management

SkillUp contains several layers of MP management.

### MP-regain weapon skills

When enabled, the addon can use:

-   **Dagger:** Energy Drain, Energy Steal
-   **Club:** Mystic Boon, Starlight, Moonlight
-   **Staff:** Spirit Taker

The weapon skill must be available, the player must have at least 1000
TP, and a valid enemy target must exist. fileciteturn1file0L504-L557

### Spell affordability

Before casting the next rotation spell, SkillUp checks whether the
player has enough MP. It reserves an additional 25 MP and skips the
spell when necessary. If the entire remaining rotation is unaffordable,
the addon allows the player to rest instead of endlessly cycling.
fileciteturn1file0L694-L716

### Refresh support

The addon can use:

-   Geo-Refresh when GEO is the main job.
-   Indi-Refresh when GEO is the subjob.
-   Refresh when RDM is subjob and the required subjob level is
    available.
-   Haste when RDM or WHM is subjob.

fileciteturn1file0L724-L760

## Skill-Cap Detection

The addon stops automatically when the selected skill reaches its
configured cap unless Test Mode is enabled.

For most magic skills it checks the corresponding `... Magic Capped`
value.

Ninjutsu uses:

``` text
Ninjutsu Capped
```

Geomancy requires both:

``` text
Geomancy Capped
Handbell Capped
```

Singing requires:

``` text
Singing Capped
```

plus whichever Wind/String instrument tracking options are enabled.
fileciteturn1file0L559-L585

### Test Mode

Test Mode disables the normal cap-stop behavior:

``` text
//skillup settestmode
```

This is intended for testing and allows the rotation to continue beyond
the normal skill cap. fileciteturn1file0L431-L433

## Cast Tracking

The addon tracks pending spell casts so it can distinguish successful
casts from interruptions.

For spells, the `action` event is used to observe the cast sequence:

-   Category `8` is used to observe the casting state.
-   A subsequent category `8` can be interpreted as an interruption.
-   Category `4` is treated as a successful cast.

Non-spell actions use a timeout safety mechanism because their
resolution categories are not confirmed by the source's own comments.


If a spell is interrupted, SkillUp generally retries it. It has special
handling when the target died, became invalid, or offensive casting is
no longer possible.

## Skill-Up Tracking

Skill-up gains are detected from incoming chat text. The addon strips
FFXI color-control sequences before attempting to match messages such as
a player's skill rising.

Each gain is stored with a timestamp, and the addon calculates an
approximate skill-ups-per-hour rate using the last hour of recorded
gains.

The Main panel displays:

-   Current skill-up mode
-   Current skill level/cap state
-   Running/stopped state
-   Skill-ups per hour
-   Total skill-ups

fileciteturn1file0L862-L909

## Persistence

### Character settings

The addon creates a character-specific settings file:

``` text
data/<character>/settings.lua
```

The first time the character runs SkillUp, the root `settings.lua` is
copied into that location. fileciteturn1file0L949-L964

The in-game Save button writes the spell selections, global toggles,
Singing tracking options, toolbag option, and MP threshold back to the
character's settings file. fileciteturn2file0L750-L837

> **Warning:** Saving through the in-game settings menu regenerates the
> settings file and removes hand-added comments beyond the generated
> header. Hand editing is supported, but saving through the UI will
> rewrite the file.

### UI position

The panel position is stored in:

``` text
data/<character>/Saves/skillup_data.lua
```

and restored when the addon loads. fileciteturn1file0L180-L188
fileciteturn1file0L967-L974

## User Interface

The settings window is a persistent, draggable panel. It contains:

-   Main category tabs
-   Category sub-tabs
-   Spell selection grids
-   Global options
-   Singing-specific controls
-   Ninjutsu-specific controls
-   Help tab
-   Save / Cancel controls
-   A Main-tab status display
-   Hide/show controls

The panel is dynamically resized around its current contents and
constrained to remain on-screen. fileciteturn2file0L227-L264
fileciteturn2file0L597-L747

The panel can be dragged as one unit, with its position retained for
subsequent sessions.


## Commands

The addon registers these command aliases:

//skillup
//su


### Start a skill-up category


//skillup start Healing
//skillup start Enhancing
//skillup start Ninjutsu
//skillup start Singing
//skillup start Blue
//skillup start Summoning
//skillup start Geomancy
//skillup start Elemental
//skillup start Dark
//skillup start Divine
//skillup start Enfeebling


Starting a category rebuilds the rotation from spells available to the
current job/subjob and from the configured whitelist. Spells the
character does not possess are reported, and the run stops if no usable
spells remain. fileciteturn1file0L352-L400

### Stop

``` text
//skillup skillstop
```

Stops the skill-up process. fileciteturn1file0L411-L412

### Show / hide the settings panel

``` text
//skillup show
//skillup hide
```

The panel can also be hidden using its `[X]` button.
fileciteturn2file0L950-L969

### Set MP-regain WS threshold

``` text
//skillup setthreshold 50
```

The supported threshold values are:

``` text
5, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100
```

The threshold represents the player's MP percentage at or below which an
available MP-restoring weapon skill can be used.
fileciteturn2file0L21-L32

### Toggle options

``` text
//skillup settrust
//skillup setgeo
//skillup setitem
//skillup setmpws
//skillup setoffensive
//skillup setengaged
//skillup settrackwind
//skillup settrackstring
//skillup settoolbags
//skillup settestmode
```

These correspond to the global and category-specific settings exposed by
the UI.


## Debugging

SkillUp includes several debugging commands.

### MP-regain debugging

``` text
//skillup mpwsdebug
```

Reports:

-   Current MP-regain WS setting
-   Current MP percentage
-   Configured threshold
-   Enemy-target availability
-   TP
-   Main weapon skill
-   Candidate weapon skills
-   Selected ready weapon skill

fileciteturn1file0L438-L447

### Party debugging

``` text
//skillup partydebug
```

Writes party-target information to:

``` text
data/<character>/Saves/skillup_debug.log
```

It records party members, HP, mob availability, targetability, live
party targets, rotation position, and the current spell target.
fileciteturn1file0L448-L469

### Action-message debugging

``` text
//skillup actionmsgdebug
```

Enables logging of relevant incoming text and action-message information
to `skillup_debug.log`. This is useful when diagnosing skill-up message
matching or action-message behavior. fileciteturn1file0L470-L475

### Action-event capture

``` text
//skillup actioncapture
```

Captures Windower `action` event data, including:

-   Actor ID
-   Action category
-   Action parameter
-   Target IDs
-   Action message IDs
-   Action parameters
-   Additional-effect information

The data is written to `skillup_debug.log`.
fileciteturn1file0L237-L250 fileciteturn1file0L314-L320

## Runtime Flow

At a high level, the addon operates like this:

``` text
Load addon
   │
   ├── Load character settings
   ├── Initialize skill state
   ├── Load spell library
   ├── Restore saved UI position
   └── Create settings UI
          │
          ▼
     Start category
          │
          ├── Build valid spell list
          ├── Apply user whitelists
          ├── Check job/subjob availability
          ├── Determine targets
          └── Begin rotation
                 │
                 ▼
          Decide next action
                 │
       ┌─────────┼─────────┐
       ▼         ▼         ▼
   MP WS       Support    Skill-up
   needed?     action?    spell
       │         │         │
       └─────────┼─────────┘
                 ▼
           Execute action
                 │
                 ▼
          Track result
          /          \
      success       interrupt
        │              │
        ▼              ▼
   Advance/decide   Retry/skip
        │              │
        └──────┬───────┘
               ▼
          Check skill cap
               │
       ┌───────┴────────┐
       ▼                ▼
    Continue           Stop
```

The core decision loop prioritizes special cases such as Summoning pet
requirements, MP-regain weapon skills, insufficient MP, Moogle Trust,
skill-up items, GEO refresh, RDM Refresh/Haste, and finally the selected
skill-up rotation. fileciteturn1file0L670-L762

## Important Implementation Notes

### Action events are currently spell-focused

The source explicitly notes that action-event confirmation is
established for spells, while job abilities, weapon skills, and item
actions use an eight-second timeout as a safety net.
fileciteturn3file0L131-L139

### Skill-up detection depends on chat text

The total skill-up counter is driven by matching the player's skill-rise
message in incoming text. If a server/client localization or message
format differs from the expected English pattern, this portion may
require adjustment. The source currently uses the English-language form
of the player's skill-rise message. fileciteturn3file0L72-L96

### Settings are character-specific

The addon deliberately loads settings after the character name becomes
available instead of requiring the settings module at parse time. This
is necessary because the settings path is based on the current character
name. fileciteturn1file0L21-L25

## File/Directory Overview

``` text
SkillUp/
├── skillup.lua                 # Main addon implementation
├── settings.lua                # Root/default settings template
├── libs/
│   └── spell_library.lua       # Spell grouping/library used by the UI
├── icons/
│   └── background.png          # UI panel background
└── data/
    └── <character>/
        ├── settings.lua         # Character-specific settings
        └── Saves/
            ├── skillup_data.lua
            └── skillup_debug.log
```

The exact contents and structure of `settings.lua`, `spell_library.lua`,
`NINJUTSU_TOOL_MAP`, and `TOOLBAG_MAP` should be documented separately
if those files are part of the addon distribution; they are
dependencies/references from `skillup.lua` rather than being fully
defined in the source examined here.

## Credits

-   **Addon:** SkillUp
-   **Author:** Aryden
-   **Version:** 0.0.1.0

fileciteturn1file0L11-L14

## Disclaimer

This README documents the behavior implemented in the supplied
`skillup.lua`. It intentionally does not invent installation
dependencies, configuration values, mappings, or behaviors that are not
supported by the source file.
