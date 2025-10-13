-- dronedrone.lua
-- Two drifting drones (A/B) + two Euclidean beatmakers (1/2).
-- UI pages: A, B, 1, 2, Mod, Mix. FX are params-only (no FX page).
--
-- Keys:
--   K2 = toggle the focused thing (drone or beat)
--   K3 = global PANIC (kills all drones/voices, stops beats)
--   K1+K3 = save params to autosave
--   K2+K3 = open presets
-- Engine: Dromedary2 (SC). Mix control uses setLevelRange/noteOffRange for safety.

engine.name = "Dromedary2"

local util = require "util"
local cs   = require "controlspec"

local Params = include("lib/params")
local UI     = include("lib/ui")
local Grid = include("lib/grid")

-- =========================================================
-- Globals / config
-- =========================================================
local DRONES = 2
local drone_names = {"A","B"}
-- Tabs: A, B, 1 (beat1), 2 (beat2), Mod (LFO+Sub), Mix
local tab_titles  = {"A","B","1","2","Mod","Mix"}

-- Voice-id spacing so partials across drones never collide
local drone_voice_offset = {0, 32}
local VOICE_SPAN = 32

-- UI state
local tab_selected, param_selected = 1, 1
local k1_held = false
local preset_ui = { active = false, sel = 1 }

-- prevents a double K2 press from immediately re-triggering
-- (note: not currently used; leaving here if you want stricter debouncing)
local last_toggle = {0, 0}
local TOGGLE_DEBOUNCE = 0.20 -- seconds

-- remember when we last stopped a drone; guards against re-triggering tails
local last_stop = {0, 0}
local STOP_COOLDOWN = 0.30

-- =========================================================
-- Engine mix & FX (FX are driven via params; not shown on UI)
-- =========================================================
local base_main_level = 1.0

local subosc_level    = 0.5
local subosc_detune   = 0.0
local subosc_wave     = 1

local chorus_mix      = 0.2
local noise_level     = 0.1
local fx_cutoff       = 12000
local fx_resonance    = 0.20
local rvb_mix         = 0.25
local rvb_room        = 0.60
local rvb_damp        = 0.50

-- =========================================================
-- Global LFO (engine-level target: Resonance, Amp, or Pan)
-- =========================================================
local lfo_on, lfo_target, lfo_wave, lfo_freq, lfo_depth =
  true, 1, 1, 2.0, 0.20
local lfo_clock, lfo_phase = nil, 0.0

-- =========================================================
-- Beats (two Euclidean sub-kicks)
-- =========================================================
local beat_divs = {1, 1/2, 1/4, 1/8}

-- Beat 1
local beat1_on = false
local beat1_steps, beat1_fills, beat1_rotate = 16, 5, 0
local beat1_div_ix = 3 -- 1/1,1/2,1/4,1/8
local beat1_kick_hz, beat1_kick_decay = 48, 0.60
beat1_amp = beat1_amp or 0.95   -- persisted via params (global var so params keep it)
local beat1_clock, beat1_step = nil, 1
local beat1_pat = {}
local beat1_started_at = 0

-- Beat 2
local beat2_on = false
local beat2_steps, beat2_fills, beat2_rotate = 16, 8, 0
local beat2_div_ix = 3
local beat2_kick_hz, beat2_kick_decay = 55, 0.45
beat2_amp = beat2_amp or 0.95   -- persisted via params (global var so params keep it)
local beat2_clock, beat2_step = nil, 1
local beat2_pat = {}
local beat2_started_at = 0

-- =========================================================
-- Drone settings (run until stopped)
-- =========================================================
math.randomseed(os.time())
local function rand_around(val, pct)
  return val + ((math.random() - 0.5) * 2 * pct * val)
end

local drones_settings = {}
for i=1,DRONES do
  drones_settings[i] = {
    -- Tone
    base_hz  = math.floor(rand_around(360, 0.1)),
    partials = math.max(1, math.floor(rand_around(3, 0.4))),
    detune   = 0.5,
    waveform = math.random(1,4),

    -- ADSR
    attack   = 0.60,
    decay    = 1.00,
    sustain  = 0.80,
    release  = 2.50,

    -- Per-drone mix (0..1.5)
    mix      = 0.70,

    -- Runtime flags/state
    running  = false,
    launched = {},    -- the exact voice ids we started
    drone_id = nil,
    drone_start = 0,
  }
end

-- =========================
-- Safe clock helpers (robust)
-- =========================
local function safe_cancel(id)
  -- norns clock.cancel is tolerant; just try if we have *anything*
  if id ~= nil then pcall(clock.cancel, id) end
end

local function defer(sec, fn)
  -- Defensive delay (doesn't assume anything about 'sec')
  return clock.run(function()
    local t = tonumber(sec) or 0
    while t > 0 do
      local dt = (t > 0.1) and 0.1 or t
      clock.sleep(dt)
      t = t - dt
    end
    if fn then fn() end
  end)
end


-- =========================================================
-- Engine helpers (ADSR / per-drone mix / global mix+fx)
-- =========================================================
local function apply_env(slot)
  -- send current ADSR to engine for *new* voices
  engine.attack(slot.attack or 0.6)
  engine.decay(slot.decay or 1.0)
  engine.sustain(slot.sustain or 0.8)
  engine.release(slot.release or 2.5)
end

local function apply_drone_mix(slot_num)
  -- set post-chain per-voice range level (preferred over amp)
  local base = drone_voice_offset[slot_num]
  local lvl  = drones_settings[slot_num].mix or 0.7
  if engine.setLevelRange then
    pcall(engine.setLevelRange, base + 1, base + VOICE_SPAN, lvl)
  elseif engine.setAmpRange then
    pcall(engine.setAmpRange, base + 1, base + VOICE_SPAN, lvl)
  end
end

local function set_engine_mix_and_fx()
  -- global mix / FX setters; FX live only in params menu
  pcall(engine.mainOscLevel, base_main_level)
  pcall(engine.noiseLevel,   noise_level)
  pcall(engine.chorusMix,    chorus_mix)

  pcall(engine.subOscLevel,  subosc_level)
  pcall(engine.subOscDetune, subosc_detune)
  pcall(engine.subOscWave,   subosc_wave - 1)

  -- gentle limiter safety at engine level (defaults)
  pcall(engine.limitThresh, 0.95)
  pcall(engine.limitDur, 0.01)

  if engine.cutoff    then engine.cutoff(fx_cutoff) end
  if engine.resonance then engine.resonance(fx_resonance) end

  if engine.reverbMix  then engine.reverbMix(rvb_mix)   end
  if engine.reverbRoom then engine.reverbRoom(rvb_room) end
  if engine.reverbDamp then engine.reverbDamp(rvb_damp) end
end

-- =========================================================
-- LFO (engine modulation loop)
-- =========================================================
local function lfo_val(phase, wave)
  local two_pi = math.pi * 2
  if wave == 1 then
    return math.sin(phase)
  elseif wave == 2 then
    local t = (phase % two_pi) / two_pi
    return 4 * math.abs(t - 0.5) - 1
  elseif wave == 3 then
    local t = (phase % two_pi) / two_pi
    return (2 * t) - 1
  else
    return (math.sin(phase) >= 0) and 1 or -1
  end
end

-- LFO
local lfo_clock = nil
local function stop_lfo_clock()
  safe_cancel(lfo_clock)
  lfo_clock = nil
end

local function start_lfo_clock()
  stop_lfo_clock()
  lfo_clock = clock.run(function()
    local step = 1/50
    while true do
      clock.sleep(step)
      lfo_phase = (lfo_phase + (2*math.pi) * math.max(0, lfo_freq) * step) % (2*math.pi)
      local s = lfo_val(lfo_phase, lfo_wave)
      if lfo_on then
        if     lfo_target == 1 and engine.resonance then
          local rqv = util.clamp(fx_resonance + (0.30 * lfo_depth * s), 0.05, 0.99)
          engine.resonance(rqv)
        elseif lfo_target == 2 then
          local lvl = util.clamp(base_main_level + 0.5 * lfo_depth * s, 0, 1)
          engine.mainOscLevel(lvl)
        elseif lfo_target == 3 and engine.setPanRange then
          local pan = util.clamp(lfo_depth * s, -1, 1)
          for slot = 1, DRONES do
            local base = drone_voice_offset[slot]
            pcall(engine.setPanRange, base + 1, base + VOICE_SPAN, pan)
          end
        end
      else
        engine.mainOscLevel(base_main_level)
        if engine.resonance then engine.resonance(fx_resonance) end
      end
    end
  end)
end


-- =========================================================
-- Euclidean helpers + per-beat clocks
-- =========================================================
local function euclid(steps, fills, rotate)
  local pat, bucket = {}, 0
  steps = math.max(1, steps)
  fills = util.clamp(fills, 0, steps)
  for i=1,steps do
    bucket = bucket + fills
    if bucket >= steps then bucket = bucket - steps; pat[i] = 1 else pat[i] = 0 end
  end
  local rot = ((rotate % steps) + steps) % steps
  if rot ~= 0 then
    local out = {}
    for i=1,steps do out[i] = pat[((i-1-rot) % steps)+1] end
    pat = out
  end
  return pat
end

local function refresh_beat1_pat()
  beat1_pat = euclid(beat1_steps, beat1_fills, beat1_rotate)
  if beat1_step > beat1_steps then beat1_step = 1 end
end

local function refresh_beat2_pat()
  beat2_pat = euclid(beat2_steps, beat2_fills, beat2_rotate)
  if beat2_step > beat2_steps then beat2_step = 1 end
end

-- Beat 1
local beat1_clock = nil
local function stop_beat1()
  beat1_on = false
  beat1_started_at = 0
  safe_cancel(beat1_clock)
  beat1_clock = nil
end

local function start_beat1()
  stop_beat1()
  beat1_on = true
  beat1_started_at = util.time()
  refresh_beat1_pat()
  beat1_clock = clock.run(function()
    local div = beat_divs[beat1_div_ix] or 1/4
    while beat1_on do
      clock.sync(div)
      if beat1_pat[beat1_step] == 1 then
        if engine.kick then engine.kick(beat1_amp, beat1_kick_hz, beat1_kick_decay) end
      end
      beat1_step = (beat1_step % beat1_steps) + 1
      redraw()
    end
  end)
end

-- Beat 2
local beat2_clock = nil
local function stop_beat2()
  beat2_on = false
  beat2_started_at = 0
  safe_cancel(beat2_clock)
  beat2_clock = nil
end

local function start_beat2()
  stop_beat2()
  beat2_on = true
  beat2_started_at = util.time()
  refresh_beat2_pat()
  beat2_clock = clock.run(function()
    local div = beat_divs[beat2_div_ix] or 1/4
    while beat2_on do
      clock.sync(div)
      if beat2_pat[beat2_step] == 1 then
        if engine.kick then engine.kick(beat2_amp, beat2_kick_hz, beat2_kick_decay) end
      end
      beat2_step = (beat2_step % beat2_steps) + 1
      redraw()
    end
  end)
end

local function musical_preset_names()
  local p = params:lookup_param("musical_preset_load")
  if p and p.options then
    -- drop the leading "—"
    local out = {}
    for i=2,#p.options do table.insert(out, p.options[i]) end
    if #out == 0 then out = {"(none)"} end
    return out
  end
  return {"(none)"}
end

local function open_preset_picker()
  local names = musical_preset_names()
  preset_ui.active = true
  preset_ui.sel = 1  -- first actual preset
  redraw()
end

local function close_preset_picker()
  preset_ui.active = false
  redraw()
end

-- =========================================================
-- Autosave helper
-- =========================================================
local function autosave_path()
  return norns.state.data .. "autosave.pset"
end

local function save_params_to_autosave()
  util.make_dir(norns.state.data)
  params:write(autosave_path())
  print("dronedrone: saved params → " .. autosave_path())
end

-- =========================================================
-- Param change hook (called by lib/params)
-- =========================================================
local function PARAM_SET(key, v)
  -- Engine mix/FX (FX via params only)
  if key=="main_level"     then base_main_level = v; set_engine_mix_and_fx(); redraw()
  elseif key=="sub_level"  then subosc_level = v; set_engine_mix_and_fx(); redraw()
  elseif key=="sub_detune" then subosc_detune = v; set_engine_mix_and_fx(); redraw()
  elseif key=="sub_wave"   then subosc_wave = v; set_engine_mix_and_fx(); redraw()
  elseif key=="fx_chorus"  then chorus_mix = v; set_engine_mix_and_fx(); redraw()
  elseif key=="fx_noise"   then noise_level = v; set_engine_mix_and_fx(); redraw()
  elseif key=="fx_revmix"  then rvb_mix = v; set_engine_mix_and_fx(); redraw()
  elseif key=="fx_revroom" then rvb_room = v; set_engine_mix_and_fx(); redraw()
  elseif key=="fx_revdamp" then rvb_damp = v; set_engine_mix_and_fx(); redraw()
  elseif key=="fx_cutoff"  then fx_cutoff = v; set_engine_mix_and_fx(); redraw()
  elseif key=="fx_reson"   then fx_resonance = v; set_engine_mix_and_fx(); redraw()

  -- LFO
  elseif key=="lfo_on"     then lfo_on = (v == true or v == 2); redraw()
  elseif key=="lfo_target" then lfo_target = v; redraw()
  elseif key=="lfo_wave"   then lfo_wave = v; redraw()
  elseif key=="lfo_freq"   then lfo_freq = v; redraw()
  elseif key=="lfo_depth"  then lfo_depth = v; redraw()

  -- Beat 1
  elseif key=="beat1_steps"  then beat1_steps  = v; refresh_beat1_pat(); redraw()
  elseif key=="beat1_fills"  then beat1_fills  = v; refresh_beat1_pat(); redraw()
  elseif key=="beat1_rotate" then beat1_rotate = v; refresh_beat1_pat(); redraw()
  elseif key=="beat1_div_ix" then beat1_div_ix = v; redraw()
  elseif key=="beat1_tune"   then beat1_kick_hz = v; redraw()
  elseif key=="beat1_decay"  then beat1_kick_decay = v; redraw()
  elseif key=="beat1_amp"    then beat1_amp = v; redraw()

  -- Beat 2
  elseif key=="beat2_steps"  then beat2_steps  = v; refresh_beat2_pat(); redraw()
  elseif key=="beat2_fills"  then beat2_fills  = v; refresh_beat2_pat(); redraw()
  elseif key=="beat2_rotate" then beat2_rotate = v; refresh_beat2_pat(); redraw()
  elseif key=="beat2_div_ix" then beat2_div_ix = v; redraw()
  elseif key=="beat2_tune"   then beat2_kick_hz = v; redraw()
  elseif key=="beat2_decay"  then beat2_kick_decay = v; redraw()
  elseif key=="beat2_amp"    then beat2_amp = v; redraw()
  end
end

-- =========================================================
-- Global PANIC (K3) and helpers
-- =========================================================
local function kill_range(slot_num)
  -- hard kill any leftovers in this drone's voice block
  local base = drone_voice_offset[slot_num] or 0
  local lo   = base + 1
  local hi   = base + VOICE_SPAN
  if engine.freeRange     then pcall(engine.freeRange, lo, hi) end   -- hard kill first
  if engine.setLevelRange then pcall(engine.setLevelRange, lo, hi, 0) end
  if engine.noteOffRange  then pcall(engine.noteOffRange,  lo, hi) end
end

-- Per-drone HARD kill that cannot stack or leave zombies
local function drone_hard_kill(slot_num)
  local s = drones_settings[slot_num]
  local base = drone_voice_offset[slot_num] or 0
  local lo, hi = base + 1, base + VOICE_SPAN

  -- server-side: kill first, then belt+suspenders mute+noteOff
  if engine.freeRange     then pcall(engine.freeRange, lo, hi) end
  if engine.setLevelRange then pcall(engine.setLevelRange, lo, hi, 0.0)
  elseif engine.setAmpRange then pcall(engine.setAmpRange, lo, hi, 0.0) end
  if engine.noteOffRange  then pcall(engine.noteOffRange,  lo, hi) end

  -- local state
  s.running      = false
  s.launched     = {}
  s.drone_id     = nil
  s.drone_start  = 0
  last_stop[slot_num] = util.time()
end


local function global_panic()
  -- local state reset
  for i = 1, DRONES do
    local s = drones_settings[i]
    if s then s.launched = {}; s.drone_id = nil; s.drone_start = 0; s.running = false end
  end
  stop_beat1(); stop_beat2()

  -- engine hard stop
  if engine.panic then
    pcall(engine.panic)
  else
    -- fallback across whole possible range
    local lo = (drone_voice_offset[1] or 0) + 1
    local hi = (drone_voice_offset[#drone_voice_offset] or 0) + VOICE_SPAN
    if engine.freeRange     then pcall(engine.freeRange, lo, hi) end
    if engine.setLevelRange then pcall(engine.setLevelRange, lo, hi, 0.0) end
    if engine.noteOffRange  then pcall(engine.noteOffRange,  lo, hi) end
    if engine.free_all_notes then pcall(engine.free_all_notes) end
  end
end

-- =========================================================
-- UI (draw)
-- =========================================================
function redraw()
  screen.clear()
    if Grid and Grid.redraw then Grid.redraw() end
  UI.draw_frame()
  UI.draw_tabs(tab_titles, tab_selected)
  if preset_ui.active then
    UI.draw_preset_picker("Musical Presets", musical_preset_names(), preset_ui.sel)
    screen.update()
    return
  end
if tab_selected <= 2 then
  -- Drone pages A/B — with ON checkbox (no Release param)
  local s = drones_settings[tab_selected]
  local labels = {"On","Base","Parts","Wave","Det","A","D","S"}
  local values = {
    (s.running and "[X]" or "[ ]"),
    math.floor(s.base_hz).."Hz",
    s.partials,
    ({"Sine","Tri","Saw","Square"})[s.waveform],    -- Wave moved up
    string.format("%.2f", s.detune).."",          -- Detune moved down
    string.format("%.2f", s.attack).."s",
    string.format("%.2f", s.decay).."s",
    string.format("%.2f", s.sustain),
  }
  UI.draw_two_col(labels, values, param_selected, UI.drone_xy)
  UI.draw_status_lamps(drones_settings, beat1_on, beat2_on)

  elseif tab_selected == 3 then
    -- Beat 1 page
    local labels = { "Run","Steps","Fills","Rotate","Div","Tune","Decay","Amp" }
    local values = {
      beat1_on and "[X]" or "[ ]",
      beat1_steps, beat1_fills, beat1_rotate,
      ({ "1/1","1/2","1/4","1/8" })[beat1_div_ix],
      string.format("%.0fHz", beat1_kick_hz),
      string.format("%.2f",  beat1_kick_decay),
      string.format("%.2f",  beat1_amp),
    }
    UI.draw_two_col(labels, values, param_selected, UI.beat_xy)
    UI.draw_pattern_bar(beat1_pat, beat1_on, beat1_step)
    UI.draw_status_lamps(drones_settings, beat1_on, beat2_on)

  elseif tab_selected == 4 then
    -- Beat 2 page
    local labels = { "Run","Steps","Fills","Rotate","Div","Tune","Decay","Amp" }
    local values = {
      beat2_on and "[X]" or "[ ]",
      beat2_steps, beat2_fills, beat2_rotate,
      ({ "1/1","1/2","1/4","1/8" })[beat2_div_ix],
      string.format("%.0fHz", beat2_kick_hz),
      string.format("%.2f",  beat2_kick_decay),
      string.format("%.2f",  beat2_amp),
    }
    UI.draw_two_col(labels, values, param_selected, UI.beat_xy)
    UI.draw_pattern_bar(beat2_pat, beat2_on, beat2_step)
    UI.draw_status_lamps(drones_settings, beat1_on, beat2_on)

  elseif tab_selected == 5 then
  -- MOD page (no headers): Left = LFO (5), Right = Sub+FX (5)
  local labels = { "LFO","Type","Wave","Freq","Depth",  "Lvl","Wave","Det","Rvb","Noise" }
  local values = {
    (lfo_on and "[X]" or "[ ]"),
    ({"Res","Amp","Pan"})[lfo_target],
    ({"Sine","Tri","Saw","Square"})[lfo_wave],
    string.format("%.1fHz", lfo_freq),
    string.format("%.2f",   lfo_depth),

    string.format("%.2f", subosc_level),
    ({"Sine","Tri","Saw","Square"})[subosc_wave],
    string.format("%.1f", subosc_detune),
    string.format("%.2f", rvb_mix),
    string.format("%.2f", noise_level),
  }

  if UI.draw_two_col_split then
    UI.draw_two_col_split(labels, values, 5, param_selected, UI.mod_xy) -- 5 left, 5 right
  else
    UI.draw_two_col(labels, values, param_selected, UI.mod_xy)
  end

  UI.draw_status_lamps(drones_settings, beat1_on, beat2_on)

  elseif tab_selected == 6 then
    -- Mix page: vertical bars (A, B, 1, 2)
    local names  = {"A","B","1","2"}
    local values = {
      drones_settings[1].mix or 0.7,
      drones_settings[2].mix or 0.7,
      beat1_amp or 0.95,
      beat2_amp or 0.95,
    }
    UI.draw_mix_bars(names, values, param_selected, 1.5)
    UI.draw_status_lamps(drones_settings, beat1_on, beat2_on)
  end

  screen.update()
end

-- =========================================================
-- Encoders / Keys
-- =========================================================
-- consider any of these as "running": explicit flag, non-empty launched list, or a live id marker
local function drone_is_running(i)
  local s = drones_settings[i]
  if not s then return false end
  if s.running == true then return true end
  if s.launched and #s.launched > 0 then return true end
  if s.drone_id ~= nil then return true end
  return false
end

function enc(n, d)
  -- Preset picker overlay: E2 scrolls; swallow others
  if preset_ui.active then
    if n == 2 then
      local names = musical_preset_names()
      if #names > 0 then
        preset_ui.sel = util.wrap(preset_ui.sel + d, 1, #names)
        redraw()
      end
    end
    return
  end

  if n == 1 then
    -- E1: change page
    tab_selected = util.wrap(tab_selected + d, 1, 6)
    param_selected = 1

  elseif tab_selected <= 2 then
    -- Drone pages A/B
    if n == 2 then
      -- On, Base, Parts, Wave, Det, A, D, S
      param_selected = util.wrap(param_selected + d, 1, 8)

    elseif n == 3 then
      local i = tab_selected
      local s = drones_settings[i]

      if     param_selected == 1 then
        -- toggle On
        local now = util.time()
        if s.running then
          stop_drone(i)
        else
          if now - (last_stop[i] or 0) < (STOP_COOLDOWN or 0.30) then return end
          kill_range(i)
          launch_drone(i)
        end

      elseif param_selected == 2 then
        s.base_hz  = math.max(20, s.base_hz + d)

      elseif param_selected == 3 then
        s.partials = util.clamp(s.partials + d, 1, 16)

      elseif param_selected == 4 then
        s.waveform = util.wrap(s.waveform + d, 1, 4)

      elseif param_selected == 5 then
        s.detune   = util.clamp(s.detune + d*0.05, 0, 10)

      elseif param_selected == 6 then
        s.attack   = util.clamp(s.attack  + d*0.05, 0.0, 30.0)

      elseif param_selected == 7 then
        s.decay    = util.clamp(s.decay   + d*0.05, 0.0, 30.0)

      elseif param_selected == 8 then
        s.sustain  = util.clamp(s.sustain + d*0.02, 0.0, 1.0)
      end

      -- apply new ADSR immediately
      if param_selected >= 6 and param_selected <= 8 then
        apply_env(s)
      elseif param_selected >= 2 and param_selected <= 5 then
        apply_env(s)
      end
    end

  elseif tab_selected == 3 then
    -- Beat 1
    if n == 2 then
      param_selected = util.wrap(param_selected + d, 1, 8)
    elseif n == 3 then
      if     param_selected == 1 then
        if beat1_on then stop_beat1() params:set("beat1_run",1) else start_beat1() params:set("beat1_run",2) end
      elseif param_selected == 2 then
        beat1_steps = util.clamp(beat1_steps + d, 1, 32) params:set("beat1_steps", beat1_steps) refresh_beat1_pat()
      elseif param_selected == 3 then
        beat1_fills = util.clamp(beat1_fills + d, 0, beat1_steps) params:set("beat1_fills", beat1_fills) refresh_beat1_pat()
      elseif param_selected == 4 then
        beat1_rotate = util.clamp(beat1_rotate + d, -64, 64) params:set("beat1_rotate", beat1_rotate) refresh_beat1_pat()
      elseif param_selected == 5 then
        beat1_div_ix = util.wrap(beat1_div_ix + d, 1, #beat_divs) params:set("beat1_div_ix", beat1_div_ix)
      elseif param_selected == 6 then
        beat1_kick_hz = util.clamp(beat1_kick_hz + d, 20, 120) params:set("beat1_tune", beat1_kick_hz)
      elseif param_selected == 7 then
        beat1_kick_decay = util.clamp(beat1_kick_decay + d*0.02, 0.05, 2.0) params:set("beat1_decay", beat1_kick_decay)
      elseif param_selected == 8 then
        beat1_amp = util.clamp((beat1_amp or 0.95) + d*0.02, 0, 1.5) params:set("beat1_amp", beat1_amp)
      end
    end

  elseif tab_selected == 4 then
    -- Beat 2
    if n == 2 then
      param_selected = util.wrap(param_selected + d, 1, 8)
    elseif n == 3 then
      if     param_selected == 1 then
        if beat2_on then stop_beat2() params:set("beat2_run",1) else start_beat2() params:set("beat2_run",2) end
      elseif param_selected == 2 then
        beat2_steps = util.clamp(beat2_steps + d, 1, 32) params:set("beat2_steps", beat2_steps) refresh_beat2_pat()
      elseif param_selected == 3 then
        beat2_fills = util.clamp(beat2_fills + d, 0, beat2_steps) params:set("beat2_fills", beat2_fills) refresh_beat2_pat()
      elseif param_selected == 4 then
        beat2_rotate = util.clamp(beat2_rotate + d, -64, 64) params:set("beat2_rotate", beat2_rotate) refresh_beat2_pat()
      elseif param_selected == 5 then
        beat2_div_ix = util.wrap(beat2_div_ix + d, 1, #beat_divs) params:set("beat2_div_ix", beat2_div_ix)
      elseif param_selected == 6 then
        beat2_kick_hz = util.clamp(beat2_kick_hz + d, 20, 120) params:set("beat2_tune", beat2_kick_hz)
      elseif param_selected == 7 then
        beat2_kick_decay = util.clamp(beat2_kick_decay + d*0.02, 0.05, 2.0) params:set("beat2_decay", beat2_kick_decay)
      elseif param_selected == 8 then
        beat2_amp = util.clamp((beat2_amp or 0.95) + d*0.02, 0, 1.5) params:set("beat2_amp", beat2_amp)
      end
    end

  elseif tab_selected == 5 then
    -- Mod page: 10 items total (1..10)
    if n == 2 then
      param_selected = util.wrap(param_selected + d, 1, 10)
    elseif n == 3 then
      if     param_selected == 1 then
        lfo_on = not lfo_on
        if params.lookup and params.lookup["lfo_on"] then
          params:set("lfo_on", lfo_on and 2 or 1)
        end
      elseif param_selected == 2 then lfo_target    = util.wrap(lfo_target + d, 1, 3)               params:set("lfo_target", lfo_target)
      elseif param_selected == 3 then lfo_wave      = util.wrap(lfo_wave + d, 1, 4)                 params:set("lfo_wave",   lfo_wave)
      elseif param_selected == 4 then lfo_freq      = util.clamp(lfo_freq + d*0.1, 0, 40)           params:set("lfo_freq",   lfo_freq)
      elseif param_selected == 5 then lfo_depth     = util.clamp(lfo_depth + d*0.02, 0, 1)          params:set("lfo_depth",  lfo_depth)
      elseif param_selected == 6 then subosc_level  = util.clamp(subosc_level + d*0.05, 0, 1)       params:set("sub_level",  subosc_level)
      elseif param_selected == 7 then subosc_wave   = util.wrap(subosc_wave + d, 1, 4)              params:set("sub_wave",   subosc_wave)
      elseif param_selected == 8 then subosc_detune = util.clamp(subosc_detune + d*0.1, 0, 12)      params:set("sub_detune", subosc_detune)
      elseif param_selected == 9 then rvb_mix       = util.clamp(rvb_mix + d*0.02, 0, 1)            params:set("fx_revmix",  rvb_mix)
      elseif param_selected == 10 then noise_level  = util.clamp(noise_level + d*0.02, 0, 1)        params:set("fx_noise",   noise_level)
      end
      set_engine_mix_and_fx()
    end

  elseif tab_selected == 6 then
    -- Mix bars
    if n == 2 then
      param_selected = util.wrap(param_selected + d, 1, 4)
    elseif n == 3 then
      if     param_selected == 1 then
        local s = drones_settings[1]
        s.mix = util.clamp((s.mix or 0.7) + d*0.02, 0, 1.5)
        apply_drone_mix(1)
        if params.lookup and params.lookup["Amix"] then params:set("Amix", s.mix) end
      elseif param_selected == 2 then
        local s = drones_settings[2]
        s.mix = util.clamp((s.mix or 0.7) + d*0.02, 0, 1.5)
        apply_drone_mix(2)
        if params.lookup and params.lookup["Bmix"] then params:set("Bmix", s.mix) end
      elseif param_selected == 3 then
        beat1_amp = util.clamp((beat1_amp or 0.95) + d*0.02, 0, 1.5)
        if params.lookup and params.lookup["beat1_amp"] then params:set("beat1_amp", beat1_amp) end
      elseif param_selected == 4 then
        beat2_amp = util.clamp((beat2_amp or 0.95) + d*0.02, 0, 1.5)
        if params.lookup and params.lookup["beat2_amp"] then params:set("beat2_amp", beat2_amp) end
      end
    end
  end

  redraw()
end

function key(n, z)
  if n == 1 then k1_held = (z == 1); return end
  if n == 2 then k2_held = (z == 1) end
  if n == 3 then k3_held = (z == 1) end
  if z ~= 1 then return end

  -- K2+K3 together opens the preset picker
  if (n == 2 and k3_held) or (n == 3 and k2_held) then
    open_preset_picker()
    return
  end

  -- When picker is open: K2 loads, K3 closes
  if preset_ui.active then
    if n == 2 then
      local ix = preset_ui.sel + 1 -- +1 for leading "—"
      if params.lookup and params.lookup["musical_preset_load"] then
        params:set("musical_preset_load", ix)
      end
      preset_ui.active = false
      redraw()
      return
    elseif n == 3 then
      preset_ui.active = false
      redraw()
      return
    end
  end

  

if n == 2 then
  if tab_selected <= 2 then
    local i = tab_selected
    local now = util.time()
    local is_on = drone_is_running(i) or (drones_settings[i].launched and #drones_settings[i].launched > 0)

    if is_on then
      drone_hard_kill(i)                 -- <<< use hard kill
    else
      if now - (last_stop[i] or 0) < STOP_COOLDOWN then return end
      kill_range(i)                      -- clear anything stale
      launch_drone(i)
    end


    elseif tab_selected == 3 then
      if beat1_on then stop_beat1() params:set("beat1_run",1) else start_beat1() params:set("beat1_run",2) end
    elseif tab_selected == 4 then
      if beat2_on then stop_beat2() params:set("beat2_run",1) else start_beat2() params:set("beat2_run",2) end
    end

  elseif n == 3 then
    -- K3: global panic (K1+K3 saves autosave)
    if k1_held then
      save_params_to_autosave()
      return
    end
    if engine.panic then pcall(engine.panic) end  -- engine-side kill
    global_panic()                                -- Lua-side cleanup
    redraw()
  end
end

-- =========================================================
-- Drone launch/stop
-- =========================================================
function launch_drone(slot_num)
  local slot = drones_settings[slot_num]

  -- if something is still around, hard-stop the whole range first
  kill_range(slot_num)

  -- mark running *before* we spawn voices (prevents re-launch on quick K2)
  slot.running = true
  slot.launched = {}
  local now = util.time()
  slot.drone_start = now
  slot.drone_id = now

  engine.oscWaveShape((slot.waveform or 1) - 1)
  apply_env(slot)

  for i=1, slot.partials do
    local vid = drone_voice_offset[slot_num] + i
    local det = ((i - 1) - ((slot.partials - 1) / 2)) * slot.detune
    local hz  = slot.base_hz + det
    engine.noteOn(vid, hz, slot.mix or 0.5)
    table.insert(slot.launched, vid)
  end

  apply_drone_mix(slot_num)
  redraw()
end

function stop_drone(slot_num)
  drone_hard_kill(slot_num)
  redraw()
end

-- =========================================================
-- Lifecycle
-- =========================================================
local function force_silent_boot()
  for i=1,DRONES do stop_drone(i) end
  stop_beat1(); stop_beat2()
  if params.lookup and params.lookup["beat1_run"] then params:set("beat1_run", 1) end
  if params.lookup and params.lookup["beat2_run"] then params:set("beat2_run", 1) end
  redraw()
end

function init()
  -- Wire params module
  Params.setup({
    DRONES = DRONES,
    drones_settings = drones_settings,
    apply_env = apply_env,
    set_engine_mix_and_fx = set_engine_mix_and_fx,

    -- expose both beat patterns + controls to params (if needed)
    refresh_beat1_pat = refresh_beat1_pat,
    refresh_beat2_pat = refresh_beat2_pat,
    start_beat1 = start_beat1,
    stop_beat1  = stop_beat1,
    start_beat2 = start_beat2,
    stop_beat2  = stop_beat2,

    apply_drone_mix = apply_drone_mix,
    redraw = redraw,
    set = PARAM_SET,
  })

  -- Autosave: create if missing, then bang
  local p = autosave_path()
  if util.file_exists(p) then params:read(p) else util.make_dir(norns.state.data) params:write(p) end
  params:bang()

  force_silent_boot()

  -- engine post-load init (LFO, etc.)
  defer(0.15, function()
    pcall(set_engine_mix_and_fx)
    refresh_beat1_pat(); refresh_beat2_pat()
    start_lfo_clock()
    redraw()
  end)
end

Grid.setup({
  -- If the top row appears on the bottom, flip Y:
Grid.set_flip_y(false),

-- If columns/rows are still swapped, also do:
-- Grid.set_swap_xy(true)

-- If it mirrors left/right, use:
-- Grid.set_flip_x(true)
  redraw = redraw,

  k1_held = function() return k1_held end,

  -- toggles
  drone_is_running = function(i) return drone_is_running(i) end,
  drone_toggle = function(i)
    if drone_is_running(i) then stop_drone(i) else launch_drone(i) end
  end,
  beat_is_on = function(i) return (i==1 and beat1_on) or (i==2 and beat2_on) end,
  beat_toggle = function(i)
    if i==1 then if beat1_on then stop_beat1() else start_beat1() end
    else          if beat2_on then stop_beat2() else start_beat2() end end
  end,

  -- faders
  get_mix = function(i) return drones_settings[i].mix or 0 end,
  set_mix = function(i, v)
    drones_settings[i].mix = util.clamp(v, 0, 1.5)
    apply_drone_mix(i)
    if params.lookup then params:set((i==1) and "Amix" or "Bmix", drones_settings[i].mix) end
  end,
  get_beat_amp = function(i) return (i==1 and beat1_amp) or beat2_amp end,
  set_beat_amp = function(i, v)
    if i==1 then beat1_amp = util.clamp(v,0,1.5); params:set("beat1_amp", beat1_amp)
    else        beat2_amp = util.clamp(v,0,1.5); params:set("beat2_amp", beat2_amp) end
  end,

  -- nav
  goto_tab = function(ix) tab_selected = util.clamp(ix,1,6); param_selected = 1; redraw() end,

  -- drone nudges
  drone_base = function(i, d)
    local s = drones_settings[i]; s.base_hz = math.max(20, s.base_hz + d); apply_env(s)
  end,
  drone_partials = function(i, d)
    local s = drones_settings[i]; s.partials = util.clamp(s.partials + d, 1, 16); apply_env(s)
  end,
  drone_cycle_wave = function(i, dir)
    local s = drones_settings[i]; s.waveform = util.wrap(s.waveform + dir, 1, 4)
  end,
  drone_detune = function(i, d)
    local s = drones_settings[i]; s.detune = util.clamp(s.detune + d, 0, 10)
  end,

  -- euclid nudges (second column)
  beat_cycle_div = function(i, dir)
    if i==1 then beat1_div_ix = util.wrap(beat1_div_ix + dir, 1, #beat_divs); params:set("beat1_div_ix", beat1_div_ix)
    else         beat2_div_ix = util.wrap(beat2_div_ix + dir, 1, #beat_divs); params:set("beat2_div_ix", beat2_div_ix) end
  end,
  beat_tune = function(i, d)
    if i==1 then beat1_kick_hz = util.clamp(beat1_kick_hz + d, 20, 120); params:set("beat1_tune", beat1_kick_hz)
    else         beat2_kick_hz = util.clamp(beat2_kick_hz + d, 20, 120); params:set("beat2_tune", beat2_kick_hz) end
  end,
  beat_decay = function(i, d)
    if i==1 then beat1_kick_decay = util.clamp(beat1_kick_decay + d, 0.05, 2.0); params:set("beat1_decay", beat1_kick_decay)
    else         beat2_kick_decay = util.clamp(beat2_kick_decay + d, 0.05, 2.0); params:set("beat2_decay", beat2_kick_decay) end
  end,
  beat_amp = function(i, d)
    if i==1 then beat1_amp = util.clamp(beat1_amp + d, 0, 1.5); params:set("beat1_amp", beat1_amp)
    else         beat2_amp = util.clamp(beat2_amp + d, 0, 1.5); params:set("beat2_amp", beat2_amp) end
  end,
})


function cleanup()
  stop_lfo_clock()
if Grid and Grid.cleanup then Grid.cleanup() end
  global_panic()
  util.make_dir(norns.state.data)
  params:write(autosave_path())
end
