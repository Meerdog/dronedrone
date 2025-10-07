-- lib/grid.lua — Launchpad RGB + monome, no-flicker diff updates
-- Layout:
--  Cols 1–4: toggles on y=1 (A,B,1,2) + faders y>=2  (mix/amp)
--  Cols 5–8: helpers (y=1 = nav; y=2..8 = nudges)
-- Color:
--  Toggles: green (on) / red (off)
--  Faders:  green lit segments, dim background
--  Helpers: cyan; EXCEPTION: x=5 (page A) uses Drone A’s toggle color

local util = require "util"

local Grid = {}

-- Prefer midigrid (Launchpad). Fallback: monome grid.
local mg_ok, midigrid = pcall(require, "midigrid")
local mg = nil   -- midigrid device (0-based coords + RGB)
local g  = nil   -- monome grid   (1-based coords, 0..15 levels)

local ctx = nil
local running = false
local clock_id = nil

-- page columns
local XA, XB, X1, X2          = 1, 2, 3, 4
local XP_A, XP_B, XP_1, XP_2  = 5, 6, 7, 8
local Y_TOGGLE     = 1
local Y_FADERS_TOP = 2
local COLS, ROWS   = 16, 8

-- optional rotation
local SWAP_XY = false
function Grid.set_swap_xy(flag) SWAP_XY = (flag == true); Grid.redraw() end

-- nudge amounts
local STEP = {
  base_hz   = 5,
  partials  = 1,
  detune    = 0.05,
  div       = 1,
  tune_hz   = 1,
  decay     = 0.02,
  amp       = 0.02,
}

-- Launchpad palette (0..63 per channel)
local C = {
  off    = {0,0,0},
  red    = {63,0,0},
  green  = {0,63,0},
  cyan   = {0,63,63},
  white  = {63,63,63},
  yellow = {63,63,0},
  orange = {63,25,0},
  dim    = {6,6,6},
}

----------------------------------------------------------------
-- coord helpers
----------------------------------------------------------------
local function to_dev(x, y) if SWAP_XY then return y, x else return x, y end end
local function to_mg(x, y) return (x-1), (y-1) end
local function from_mg(x, y) return (x+1), (y+1) end

-- ---- Programmer Mode helpers (midigrid-first, SysEx fallback) ----
local function _send_sysex_if_possible(dev, bytes)
  -- midigrid devices usually expose a .midi (norns midi device)
  local ok = pcall(function() if dev and dev.midi and dev.midi.send then dev.midi:send(bytes) end end)
  if not ok and midi and dev and dev.port then
    -- ultra fallback: try norns midi port number (if device exposes it)
    local m = midi.connect(dev.port)
    if m and m.send then m:send(bytes) end
  end
end

local function enter_programmer_mode(dev)
  if not dev then return end
  -- common midigrid APIs we’ve seen across devices
  if dev.enter_programmer_mode then return dev:enter_programmer_mode() end
  if dev.programmer_mode       then return dev:programmer_mode(true)   end
  if dev.device and dev.device.enter_programmer_mode then
    return dev.device:enter_programmer_mode()
  end
  -- Launchpad Mini MK3 SysEx (enter Programmer Mode)
  -- F0 00 20 29 02 0D 0E 01 F7
  _send_sysex_if_possible(dev, {0xF0,0x00,0x20,0x29,0x02,0x0D,0x0E,0x01,0xF7})
end

local function exit_programmer_mode(dev)
  if not dev then return end
  if dev.programmer_mode then return dev:programmer_mode(false) end
  if dev.device and dev.device.exit_programmer_mode then
    return dev.device:exit_programmer_mode()
  end
  -- SysEx: leave Programmer Mode (same msg, trailing 0x00)
  -- F0 00 20 29 02 0D 0E 00 F7
  _send_sysex_if_possible(dev, {0xF0,0x00,0x20,0x29,0x02,0x0D,0x0E,0x00,0xF7})
end


----------------------------------------------------------------
-- simple framebuffer (diff → no flicker)
----------------------------------------------------------------
local fb_rgb = {}   -- [x][y] = {r,g,b} for mg
local fb_lvl = {}   -- [x][y] = 0..15    for monome

local function fb_set_rgb(x, y, rgb)
  fb_rgb[x] = fb_rgb[x] or {}
  local prev = fb_rgb[x][y]
  local same = prev and prev[1]==rgb[1] and prev[2]==rgb[2] and prev[3]==rgb[3]
  if same then return false end
  fb_rgb[x][y] = {rgb[1], rgb[2], rgb[3]}
  return true
end

local function fb_set_lvl(x, y, lvl)
  fb_lvl[x] = fb_lvl[x] or {}
  if fb_lvl[x][y] == lvl then return false end
  fb_lvl[x][y] = lvl
  return true
end

local function led(x, y, level, color)
  local dx, dy = to_dev(x, y)
  if mg then
    local rgb = color or { (level or 0)*4, (level or 0)*4, (level or 0)*4 }
    if fb_set_rgb(dx, dy, rgb) then
      local mx, my = to_mg(dx, dy)
      mg:led(mx, my, rgb)
    end
  elseif g then
    local lvl = math.max(0, math.min(15, level or 0))
    if fb_set_lvl(dx, dy, lvl) then
      g:led(dx, dy, lvl)
    end
  end
end

local function all_off()
  for x=1,COLS do
    fb_rgb[x] = {}
    fb_lvl[x] = {}
    for y=1,ROWS do
      if mg then
        local mx,my = to_mg(x,y)
        mg:led(mx,my,C.off)
      elseif g then
        g:led(x,y,0)
      end
    end
  end
  if mg then mg:refresh() end
  if g  then g:refresh()  end
end

----------------------------------------------------------------
-- draw helpers
----------------------------------------------------------------
local function draw_toggle_leds()
  local a_on  = (ctx and ctx.drone_is_running and ctx.drone_is_running(1)) or false
  local b_on  = (ctx and ctx.drone_is_running and ctx.drone_is_running(2)) or false
  local e1_on = (ctx and ctx.beat_is_on and ctx.beat_is_on(1)) or false
  local e2_on = (ctx and ctx.beat_is_on and ctx.beat_is_on(2)) or false

  if mg then
    led(XA, Y_TOGGLE, nil, a_on and C.green or C.red)
    led(XB, Y_TOGGLE, nil, b_on and C.green or C.red)
    led(X1, Y_TOGGLE, nil, e1_on and C.green or C.red)
    led(X2, Y_TOGGLE, nil, e2_on and C.green or C.red)
  else
    led(XA, Y_TOGGLE, a_on and 15 or 5)
    led(XB, Y_TOGGLE, b_on and 15 or 5)
    led(X1, Y_TOGGLE, e1_on and 15 or 5)
    led(X2, Y_TOGGLE, e2_on and 15 or 5)
  end
end

local function draw_fader(col, val, maxv)
  maxv = maxv or 1.5
  local steps = (ROWS - Y_FADERS_TOP + 1)
  local t   = math.max(0, math.min(1, (val or 0) / maxv))
  local lit = math.floor(t * steps + 0.5)
  for y = Y_FADERS_TOP, ROWS do
    local idx = ROWS - y + 1
    if mg then
      led(col, y, nil, (idx <= lit) and C.green or C.dim)
    else
      led(col, y, (idx <= lit) and 12 or 3)
    end
  end
end

local function draw_helper_col(x)
  if mg then
    -- x=5 (Page A) adopts Drone A’s toggle color
    local a_on = (ctx and ctx.drone_is_running and ctx.drone_is_running(1)) or false
    local a_nav_color = (x == XP_A) and (a_on and C.green or C.red) or C.cyan
    led(x, 1, nil, a_nav_color)
    for y=2,ROWS do led(x, y, nil, C.dim) end
  else
    led(x, 1, 10); for y=2,ROWS do led(x, y, 4) end
  end
end

----------------------------------------------------------------
-- public redraw (diff-based; no clearing → no flicker)
----------------------------------------------------------------
function Grid.redraw()
  if not (mg or g) then return end

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

  if mg then mg:refresh() end
  if g  then g:refresh()  end
end

----------------------------------------------------------------
-- actions (unchanged)
----------------------------------------------------------------
local function goto_tab(ix) if ctx and ctx.goto_tab then ctx.goto_tab(ix) end end

local function val_from_row(y, maxv)
  maxv = maxv or 1.5
  local steps = (ROWS - Y_FADERS_TOP + 1)
  local pos   = math.max(Y_FADERS_TOP, math.min(ROWS, y))
  local idx   = ROWS - pos + 1
  return (idx / steps) * maxv
end

local function handle_press(cx, cy)
  -- col 1..4 toggles
  if cx == XA and cy == Y_TOGGLE then if ctx.drone_toggle then ctx.drone_toggle(1) end; Grid.redraw(); return end
  if cx == XB and cy == Y_TOGGLE then if ctx.drone_toggle then ctx.drone_toggle(2) end; Grid.redraw(); return end
  if cx == X1 and cy == Y_TOGGLE then if ctx.beat_toggle  then ctx.beat_toggle(1)  end; Grid.redraw(); return end
  if cx == X2 and cy == Y_TOGGLE then if ctx.beat_toggle  then ctx.beat_toggle(2)  end; Grid.redraw(); return end

  -- col 1..4 faders
  if cy >= Y_FADERS_TOP then
    if cx == XA and ctx.set_mix      then ctx.set_mix(1, val_from_row(cy, 1.5)); Grid.redraw(); return end
    if cx == XB and ctx.set_mix      then ctx.set_mix(2, val_from_row(cy, 1.5)); Grid.redraw(); return end
    if cx == X1 and ctx.set_beat_amp then ctx.set_beat_amp(1, val_from_row(cy, 1.5)); Grid.redraw(); return end
    if cx == X2 and ctx.set_beat_amp then ctx.set_beat_amp(2, val_from_row(cy, 1.5)); Grid.redraw(); return end
  end

  -- helpers: Drone A (5)
  if cx == XP_A then
    if     cy == 1 and goto_tab           then goto_tab(1)
    elseif cy == 2 and ctx.drone_base     then ctx.drone_base(1,  STEP.base_hz)
    elseif cy == 3 and ctx.drone_base     then ctx.drone_base(1, -STEP.base_hz)
    elseif cy == 4 and ctx.drone_partials then ctx.drone_partials(1,  STEP.partials)
    elseif cy == 5 and ctx.drone_partials then ctx.drone_partials(1, -STEP.partials)
    elseif cy == 6 and ctx.drone_cycle_wave then ctx.drone_cycle_wave(1, 1)
    elseif cy == 7 and ctx.drone_detune   then ctx.drone_detune(1,  STEP.detune)
    elseif cy == 8 and ctx.drone_detune   then ctx.drone_detune(1, -STEP.detune)
    end
    if ctx.redraw then ctx.redraw() end; Grid.redraw(); return
  end

  -- helpers: Drone B (6)
  if cx == XP_B then
    if     cy == 1 and goto_tab           then goto_tab(2)
    elseif cy == 2 and ctx.drone_base     then ctx.drone_base(2,  STEP.base_hz)
    elseif cy == 3 and ctx.drone_base     then ctx.drone_base(2, -STEP.base_hz)
    elseif cy == 4 and ctx.drone_partials then ctx.drone_partials(2,  STEP.partials)
    elseif cy == 5 and ctx.drone_partials then ctx.drone_partials(2, -STEP.partials)
    elseif cy == 6 and ctx.drone_cycle_wave then ctx.drone_cycle_wave(2, 1)
    elseif cy == 7 and ctx.drone_detune   then ctx.drone_detune(2,  STEP.detune)
    elseif cy == 8 and ctx.drone_detune   then ctx.drone_detune(2, -STEP.detune)
    end
    if ctx.redraw then ctx.redraw() end; Grid.redraw(); return
  end

  -- helpers: Euclid 1 (7)
  if cx == XP_1 then
    if     cy == 1 and goto_tab            then goto_tab(3)
    elseif cy == 2 and ctx.beat_cycle_div  then ctx.beat_cycle_div(1,  1)
    elseif cy == 3 and ctx.beat_cycle_div  then ctx.beat_cycle_div(1, -1)
    elseif cy == 4 and ctx.beat_tune       then ctx.beat_tune(1,  STEP.tune_hz)
    elseif cy == 5 and ctx.beat_tune       then ctx.beat_tune(1, -STEP.tune_hz)
    elseif cy == 6 and ctx.beat_decay      then ctx.beat_decay(1,  STEP.decay)
    elseif cy == 7 and ctx.beat_decay      then ctx.beat_decay(1, -STEP.decay)
    elseif cy == 8 and ctx.beat_amp        then
      local d = (ctx.k1_held and ctx.k1_held()) and -STEP.amp or STEP.amp
      ctx.beat_amp(1, d)
    end
    if ctx.redraw then ctx.redraw() end; Grid.redraw(); return
  end

  -- helpers: Euclid 2 (8)
  if cx == XP_2 then
    if     cy == 1 and goto_tab            then goto_tab(4)
    elseif cy == 2 and ctx.beat_cycle_div  then ctx.beat_cycle_div(2,  1)
    elseif cy == 3 and ctx.beat_cycle_div  then ctx.beat_cycle_div(2, -1)
    elseif cy == 4 and ctx.beat_tune       then ctx.beat_tune(2,  STEP.tune_hz)
    elseif cy == 5 and ctx.beat_tune       then ctx.beat_tune(2, -STEP.tune_hz)
    elseif cy == 6 and ctx.beat_decay      then ctx.beat_decay(2,  STEP.decay)
    elseif cy == 7 and ctx.beat_decay      then ctx.beat_decay(2, -STEP.decay)
    elseif cy == 8 and ctx.beat_amp        then
      local d = (ctx.k1_held and ctx.k1_held()) and -STEP.amp or STEP.amp
      ctx.beat_amp(2, d)
    end
    if ctx.redraw then ctx.redraw() end; Grid.redraw(); return
  end
end

local function key_mg(x, y, z)  -- midigrid (0-based)
  if z ~= 1 then return end
  local ox, oy = from_mg(x, y)
  handle_press( ox, oy )
end

local function key_g(x, y, z)   -- monome (1-based)
  if z ~= 1 then return end
  handle_press( x, y )
end

----------------------------------------------------------------
-- lifecycle
----------------------------------------------------------------
function Grid.setup(context)
  ctx = context

  -- Connect midigrid first (Launchpad RGB)
  if mg_ok and midigrid and midigrid.connect then
    mg = midigrid.connect()
    if mg then
      print("grid.lua: midigrid connected: " .. (mg.name or "device"))

      -- >>> ensure Programmer Mode is engaged <<<
      enter_programmer_mode(mg)

      mg.key = key_mg
      COLS = 8; ROWS = 8  -- LP Mini mk3 in Programmer Mode is 8x8
    end
  end

  -- Fallback to monome grid
  if not mg and grid and grid.connect then
    g = grid.connect()
    if g then
      print("grid.lua: monome grid connected")
      g.key = key_g
      COLS = g.cols or COLS
      ROWS = g.rows or ROWS
    end
  end

  if not (mg or g) then
    print("grid.lua: no grid device; skipping setup")
    return
  end

  -- One-time paint; after that, Grid.redraw() only updates diffs
  all_off()
  Grid.redraw()

  -- gentle refresher so it follows encoder/K2/K3 changes
  running = true
  clock_id = clock.run(function()
    while running do
      clock.sleep(0.15)
      Grid.redraw()
    end
  end)
end

function Grid.cleanup()
  running = false
  if clock_id then pcall(clock.cancel, clock_id) end
  clock_id = nil
  all_off()
  if mg then exit_programmer_mode(mg) end
end


return Grid
