-- lib/grid.lua — Monome-style grid + Launchpad Mini MK3 RGB (manual mode switch)
-- Cols 1–4: A/B/1/2 toggles (y=1) + vertical faders (y>=2)
-- Cols 5–6 (drones): 2=Chord, 3=Wave, 4/5=Base Hz ±, 6/7=Voices ±, 8=Options
-- Cols 7–8 (beats) : 2=Division cycle, 3=Drum type, 4/5=Tune ±, 6/7=Decay ±, 8=Options
--
-- HOW TO SWITCH MODES:
--   Set GRID_MODE = "mono" or "rgb" below, then reload the norns script.

----------------------------------------------------------------
-- CONFIG (edit here)
----------------------------------------------------------------
local GRID_MODE               = "rgb"       -- "mono" or "rgb"
local LAUNCHPAD_NAME_HINT     = "launchpad mini"

-- Flip ONLY LED output rows (to match Launchpad physical layout).
-- Input now uses only the global ORIENT mapping (no per-side flip).
local LEFT_SIDE_LED_FLIP      = true        -- affects cols 1..4
local RIGHT_SIDE_LED_FLIP     = true        -- affects cols 5..8
local RIGHT_SIDE_FLIP_PALETTE = true        -- use custom palette for cols 5..8

----------------------------------------------------------------
-- Module state
----------------------------------------------------------------
local Grid = {}

local g, running, clock_id, ctx = nil, false, nil, nil

-- page columns
local XA, XB, X1, X2         = 1, 2, 3, 4
local XP_A, XP_B, XP_1, XP_2 = 5, 6, 7, 8

-- rows
local Y_TOGGLE     = 1
local Y_FADERS_TOP = 2

local COLS, ROWS = 16, 8

-- device orientation (usually leave false)
local ORIENT = { swap=false, flip_x=false, flip_y=false }

local function _map_xy(x, y)
  local X, Y = x, y
  if ORIENT.swap   then X, Y = Y, X end
  if ORIENT.flip_x then X = COLS - X + 1 end
  if ORIENT.flip_y then Y = ROWS - Y + 1 end
  return X, Y
end

----------------------------------------------------------------
-- Per-side flip helpers
----------------------------------------------------------------
-- LED: canonical → device (apply per-side interior flip)
local function to_dev_led(cx, cy)
  local on_left  = (cx >= 1 and cx <= 4)
  local on_right = (cx >= 5 and cx <= 8)
  local X, Y     = _map_xy(cx, cy)
  local need_flip = (on_left  and LEFT_SIDE_LED_FLIP)
                 or (on_right and RIGHT_SIDE_LED_FLIP)
  if need_flip and ROWS >= 2 and Y > 1 and Y < ROWS then
    Y = ROWS - Y + 1
  end
  return X, Y
end

-- KEY: device → canonical (flip vertically only)
local function to_canon_from_dev(dx, dy)
  -- apply global orientation (if any)
  local cx, cy = _map_xy(dx, dy)

  -- flip vertically based on grid height
  local max_y = (g and g.rows and g.rows > 0) and g.rows or 8
  cy = max_y - cy + 1

  return cx, cy
end


-- You can still call this for “canonical→device for KEY” if needed elsewhere
local function to_dev_key(x, y) return _map_xy(x, y) end

----------------------------------------------------------------
-- Steps for grid nudges
----------------------------------------------------------------
local STEP = {
  base_hz   = 5,
  partials  = 1,
  detune    = 0.05,
  div       = 1,
  tune_hz   = 1,
  decay     = 0.02,
  amp       = 0.02,
}

----------------------------------------------------------------
-- Launchpad Mini MK3 RGB (Programmer mode)
----------------------------------------------------------------
local lp_tx, lp_rx = nil, nil
local LP_DEV_ID = 0x0D

-- palette
local WHITE   = {127,127,127}
local GREY    = { 80, 80, 80}
local ORANGE    = {127, 60,  0}
local ORANGE_l  = {127, 85, 20}
local RED       = {127,  0,  0}
local RED_l     = {127, 30, 30}
local YELLOW    = {127,100,  0}
local YELLOW_l  = {127,115, 20}
local BROWN     = { 90, 45, 10}
local BROWN_l   = {110, 70, 30}
local PINK      = {127,  0, 90}
local PINK_l    = {127, 40,110}
local PURPLE    = { 90,  0,127}
local PURPLE_l  = {110, 30,127}
local GREEN     = {  0,127,  0}
local GREEN_l   = { 30,127, 30}
local BLUE      = {  0,  0,127}
local BLUE_l    = { 40, 40,127}
local AQUA      = {  0,100,100}
local AQUA_l    = { 30,127,127}
local VIOLET    = { 90,  0,127}
local VIOLET_l  = {110, 30,127}

-- right-side per-row color (use DEVICE Y after LED mapping)
local function right_side_rgb_for_row(dy)
  if dy == ROWS then return YELLOW    end  -- top banner
  if dy == 2    then return BROWN     end
  if dy == 3    then return AQUA      end
  if dy == 4    then return BLUE      end
  if dy == 5    then return BLUE_l    end
  if dy == 6    then return PINK      end
  if dy == 7    then return PINK_l    end
  if dy == 1    then return ORANGE_l  end  -- bottom accent
  return GREY
end

local function _lp_find_ports()
  if not midi or not midi.devices then return nil, nil end
  local tx_port, rx_port
  for _, dev in pairs(midi.devices) do
    local name = (dev.name or ""):lower()
    if dev.port and name:find(LAUNCHPAD_NAME_HINT) then
      if not rx_port then rx_port = dev.port end
      if (not tx_port) or (dev.name:find(" 2$")) then tx_port = dev.port end
    end
  end
  if not rx_port or not tx_port then
    for _, dev in pairs(midi.devices) do
      local name = (dev.name or ""):lower()
      if dev.port and name:find("launchpad") then
        if not rx_port then rx_port = dev.port end
        if not tx_port then tx_port = dev.port end
      end
    end
  end
  return tx_port, rx_port
end

local function _lp_prog(on)
  if not lp_tx then return end
  lp_tx:send{0xF0,0x00,0x20,0x29,0x02,LP_DEV_ID,0x0E,(on and 1 or 0),0xF7}
end

local function _lp_idx_for_xy(x,y)
  local xx = math.max(1,math.min(8,x))
  local yy = math.max(1,math.min(8,y))
  return yy*10 + xx
end

-- conservative mapping for incoming notes to 8x8 (Programmer mode)
local function _lp_note_to_xy(n)
  local xA = n % 10
  local yA = math.floor(n / 10)
  if xA >= 1 and xA <= 8 and yA >= 1 and yA <= 8 then
    return xA, yA
  end
  if n >= 0 and n <= 63 then
    local rx = (n % 8) + 1
    local ry = math.floor(n / 8) + 1
    return rx, (9 - ry)
  end
  return nil, nil
end

-- Base color for each cell (choose by canonical side, sample row using device Y)
local function _cell_base_rgb(cx, cy)
  local on_right = (cx >= 5 and cx <= 8)
  local dx, dy = to_dev_led(cx, cy)

  -- top banner hues
  if dy == ROWS then
    if     dx == 1 then return RED
    elseif dx == 2 then return ORANGE
    elseif dx == 3 then return AQUA
    elseif dx == 4 then return VIOLET
    elseif dx == 5 then return RED_l
    elseif dx == 6 then return ORANGE_l
    elseif dx == 7 then return AQUA_l
    elseif dx == 8 then return VIOLET_l
    end
  end

  -- bottom accent for right side
  if dy == 1 and cx >= 5 and cx <= 8 then return ORANGE end

  -- left faders neutral vs beat faders warm
  if cx == 1 or cx == 2 then return GREY end
  if cx == 3 or cx == 4 then return YELLOW_l end

  if on_right and RIGHT_SIDE_FLIP_PALETTE then
    return right_side_rgb_for_row(dy)
  end

  return GREY
end

local function _lp_led_rgb(cx,cy,level0_15)
  if GRID_MODE ~= "rgb" or not lp_tx then return end
  local dx,dy = to_dev_led(cx,cy)
  local idx   = _lp_idx_for_xy(dx,dy)
  local base  = _cell_base_rgb(cx,cy)
  local f     = math.max(0,math.min(15, level0_15))/15
  lp_tx:send{
    0xF0,0x00,0x20,0x29,0x02,LP_DEV_ID,0x03,0x03,
    idx,
    math.floor(base[1]*f+0.5),
    math.floor(base[2]*f+0.5),
    math.floor(base[3]*f+0.5),
    0xF7
  }
end

local function _lp_all_off()
  if not lp_tx then return end
  for y=1,8 do for x=1,8 do
    local dx,dy = to_dev_led(x,y)
    local idx   = _lp_idx_for_xy(dx,dy)
    lp_tx:send{0xF0,0x00,0x20,0x29,0x02,LP_DEV_ID,0x03,0x03, idx, 0, 0, 0, 0xF7}
  end end
end

local function _lp_hello_flash()
  if GRID_MODE ~= "rgb" or not lp_tx then return end
  local base = PINK
  local f    = 12/15
  local r = math.floor(base[1]*f+0.5)
  local g = math.floor(base[2]*f+0.5)
  local b = math.floor(base[3]*f+0.5)
  for y=1,8 do for x=1,8 do
    local dx,dy = to_dev_led(x,y)
    local idx   = _lp_idx_for_xy(dx,dy)
    lp_tx:send{0xF0,0x00,0x20,0x29,0x02,LP_DEV_ID,0x03,0x03, idx, r, g, b, 0xF7}
  end end
  clock.run(function() clock.sleep(0.25); _lp_all_off() end)
end

local function _lp_open_if_rgb()
  if GRID_MODE ~= "rgb" then return end
  if lp_tx and lp_rx then return end
  local txp, rxp = _lp_find_ports()
  if txp then lp_tx = midi.connect(txp) end
  if rxp then lp_rx = midi.connect(rxp) end
  if lp_tx then _lp_prog(true) end

  if lp_rx then
    lp_rx.event = function(data)
      if GRID_MODE ~= "rgb" then return end
      local msg = midi.to_msg(data)
      if not msg then return end
      if msg.type == "note_on" and msg.vel and msg.vel > 0 then
        local x, y = _lp_note_to_xy(msg.note or 0)
        if x and y then
          local cx, cy = to_canon_from_dev(x, y)
          pcall(function() handle_press(cx, cy) end)
        end
      end
    end
  end
end

----------------------------------------------------------------
-- LED helper (RGB preferred; fallback to mono g:led)
----------------------------------------------------------------
local function led(cx, cy, v)
  local lvl = math.floor(v or 0)
  if GRID_MODE == "rgb" and lp_tx then
    _lp_led_rgb(cx, cy, lvl)
    return
  end
  if not g then return end
  local dx, dy = to_dev_led(cx, cy)
  g:led(dx, dy, lvl)
end

----------------------------------------------------------------
-- Drawing
----------------------------------------------------------------
local function draw_toggle_leds()
  local a_on = ctx and ctx.drone_is_running and ctx.drone_is_running(1)
  local b_on = ctx and ctx.drone_is_running and ctx.drone_is_running(2)
  local k_on = ctx and ctx.beat_is_on and ctx.beat_is_on(1)
  local l_on = ctx and ctx.beat_is_on and ctx.beat_is_on(2)
  led(XA, Y_TOGGLE, a_on and 15 or 6)
  led(XB, Y_TOGGLE, b_on and 15 or 6)
  led(X1, Y_TOGGLE, k_on and 15 or 6)
  led(X2, Y_TOGGLE, l_on and 15 or 6)
end

-- row 2 lights properly at max (<=)
local function draw_fader(col, val, maxv)
  maxv = maxv or 1.5
  local steps   = (ROWS - Y_FADERS_TOP)
  local t       = math.max(0, math.min(1, (val or 0) / maxv))
  local lit_cnt = math.floor(t * steps + 0.5)
  local on_level, off_level = 12, 3
  for cy = Y_FADERS_TOP, ROWS do
    local idx_from_top = ROWS - cy
    local is_on = (idx_from_top <= lit_cnt)
    led(col, cy, is_on and on_level or off_level)
  end
end

local function draw_helper_col(x)
  for cy = 1, ROWS do
    local _, dy = to_dev_led(x, cy)
    local lvl
    if dy == ROWS then
      lvl = 12
    elseif dy == 1 and x >= 5 and x <= 8 then
      lvl = 9
    else
      local frac = (dy - 1) / (ROWS - 1)
      lvl = math.floor(4 + 8*frac + 0.5) -- 4..12
    end
    led(x, cy, lvl)
  end
end

local function val_from_row(y, maxv)
  maxv = maxv or 1.5
  local cy    = math.max(Y_FADERS_TOP, math.min(ROWS, y))
  local span  = (ROWS - Y_FADERS_TOP)
  if span <= 0 then return 0 end
  local t     = (ROWS - cy) / span
  return t * maxv
end

----------------------------------------------------------------
-- Shared press handler (both modes call this)
----------------------------------------------------------------
function handle_press(cx, cy)
  if not ctx then return end
  local rev = ((ctx.k1_held and ctx.k1_held()) and -1 or 1)

  -- toggles + page nav (row 1)
  if cy == Y_TOGGLE then
    if     cx == XA   then if ctx.drone_toggle then ctx.drone_toggle(1) end; Grid.redraw(); return end
    if     cx == XB   then if ctx.drone_toggle then ctx.drone_toggle(2) end; Grid.redraw(); return end
    if     cx == X1   then if ctx.beat_toggle  then ctx.beat_toggle(1)  end; Grid.redraw(); return end
    if     cx == X2   then if ctx.beat_toggle  then ctx.beat_toggle(2)  end; Grid.redraw(); return end
    if     cx == XP_A and ctx.goto_tab then ctx.goto_tab(1); Grid.redraw(); return end
    if     cx == XP_B and ctx.goto_tab then ctx.goto_tab(2); Grid.redraw(); return end
    if     cx == XP_1 and ctx.goto_tab then ctx.goto_tab(3); Grid.redraw(); return end
    if     cx == XP_2 and ctx.goto_tab then ctx.goto_tab(4); Grid.redraw(); return end
  end

  -- faders (cols 1..4) on rows >= 2
  if cy >= Y_FADERS_TOP then
    if cx == XA and ctx.set_mix      then ctx.set_mix(1, val_from_row(cy, 1.5)); Grid.redraw(); return end
    if cx == XB and ctx.set_mix      then ctx.set_mix(2, val_from_row(cy, 1.5)); Grid.redraw(); return end
    if cx == X1 and ctx.set_beat_amp then ctx.set_beat_amp(1, val_from_row(cy, 1.5)); Grid.redraw(); return end
    if cx == X2 and ctx.set_beat_amp then ctx.set_beat_amp(2, val_from_row(cy, 1.5)); Grid.redraw(); return end
  end

  -- helper columns (5..8), rows 2..8
  if cy >= 2 then
    if cx == XP_A then
      if     cy == 2 and ctx.drone_cycle_chord then ctx.drone_cycle_chord(1, rev)
      elseif cy == 3 and ctx.drone_cycle_wave  then ctx.drone_cycle_wave(1, rev)
      elseif cy == 4 and ctx.drone_base        then ctx.drone_base(1,  STEP.base_hz)
      elseif cy == 5 and ctx.drone_base        then ctx.drone_base(1, -STEP.base_hz)
      elseif cy == 6 and ctx.drone_partials    then ctx.drone_partials(1,  STEP.partials)
      elseif cy == 7 and ctx.drone_partials    then ctx.drone_partials(1, -STEP.partials)
      elseif cy == 8 and ctx.toggle_options    then ctx.toggle_options("A")
      end
      if ctx.redraw then ctx.redraw() end; Grid.redraw(); return
    end

    if cx == XP_B then
      if     cy == 2 and ctx.drone_cycle_chord then ctx.drone_cycle_chord(2, rev)
      elseif cy == 3 and ctx.drone_cycle_wave  then ctx.drone_cycle_wave(2, rev)
      elseif cy == 4 and ctx.drone_base        then ctx.drone_base(2,  STEP.base_hz)
      elseif cy == 5 and ctx.drone_base        then ctx.drone_base(2, -STEP.base_hz)
      elseif cy == 6 and ctx.drone_partials    then ctx.drone_partials(2,  STEP.partials)
      elseif cy == 7 and ctx.drone_partials    then ctx.drone_partials(2, -STEP.partials)
      elseif cy == 8 and ctx.toggle_options    then ctx.toggle_options("B")
      end
      if ctx.redraw then ctx.redraw() end; Grid.redraw(); return
    end

    if cx == XP_1 then
      if     cy == 2 and ctx.beat_cycle_div   then ctx.beat_cycle_div(1, rev)
      elseif cy == 3 and ctx.beat_change_drum then ctx.beat_change_drum(1, rev)
      elseif cy == 4 and ctx.beat_tune        then ctx.beat_tune(1,  STEP.tune_hz)
      elseif cy == 5 and ctx.beat_tune        then ctx.beat_tune(1, -STEP.tune_hz)
      elseif cy == 6 and ctx.beat_decay       then ctx.beat_decay(1,  STEP.decay)
      elseif cy == 7 and ctx.beat_decay       then ctx.beat_decay(1, -STEP.decay)
      elseif cy == 8 and ctx.toggle_options   then ctx.toggle_options("1")
      end
      if ctx.redraw then ctx.redraw() end; Grid.redraw(); return
    end

    if cx == XP_2 then
      if     cy == 2 and ctx.beat_cycle_div   then ctx.beat_cycle_div(2, rev)
      elseif cy == 3 and ctx.beat_change_drum then ctx.beat_change_drum(2, rev)
      elseif cy == 4 and ctx.beat_tune        then ctx.beat_tune(2,  STEP.tune_hz)
      elseif cy == 5 and ctx.beat_tune        then ctx.beat_tune(2, -STEP.tune_hz)
      elseif cy == 6 and ctx.beat_decay       then ctx.beat_decay(2,  STEP.decay)
      elseif cy == 7 and ctx.beat_decay       then ctx.beat_decay(2, -STEP.decay)
      elseif cy == 8 and ctx.toggle_options   then ctx.toggle_options("2")
      end
      if ctx.redraw then ctx.redraw() end; Grid.redraw(); return
    end
  end
end

----------------------------------------------------------------
-- redraw
----------------------------------------------------------------
local function redraw()
  if g and GRID_MODE == "mono" then g:all(0) end

  draw_toggle_leds()

  local mixA = (ctx and ctx.get_mix)      and ctx.get_mix(1)      or 0
  local mixB = (ctx and ctx.get_mix)      and ctx.get_mix(2)      or 0
  local a1   = (ctx and ctx.get_beat_amp) and ctx.get_beat_amp(1) or 0
  local a2   = (ctx and ctx.get_beat_amp) and ctx.get_beat_amp(2) or 0

  draw_fader(XA, mixA, 1.5)
  draw_fader(XB, mixB, 1.5)
  draw_fader(X1, a1,   1.5)
  draw_fader(X2, a2,   1.5)

  draw_helper_col(XP_A)
  draw_helper_col(XP_B)
  draw_helper_col(XP_1)
  draw_helper_col(XP_2)

  if g and GRID_MODE == "mono" then g:refresh() end
end

function Grid.redraw() redraw() end

----------------------------------------------------------------
-- lifecycle
----------------------------------------------------------------
function Grid.setup(context)
  ctx = context

  if grid then g = grid.connect() end
  if GRID_MODE == "rgb" then
    _lp_open_if_rgb()
    _lp_hello_flash()
  end

  -- set up MONO key handler
  if g then
    if GRID_MODE == "mono" then
      function g.key(x, y, z)
        if z == 1 then
          local cx, cy = to_canon_from_dev(x, y)
          pcall(function() handle_press(cx, cy) end)
        end
      end
    else
      g.key = function() end
    end
  end

  local function safe_size()
    local c = (g and g.cols and g.cols > 0) and g.cols or 16
    local r = (g and g.rows and g.rows > 0) and g.rows or 8
    return c, r
  end
  COLS, ROWS = safe_size()
  print("grid.lua: connected", g or "LP-RGB-only", "cols", COLS, "rows", ROWS)

  if g and GRID_MODE == "mono" then g:all(0); g:led(1,1,15); g:refresh() end

  running = true
  clock_id = clock.run(function()
    while running do
      clock.sleep(0.08)
      if g then
        local nc = (g.cols and g.cols > 0) and g.cols or 16
        local nr = (g.rows and g.rows > 0) and g.rows or 8
        if nc ~= COLS or nr ~= ROWS then
          COLS, ROWS = nc, nr
          print("grid.lua: size updated →", COLS, ROWS)
        end
      end
      pcall(redraw)
    end
  end)
  print("grid.lua: clock started; mode:", GRID_MODE)
end

function Grid.set_swap_xy(b) ORIENT.swap   = (b == true); Grid.redraw() end
function Grid.set_flip_x(b)  ORIENT.flip_x = (b == true); Grid.redraw() end
function Grid.set_flip_y(b)  ORIENT.flip_y = (b == true); Grid.redraw() end

function Grid.cleanup()
  running = false
  if clock_id then pcall(clock.cancel, clock_id) end
  clock_id = nil
  if g then g:all(0); g:refresh() end
  -- keep LP in Programmer mode on exit
end

return Grid
