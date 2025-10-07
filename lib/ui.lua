-- lib/ui.lua — compact UI helpers (two-column everywhere)
-- - Menus pushed down a bit
-- - Vertical status lamps (A, B, 1, 2)
-- - Pattern bar spans full bottom width
-- - Mod page uses same two-column layout as A/B (no special reordering)

local UI = {}

----------------------------------------------------------------
-- Screen + layout constants
----------------------------------------------------------------
local SCREEN_W, SCREEN_H = 128, 64

-- Frame + general offsets
UI.FRAME_MARGIN      = 1
UI.CONTENT_Y_OFFSET  = 4        -- Push ALL menus down by this many pixels
UI.BASE_Y0           = 22       -- Base Y for first row before offset
UI.LINE_HEIGHT       = 9        -- Row spacing

-- For Mix (legacy alias kept for clarity)
UI.TOP_PAD           = 16       -- Top padding baseline (used by mix bars)

-- Tabs (top row)
UI.TAB_FONT_SIZE     = 7
UI.TAB_Y             = 11
UI.TAB_PAD_X         = 6
UI.TAB_SEL_INSET     = 3

-- Separator line under tabs
UI.SEP_Y             = 16

-- Default two-column X positions
UI.X_LEFT            = 3
UI.X_RIGHT           = 64       -- Right column (generic two-col pages)

-- Beats + Mod can be tighter if desired:
UI.BEAT_X_RIGHT      = 55
UI.MOD_X_RIGHT       = 55

-- Lamps (right edge)
UI.LAMP_X            = 122
UI.LAMP_Y0           = 22
UI.LAMP_DY           = 10
UI.LAMP_RADIUS       = 2
UI.LAMP_LABEL_GAP      = 4   -- distance between label text and lamp center
UI.LAMP_LINE_X_OFFSET  = 10  -- how far LEFT of the lamp the vertical line sits
UI.LAMP_LINE_VPAD      = 6   -- extra vertical padding (top/bottom) for the line

-- Pattern bar (full width at bottom)
UI.PB_MARGIN_X       = 4
UI.PB_GAP            = 1
UI.PB_HEIGHT         = 4
UI.PB_Y              = SCREEN_H - UI.FRAME_MARGIN - UI.PB_HEIGHT

----------------------------------------------------------------
-- Preconfigured XY presets (two-column pages)
----------------------------------------------------------------
UI.drone_xy = {
  xL = UI.X_LEFT,
  xR = UI.X_RIGHT,
  y0 = UI.BASE_Y0 + UI.CONTENT_Y_OFFSET,
  lh = UI.LINE_HEIGHT
}

UI.beat_xy = {
  xL = UI.X_LEFT,
  xR = UI.BEAT_X_RIGHT,
  y0 = UI.BASE_Y0 + UI.CONTENT_Y_OFFSET,
  lh = UI.LINE_HEIGHT
}

UI.mod_xy = {
  xL = UI.X_LEFT,
  xR = UI.MOD_X_RIGHT,
  y0 = UI.BASE_Y0 + UI.CONTENT_Y_OFFSET,
  lh = UI.LINE_HEIGHT
}

----------------------------------------------------------------
-- Frame + tabs
----------------------------------------------------------------
function UI.draw_frame()
  screen.level(2)
  screen.rect(1,1,SCREEN_W-2,SCREEN_H-2)
  screen.stroke()
  -- separator under the tab row
  screen.move(UI.FRAME_MARGIN+3, UI.SEP_Y)
  screen.line(SCREEN_W-(UI.FRAME_MARGIN+3), UI.SEP_Y)
  screen.stroke()
end

function UI.draw_tabs(titles, sel)
  screen.font_size(UI.TAB_FONT_SIZE)
  local x = UI.FRAME_MARGIN + 7
  for i, t in ipairs(titles) do
    local w = (#t <= 2) and 10 or 18
    screen.level(sel == i and 15 or 5)
    if sel == i then
      screen.rect(x-UI.TAB_SEL_INSET, UI.TAB_Y-8, w+UI.TAB_SEL_INSET*2, 10)
      screen.fill()
      screen.level(0)
    end
    screen.move(x + w/2, UI.TAB_Y)
    screen.text_center(t)
    x = x + w + UI.TAB_PAD_X
  end
  screen.font_size(8)
  screen.level(15)
end

-- Small headers above a two-column section (e.g., Mod page)
function UI.draw_column_headers(left, right, xy)
  screen.font_size(8)
  local y_hdr = (UI.SEP_Y + 4)        -- just below the top separator
  screen.level(15)
  screen.move(xy.xL, y_hdr); screen.text(left)
  screen.move(xy.xR, y_hdr); screen.text(right)
end

----------------------------------------------------------------
-- Two-column parameter list (generic)
-- labels[] / values[]; sel (1..#labels); xy = { xL, xR, y0, lh }
----------------------------------------------------------------
function UI.draw_two_col(labels, values, sel, xy)
  local xL, xR = xy.xL, xy.xR
  local y0, lh = xy.y0, xy.lh
  local half   = math.ceil(#labels/2)

  for i = 1, #labels do
    local is_left = (i <= half)
    local colX    = is_left and xL or xR
    local row     = is_left and i or (i - half)
    local y       = y0 + (row-1)*lh

    screen.move(colX, y)
    screen.level(sel == i and 15 or 4)
    local caret = (sel == i) and "> " or "  "
    screen.text(caret .. labels[i] .. ": " .. tostring(values[i]))
  end
end

-- Like draw_two_col, but you control how many rows go in the LEFT column.
-- If left_count >= #labels it just draws everything on the left.
-- Falls back to draw_two_col if something is missing.
function UI.draw_two_col_split(labels, values, left_count, sel, xy)
  -- Fallbacks for safety
  if not xy or not xy.xL then
    xy = UI.mod_xy or { xL = 8, xR = 60, y0 = 26, lh = 9 }
  end
  if not UI.draw_two_col then
    -- emergency basic draw to avoid a "blank" page
    local y = xy.y0 or 26
    for i = 1, #labels do
      screen.move((xy.xL or 8), y + (i-1)*(xy.lh or 9))
      screen.level(sel == i and 15 or 4)
      local caret = (sel == i) and "> " or "  "
      screen.text(caret .. tostring(labels[i]) .. ": " .. tostring(values[i] or ""))
    end
    return
  end

  local xL, xR = xy.xL, xy.xR
  local y0, lh = xy.y0, xy.lh
  local total  = #labels
  local left_n = math.max(0, math.min(left_count or 0, total))
  local right_n = total - left_n

  -- left column
  for i = 1, left_n do
    local y = y0 + (i-1)*lh
    screen.move(xL, y)
    screen.level(sel == i and 15 or 4)
    local caret = (sel == i) and "> " or "  "
    screen.text(caret .. labels[i] .. ": " .. tostring(values[i]))
  end

  -- right column
  for j = 1, right_n do
    local idx = left_n + j
    local y = y0 + (j-1)*lh
    screen.move(xR, y)
    screen.level(sel == idx and 15 or 4)
    local caret = (sel == idx) and "> " or "  "
    screen.text(caret .. labels[idx] .. ": " .. tostring(values[idx]))
  end
end

----------------------------------------------------------------
-- Pattern bar (full width bottom)
----------------------------------------------------------------
function UI.draw_pattern_bar(pattern, running, step)
  local steps = #pattern
  if steps <= 0 then return end

  local x0     = UI.PB_MARGIN_X
  local x1     = SCREEN_W - UI.PB_MARGIN_X
  local avail  = x1 - x0
  local gapsW  = (steps - 1) * UI.PB_GAP
  local cellW  = math.max(1, math.floor((avail - gapsW) / steps))
  local y      = UI.PB_Y

  local x = x0
  for i = 1, steps do
    local on = (pattern[i] == 1)
    if running and i == step then
      screen.level(on and 15 or 10)
    else
      screen.level(on and 8 or 2)
    end
    screen.rect(x, y, cellW, UI.PB_HEIGHT)
    if on then screen.fill() else screen.stroke() end
    x = x + cellW + UI.PB_GAP
  end
end

----------------------------------------------------------------
-- Simple text mix (2×2 grid) — still used in some places
----------------------------------------------------------------
function UI.draw_mix(names, values, sel)
  local xL, xR = UI.X_LEFT, UI.X_RIGHT
  local y0, lh = UI.BASE_Y0 + UI.CONTENT_Y_OFFSET, UI.LINE_HEIGHT

  for i = 1, #names do
    local left_col = (i <= 2)
    local colX     = left_col and xL or xR
    local row      = left_col and i or (i - 2)
    local y        = y0 + (row-1)*lh

    screen.move(colX, y)
    screen.level(sel == i and 15 or 4)
    local caret = (sel == i) and "> " or "  "
    screen.text(caret .. names[i] .. ": " .. values[i])
  end
end

----------------------------------------------------------------
-- Vertical status lamps (A, B, 1, 2) with slim left line
----------------------------------------------------------------
function UI.draw_status_lamps(drones_settings, beat1_on, beat2_on)
  local x  = UI.LAMP_X
  local y0 = UI.LAMP_Y0
  local dy = UI.LAMP_DY
  local r  = UI.LAMP_RADIUS

  -- vertical guide line spanning all four lamps
  local firstY = y0 + 0*dy
  local lastY  = y0 + 3*dy
  local lineX  = x - UI.LAMP_LINE_X_OFFSET
  local topY   = firstY - r - UI.LAMP_LINE_VPAD
  local botY   = lastY  + r + UI.LAMP_LINE_VPAD

  screen.level(3)
  screen.move(lineX, topY)
  screen.line(lineX, botY)
  screen.stroke()

  local function lamp(y, lbl, on)
    -- label (tight to lamp)
    screen.level(5)
    screen.move(x - UI.LAMP_LABEL_GAP, y + 2)
    screen.text_right(lbl)

    -- lamp itself
    screen.level(on and 12 or 2)
    screen.circle(x, y, r)
    screen.fill()
  end

  local a_running = drones_settings[1] and drones_settings[1].running
  local b_running = drones_settings[2] and drones_settings[2].running

  lamp(y0 + 0*dy, "A", a_running)
  lamp(y0 + 1*dy, "B", b_running)
  lamp(y0 + 2*dy, "1", beat1_on)
  lamp(y0 + 3*dy, "2", beat2_on)
end

----------------------------------------------------------------
-- Mix page: vertical list of bars (A, B, 1, 2)
-- names:  {"A","B","1","2"}
-- values: {a,b,c,d}   raw values
-- sel:    selected row (1..4)
-- maxval: value that maps to full bar (e.g. 1.5)
----------------------------------------------------------------
function UI.draw_mix_bars(names, values, sel, maxval)
  -- Use the same visual rhythm as other pages
  local x      = UI.X_LEFT
  local y      = (UI.BASE_Y0 + UI.CONTENT_Y_OFFSET) + 1
  local bar_w  = 60     -- pixel width of each bar
  local bar_h  = 7      -- pixel height
  local gap    = 2      -- vertical gap

  screen.font_size(8)

  for i=1, #names do
    local is_sel = (i == sel)
    local val    = values[i] or 0
    local pct    = 0
    if (maxval or 0) > 0 then
      pct = math.min(1, math.max(0, val / maxval))
    end

    -- label
    screen.level(is_sel and 15 or 10)
    screen.move(x, y + (i-1)*(bar_h+gap))
    screen.text(names[i])

    -- bar background
    local bx = x + 14
    local by = y - 5 + (i-1)*(bar_h+gap)
    screen.level(3)
    screen.rect(bx, by, bar_w, bar_h)
    screen.stroke()

    -- bar fill
    screen.level(is_sel and 15 or 8)
    screen.rect(bx+1, by+1, math.floor((bar_w-2)*pct), bar_h-2)
    screen.fill()

    -- numeric value at bar end
    screen.level(6)
    screen.move(bx + bar_w + 4, by + bar_h - 1)
    screen.text(string.format("%.2f", val))
  end
end

return UI
