-- ============================================================
-- SkillUp addon -- generic utilities
-- ============================================================
-- Addon-agnostic helper functions: file I/O, geometry, text-size
-- estimation, and small list/table operations. Nothing in this file
-- reads or writes any SkillUp-specific state (addon_state, rotation_state,
-- settings_ui, settings_state) -- only FFXI/Windower-specific readers
-- live in libs/ffxi_helpers.lua, and everything else stays in
-- skillup.lua itself.

-- Function: ensure_dir_path
-- Description: Creates every directory level in a path that doesn't
--   already exist, one level at a time (windower.create_dir only
--   creates a single level, so this walks the path piece by piece).
-- Parameters:
--   path (string) - the full directory path to ensure exists, e.g.
--     "C:/Windower4/addons/skillup/data/CharacterName"
-- Returns: none
function ensure_dir_path(path)
    local accum = nil
    for part in path:gmatch('[^/\\]+') do
        accum = accum and (accum..'/'..part) or part
        if not windower.dir_exists(accum) then
            windower.create_dir(accum)
        end
    end
end

-- Function: file_exists
-- Description: Checks whether a file exists and is readable, using a
--   plain Lua io.open probe (Windower has no dedicated "file exists"
--   API, unlike windower.dir_exists for directories).
-- Parameters:
--   path (string) - full path to the file to check
-- Returns: boolean - true if the file could be opened for reading
function file_exists(path)
    local f = io.open(path, 'r')
    if f then
        f:close()
        return true
    end
    return false
end

-- Function: copy_file
-- Description: Copies the full contents of one file to another,
--   overwriting the destination if it already exists.
-- Parameters:
--   src (string) - path to the source file to read
--   dst (string) - path to the destination file to write
-- Returns: boolean - true if the copy succeeded, false if either file
--   could not be opened
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

-- Function: point_in_padded_bounds
-- Description: Manual hit-test for whether a screen point falls within
--   a text object's padded bounding box. Used for tab click/hover
--   detection, since inactive tabs have no background image object of
--   their own to hover-test against (only the active tab's highlight
--   image exists) -- the padding amounts (-4 on X, -2 on Y) match the
--   offsets used when drawing the tab highlight rectangles.
-- Parameters:
--   t (texts object) - the text object whose position anchors the box
--   x (number) - the point's screen X coordinate to test
--   y (number) - the point's screen Y coordinate to test
--   width (number) - width of the padded bounding box
--   height (number) - height of the padded bounding box
-- Returns: boolean - true if (x, y) falls within the padded box
function point_in_padded_bounds(t, x, y, width, height)
    local tx, ty = t:pos()
    return x >= tx - 4 and x <= tx - 4 + width and y >= ty - 2 and y <= ty - 2 + height
end

-- Function: estimate_text_size
-- Description: Estimates the rendered width/height of a text string
--   from its character count, rather than measuring it via
--   texts.extents() -- calling extents() immediately after creating or
--   changing a text object's content (same tick) returns stale/zero
--   values before Windower has actually rendered a frame, which
--   previously collapsed this addon's whole settings layout to one
--   point. This is less pixel-precise than a real measurement but is
--   immediate and deterministic. The multiplier is a deliberately
--   generous estimate for 'Segoe UI Symbol' at the sizes this UI uses,
--   erring toward extra space rather than overlap.
-- Parameters:
--   str (string) - the text to measure, including any \cs()/\cr color
--     codes (these are stripped out before measuring so they don't
--     inflate the character count)
--   font_size (number) - the font size the text will be rendered at
-- Returns: width (number), height (number) - estimated pixel dimensions
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

-- Function: clamp_panel_position
-- Description: Constrains a screen coordinate pair so a draggable panel
--   can't be dragged off-screen, using the current display resolution.
--   Leaves a 200px margin so the panel can't be dragged so far that it
--   becomes impossible to grab again.
-- Parameters:
--   x (number) - proposed X position
--   y (number) - proposed Y position
-- Returns: x (number), y (number) - the clamped position (unchanged if
--   screen resolution couldn't be read, or if already within bounds)
function clamp_panel_position(x, y)
    local screen = windower.get_windower_settings()
    if not screen then return x, y end
    local x_max = math.max(0, screen.x_res - 200)
    local y_max = math.max(0, screen.y_res - 200)
    x = math.min(math.max(x, 0), x_max)
    y = math.min(math.max(y, 0), y_max)
    return x, y
end

-- Function: queues_equal
-- Description: Compares two ordered lists of category names for exact
--   equality (same length, same values, same order). Used to decide
--   whether the checked category boxes still match an existing
--   skill-up queue, or whether they've changed and the queue needs to
--   be rebuilt from scratch.
-- Parameters:
--   a (table) - first list of strings
--   b (table) - second list of strings
-- Returns: boolean - true if both lists are identical element-for-element
function queues_equal(a, b)
    if #a ~= #b then return false end
    for i = 1, #a do
        if a[i] ~= b[i] then return false end
    end
    return true
end

-- Function: get_rate
-- Description: Computes an hourly rate from a table of {timestamp =
--   amount} entries recorded via os.clock(), extrapolating whatever's
--   been earned in the tracked window out to a full hour rather than
--   just summing raw totals (which would only be a true hourly rate
--   once a full hour had actually elapsed). Also prunes any entries
--   older than one hour as a side effect, so the tracking table doesn't
--   grow unbounded over a long play session.
-- Parameters:
--   tab (table) - a table of [timestamp] = amount entries, mutated in
--     place to remove entries older than 3600 seconds
-- Returns: number - the extrapolated hourly rate, or 0 if the table is
--   empty or everything in it has already expired
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