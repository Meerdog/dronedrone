--           DroneDrums
--
-- 
-- Two drifting drones (A/B) 
--  two Euclidean beatmakers (1/2).
-- K2 = context toggle & K3 = PANIC


engine.name = "Dromedary2"

local util = require "util"
local cs   = require "controlspec"

local C       = include("lib/constants")
local Params  = include("lib/params")
local UI      = include("lib/ui")
local Grid    = include("lib/grid")
local Presets = include("lib/presets") -- names(), desc(i), get(i) or apply(i)

----------------------------------------------------------------
-- Config / State
----------------------------------------------------------------
local DRONES = 2
local TAB_TITLES = {"A","B","1","2","M","Mix","P"}

-- voice id layout (avoid A/B collisions)
local VOICE_SPAN = (C and C.VOICE_SPAN) or 32
local drone_voice_offset = (C and C.DRONE_VOICE_OFFSET) or {0, 32}

-- CHORDS from constants (fallback if missing)
local CHORDS = (C and C.CHORDS)
if not (CHORDS and #CHORDS > 0) then
  CHORDS = {
    { name="Off",  semitones={} },
    { name="Maj",  semitones={0,4,7} },
    { name="Min",  semitones={0,3,7} },
    { name="Sus2", semitones={0,2,7} },
    { name="Sus4", semitones={0,5,7} },
    { name="Maj7", semitones={0,4,7,11} },
    { name="Min7", semitones={0,3,7,10} },
    { name="Dom7", semitones={0,4,7,10} },
    { name="Add9", semitones={0,4,7,14} },
  }
end

-- Drum lists / tuning rules
local DRUM_NAMES = (C and C.DRUM_NAMES) or {"Kick","Snare","CH","OH","Clap","Rim","Cow","Clv","Tom"}
local DRUM_TUNELESS = (C and C.DRUM_TUNELESS) or { Clap=true, Rim=true, Cow=true, Clv=true }
local function drum_name(ix)
  local n = (ix - 1) % math.max(1, #DRUM_NAMES) + 1
  return DRUM_NAMES[n] or "Kick"
end

----------------------------------------------------------------
-- Options mode (per-entity toggled by K1+K2 or grid last row)
----------------------------------------------------------------
local options_mode = { A=false, B=false, ["1"]=false, ["2"]=false }
local function is_entity_page(ix)
  local i = ix or tab_selected
  local t = TAB_TITLES[i]
  return (t == "A" or t == "B" or t == "1" or t == "2")
end
local function entity_key_for_tab(i)
  local t = TAB_TITLES[i]
  if t == "A" or t == "B" or t == "1" or t == "2" then return t end
  return nil
end

----------------------------------------------------------------
-- Anti-pop config (stagger + short level ramp)
----------------------------------------------------------------
local START_STAGGER_SEC = 0.004
local START_RAMP_SEC    = 0.080

local function _call(fn, ...) if not fn then return false end; return pcall(fn, ...) end

-- Feature detection (range setters may not exist on some engines)
local HAS_RANGE = {
  cutoff = (engine and (engine.setCutoffRange or engine.setFilterRange)) and true or false,
  reson  = (engine and engine.setResonanceRange) and true or false,
  pan    = (engine and engine.setPanRange) and true or false,
  level  = (engine and (engine.setLevelRange or engine.setAmpRange)) and true or false,
}

local function _set_range_level(slot_idx, val)
  local base = (drone_voice_offset[slot_idx] or 0)
  local lo, hi = base + 1, base + VOICE_SPAN
  if engine.setLevelRange then pcall(engine.setLevelRange, lo, hi, val)
  elseif engine.setAmpRange then pcall(engine.setAmpRange,   lo, hi, val)
  else _call(engine.mainOscLevel, util.clamp(val,0,1.5)) end
end

local function _set_range_pan(slot_idx, v)
  if not HAS_RANGE.pan then return end
  local base = (drone_voice_offset[slot_idx] or 0)
  local lo, hi = base + 1, base + VOICE_SPAN
  pcall(engine.setPanRange, lo, hi, v)
end

local function _set_range_cutoff(slot_idx, hz)
  if HAS_RANGE.cutoff then
    local base = (drone_voice_offset[slot_idx] or 0)
    local lo, hi = base + 1, base + VOICE_SPAN
    if engine.setCutoffRange     then pcall(engine.setCutoffRange, lo, hi, hz)
    else                                pcall(engine.setFilterRange, lo, hi, hz) end
  else
    if engine.cutoff then pcall(engine.cutoff, hz) end
  end
end

local function _set_range_reson(slot_idx, r)
  if HAS_RANGE.reson then
    local base = (drone_voice_offset[slot_idx] or 0)
    local lo, hi = base + 1, base + VOICE_SPAN
    pcall(engine.setResonanceRange, lo, hi, r)
  else
    if engine.resonance then pcall(engine.resonance, r) end
  end
end

----------------------------------------------------------------
-- Beats (with Delay options)
----------------------------------------------------------------
local beat_divs = {1, 1/2, 1/4, 1/8}
local beat = {
  [1] = {
    on=false, steps=16, fills=5, rotate=0, div_ix=3, drum_ix=1,
    tune_hz=48, decay=0.60, amp=0.95, step=1, pat={}, clock=nil, started_at=0,
    global_prob=1.0, swing=0.0, humanize_ms=0, ratchet=1, ratchet_shape="even",
    delay_on=false, delay_time_ms=180, delay_fb=0.35, delay_repeats=5,
  },
  [2] = {
    on=false, steps=16, fills=8, rotate=0, div_ix=3, drum_ix=1,
    tune_hz=55, decay=0.45, amp=0.95, step=1, pat={}, clock=nil, started_at=0,
    global_prob=1.0, swing=0.0, humanize_ms=0, ratchet=1, ratchet_shape="even",
    delay_on=false, delay_time_ms=180, delay_fb=0.35, delay_repeats=5,
  },
}

-- drum triggering
local function trigger_engine_drum(name, amp, tone, dec)
  if     name == "Kick"  then _call(engine.kick,    amp, tone, dec)
  elseif name == "Snare" then _call(engine.snare,   amp, tone, dec)
  elseif name == "CH"    then _call(engine.ch,      amp, tone, dec)
  elseif name == "OH"    then _call(engine.oh,      amp, tone, dec)
  elseif name == "Clap"  then _call(engine.clap,    amp)
  elseif name == "Rim"   then _call(engine.rimshot, amp)
  elseif name == "Cow"   then _call(engine.cowbell, amp)
  elseif name == "Clv"   then _call(engine.claves,  amp)
  elseif name == "Tom"   then _call(engine.mt,      amp, tone, dec)
  else _call(engine.kick, amp, tone, dec) end
end

----------------------------------------------------------------
-- UI state / holds
----------------------------------------------------------------
local tab_selected, param_selected = 1, 1
local k1_held, k2_held, k3_held = false, false, false

-- Presets tab UI
local preset_ui = { sel=1, first=1 }

-- Options cursors + scroll windows
local DRONE_OPTS_CURSOR, DRONE_OPTS_FIRST = { [1]=1, [2]=1 }, { [1]=1, [2]=1 }
local BEAT_OPTS_CURSOR,  BEAT_OPTS_FIRST  = { [1]=1, [2]=1 }, { [1]=1, [2]=1 }

-- Screen / options panel geometry (adjusted to show 3 rows comfortably)
local SCREEN_W, SCREEN_H = 128, 64
local OPTS_Y0       = 18     -- pushed down a bit (keeps tabs clear)
local OPTS_LH       = 11     -- tighter row height so we get 3 visible rows
local OPTS_EDGE_PAD = 1      -- start scrolling 1 row before the edge

local function _opts_vis_rows()
  -- Smaller header to remove the title band so we can fit 3 rows
  local header_h = 4
  local avail_h  = SCREEN_H - OPTS_Y0 - 2
  local list_h   = math.max(1, avail_h - header_h)
  return math.max(1, math.floor(list_h / OPTS_LH))
end

-- Debounce after stop
local last_stop = {0,0}
local STOP_COOLDOWN = 0.30
local toggle_guard_until = {0,0}
local smooth_kill_clock = {[1]=nil,[2]=nil}

----------------------------------------------------------------
-- Mix / FX (params-only) + quick reverb
----------------------------------------------------------------
local base_main_level = 1.0
local subosc_level, subosc_detune, subosc_wave = 0.50, 0.0, 1
local chorus_mix, noise_level = 0.20, 0.10
local fx_cutoff, fx_resonance = 12000, 0.20
local rvb_mix, rvb_room, rvb_damp = 0.20, 0.60, 0.50

-- ---- Safety limiter / auto-headroom ----
local safety = { on=true, target_units=2.2, limit_thresh=0.85, limit_dur=0.02 }
local _safety_scale = 1.0
local safety_clock = nil

local function _safety_units()
  local u = 0
  if type(drones) ~= "table" then return u end
  for i=1,DRONES do
    local s = drones[i]
    if s then u = u + (s.mix or 0) end
  end
  u = u + (beat[1].amp or 0) + (beat[2].amp or 0)
  u = u + 0.3 * ((beat[1].ratchet or 1)-1 + (beat[2].ratchet or 1)-1)
  return u
end

local function start_safety()
  if safety_clock then pcall(clock.cancel, safety_clock) end
  safety_clock = clock.run(function()
    while true do
      clock.sleep(1/30)
      if safety.on then
        local units = _safety_units()
        local s = (units > 0) and math.min(1.0, (safety.target_units or 2.2) / units) or 1.0
        _safety_scale = util.clamp(s, 0.3, 1.0)
        if engine.mainOscLevel then engine.mainOscLevel((base_main_level or 1.0) * _safety_scale) end
        if engine.limitThresh  then engine.limitThresh (safety.limit_thresh or 0.85) end
        if engine.limitDur     then engine.limitDur    (safety.limit_dur    or 0.02) end
      else
        _safety_scale = 1.0
        if engine.mainOscLevel then engine.mainOscLevel(base_main_level or 1.0) end
      end
    end
  end)
end

local function stop_safety()
  if safety_clock then pcall(clock.cancel, safety_clock) end
  safety_clock = nil
end

local function set_engine_mix_and_fx()
  _call(engine.mainOscLevel, base_main_level * (_safety_scale or 1.0))
  _call(engine.noiseLevel,   noise_level)
  _call(engine.chorusMix,    chorus_mix)

  _call(engine.subOscLevel,  subosc_level)
  _call(engine.subOscDetune, subosc_detune)
  _call(engine.subOscWave,   subosc_wave - 1)

  _call(engine.limitThresh,  safety.limit_thresh or 0.85)
  _call(engine.limitDur,     safety.limit_dur    or 0.02)

  if engine.cutoff    then engine.cutoff(fx_cutoff) end
  if engine.resonance then engine.resonance(fx_resonance) end
  if engine.reverbMix then engine.reverbMix(rvb_mix) end
  if engine.reverbRoom then engine.reverbRoom(rvb_room) end
  if engine.reverbDamp then engine.reverbDamp(rvb_damp) end
end

----------------------------------------------------------------
-- Global LFO (Res/Amp/Pan) — audible & Mix tab reflects it
----------------------------------------------------------------
local lfo_on, lfo_target, lfo_wave, lfo_freq, lfo_depth = true, 1, 1, 2.0, 0.20
local lfo_clock, lfo_phase = nil, 0.0
local MAIN_LFO_AMP_GAIN = 0.9

local function lfo_val(ph, wave)
  local two_pi = math.pi * 2
  if     wave == 1 then return math.sin(ph)
  elseif wave == 2 then local t=(ph%two_pi)/two_pi; return 4*math.abs(t-0.5)-1
  elseif wave == 3 then local t=(ph%two_pi)/two_pi; return (2*t)-1
  else return (math.sin(ph) >= 0) and 1 or -1 end
end

local function stop_lfo() if lfo_clock then pcall(clock.cancel,lfo_clock) end; lfo_clock=nil end
local function start_lfo()
  stop_lfo()
  lfo_clock = clock.run(function()
    local step = 1/50
    while true do
      clock.sleep(step)
      lfo_phase = (lfo_phase + (2*math.pi) * math.max(0, lfo_freq) * step) % (2*math.pi)
      local s = lfo_val(lfo_phase, lfo_wave)
      if lfo_on then
        if     lfo_target == 1 and engine.resonance then
          engine.resonance(util.clamp(fx_resonance + 0.30*lfo_depth*s, 0.05, 0.99))
        elseif lfo_target == 2 then
          local base = base_main_level*_safety_scale
          local factor = 1 + MAIN_LFO_AMP_GAIN * lfo_depth * s
          _call(engine.mainOscLevel, util.clamp(base * factor, 0, 1.5))
          if type(drones) == "table" then
            for i=1,DRONES do
              local ss = drones[i]
              if ss then
                local src = ss.mix or 0.7
                local live = ss.mix_live or src
                ss.mix_live = util.clamp(live * factor, 0, 1.5)
                if HAS_RANGE.level and not (ss.lfo.running and ss.lfo.target=="mix") then
                  _set_range_level(i, ss.mix_live)
                end
              end
            end
          end
          if tab_selected == 6 then redraw() end
        elseif lfo_target == 3 and HAS_RANGE.pan then
          local any_drone_pan=false
          if type(drones)=="table" then
            for i=1,DRONES do if drones[i] and drones[i].lfo.running and drones[i].lfo.target=="pan" then any_drone_pan=true; break end end
          end
          if not any_drone_pan and type(drones)=="table" then
            local pan = util.clamp(lfo_depth * s, -1, 1)
            for i=1,DRONES do _set_range_pan(i, pan) end
          end
        end
      else
        _call(engine.mainOscLevel, base_main_level*_safety_scale)
        if engine.resonance then engine.resonance(fx_resonance) end
      end
    end
  end)
end

----------------------------------------------------------------
-- Euclid core + step scheduler (+ delay echoes)
----------------------------------------------------------------
local function euclid(steps, fills, rotate)
  local pat, bucket = {}, 0
  steps = math.max(1, steps); fills = util.clamp(fills, 0, steps)
  for i=1,steps do
    bucket = bucket + fills
    if bucket >= steps then bucket = bucket - steps; pat[i]=1 else pat[i]=0 end
  end
  local rot = ((rotate % steps) + steps) % steps
  if rot ~= 0 then
    local out = {}; for i=1,steps do out[i] = pat[((i-1-rot)%steps)+1] end; pat = out
  end
  return pat
end

local function refresh_pat(i)
  beat[i].pat = euclid(beat[i].steps, beat[i].fills, beat[i].rotate)
  if beat[i].step > beat[i].steps then beat[i].step = 1 end
end

local function schedule_echoes(tid, dname, tone_ok, amp0, tone_hz, dec)
  local t = beat[tid]
  if not t.delay_on then return end
  local fb     = util.clamp(t.delay_fb or 0.35, 0, 0.95)
  local reps   = util.clamp(t.delay_repeats or 4, 0, 12)
  local dt_sec = math.max(0.01, (t.delay_time_ms or 160)/1000)
  clock.run(function()
    local a = amp0
    for k=1,reps do
      clock.sleep(dt_sec)
      a = a * fb
      if a < 0.002 then break end
      if tone_ok then trigger_engine_drum(dname, a, tone_hz, dec)
      else trigger_engine_drum(dname, a, nil, nil) end
    end
  end)
end

local function schedule_step_hits(i, step_index, step_dur_sec)
  local b = beat[i]; if not b.on then return end
  if (b.global_prob or 1) < 1 and math.random() >= (b.global_prob or 1) then return end

  local rat = math.max(1, b.ratchet or 1)
  local shape = b.ratchet_shape or "even"

  local delay_sec = 0
  if (b.swing or 0) > 0 and (step_index % 2 == 1) then
    delay_sec = delay_sec + (step_dur_sec * util.clamp(b.swing, 0, 0.6))
  end
  if (b.humanize_ms or 0) > 0 then
    local hm = (math.random()*2 - 1) * b.humanize_ms / 1000
    delay_sec = delay_sec + math.max(0, hm)
  end

  local dname = drum_name(b.drum_ix or 1)
  local tone_ok = not DRUM_TUNELESS[dname]
  local base_amp = b.amp or 0.95
  local amp_guard = (_safety_scale or 1.0)
  local tone_hz   = b.tune_hz or 48
  local dec       = b.decay or 0.6

  clock.run(function()
    if delay_sec > 0 then clock.sleep(delay_sec) end
    if not b.on then return end

    if rat <= 1 then
      local a = base_amp*amp_guard
      if tone_ok then trigger_engine_drum(dname, a, tone_hz, dec)
      else trigger_engine_drum(dname, a, nil, nil) end
      schedule_echoes(i, dname, tone_ok, a, tone_hz, dec)
      return
    end

    local slices = rat
    local function nth_t(n)
      if shape == "burst" then
        local t = (n-1) / slices
        local skew = t^(0.65)
        return skew * step_dur_sec
      else
        return (n-1) * (step_dur_sec / slices)
      end
    end

    for n=1,slices do
      if n > 1 then
        local dt = nth_t(n) - nth_t(n-1)
        clock.sleep(math.max(0.0005, dt))
      end
      if not b.on then return end
      local scale = 1 - 0.06*(n-1)
      local a = base_amp*amp_guard*scale
      if tone_ok then trigger_engine_drum(dname, a, tone_hz, dec)
      else trigger_engine_drum(dname, a, nil, nil) end
      schedule_echoes(i, dname, tone_ok, a, tone_hz, dec)
    end
  end)
end

local function stop_beat(i)
  beat[i].on = false; beat[i].started_at = 0
  if beat[i].clock then pcall(clock.cancel, beat[i].clock) end
  beat[i].clock = nil
end

local function start_beat(i)
  stop_beat(i)
  beat[i].on = true; beat[i].started_at = util.time()
  refresh_pat(i)
  beat[i].clock = clock.run(function()
    local div = beat_divs[beat[i].div_ix] or 1/4
    while beat[i].on do
      local bpm = clock.get_tempo and clock.get_tempo() or 120
      local step_dur_sec = (60 / bpm) * div
      clock.sync(div)
      if beat[i].pat[beat[i].step] == 1 then
        schedule_step_hits(i, beat[i].step, step_dur_sec)
      end
      beat[i].step = (beat[i].step % beat[i].steps) + 1
      redraw()
    end
  end)
end

----------------------------------------------------------------
-- Drones (+ per-drone LFO & filters in Options)
----------------------------------------------------------------
local drones = {}
for i=1,DRONES do
  drones[i] = {
    running=false, chord_ix=1, waveform=2,
    base_hz=(i==1) and 360 or 340, voices=(i==1) and 3 or 4, detune=(i==1) and 0.50 or 0.60,
    attack=0.60, decay=1.00, sustain=0.80, release=2.50,
    mix=0.70, mix_live=0.70,
    filt_cutoff=12000, filt_res=0.20,
    launched={}, drone_id=nil, drone_start=0,
    lfo={enabled=false, running=false, shape="sine", rate_hz=0.15, depth=0.15, unipolar=false, target="mix", phase=0.0, handle=nil},
  }
end

local function apply_env(s)
  _call(engine.attack,  s.attack  or 0.6)
  _call(engine.decay,   s.decay   or 1.0)
  _call(engine.sustain, s.sustain or 0.8)
  _call(engine.release, s.release or 2.5)
end

local function apply_drone_mix(i)
  _set_range_level(i, drones[i].mix or 0.7)
  drones[i].mix_live = drones[i].mix
end

local function apply_drone_filter(i)
  local s = drones[i]
  _set_range_cutoff(i, s.filt_cutoff or 12000)
  _set_range_reson (i, util.clamp(s.filt_res or 0.2, 0.0, 0.99))
end

local function _shape_value(shape, x)
  if shape=="sine" then return math.sin(2*math.pi*x)
  elseif shape=="tri" then return (x<0.5) and (x*4-1) or (3-4*x)
  elseif shape=="saw" then return (2*x-1)
  else return (math.sin(2*math.pi*x)>=0) and 1 or -1 end
end

local function stop_drone_lfo(i)
  local l = drones[i].lfo
  if l.handle then pcall(clock.cancel, l.handle) end
  l.handle=nil; l.running=false
  drones[i].mix_live = drones[i].mix
  if tab_selected == 6 then redraw() end
end

local function start_drone_lfo(i)
  local l = drones[i].lfo
  if l.running then return end
  l.running=true
  l.handle = clock.run(function()
    while l.running do
      clock.sleep(1/60)
      l.phase = (l.phase + l.rate_hz/60) % 1.0
      local y = _shape_value(l.shape, l.phase); if l.unipolar then y = (y*0.5 + 0.5) end
      if l.target == "mix" then
        local base = drones[i].mix or 0.7
        local v = util.clamp(base + y * l.depth, 0, 1.5)
        drones[i].mix_live = v
        _set_range_level(i, v)
        if tab_selected == 6 then redraw() end
      elseif l.target == "pan" and HAS_RANGE.pan then
        local v = util.clamp(y * l.depth, -1, 1)
        _set_range_pan(i, v)
      elseif l.target == "cutoff" then
        local base = drones[i].filt_cutoff or 12000
        local sweep = math.max(200, base * (0.5 + 0.5*y))
        _set_range_cutoff(i, sweep)
      end
    end
  end)
end

----------------------------------------------------------------
-- Toggles / lifecycle helpers
----------------------------------------------------------------
local function kill_range(i)
  local base = drone_voice_offset[i] or 0
  local lo, hi = base+1, base+VOICE_SPAN
  if engine.freeRange     then pcall(engine.freeRange, lo, hi) end
  if HAS_RANGE.level      then pcall(engine.setLevelRange or engine.setAmpRange, lo, hi, 0.0) end
  if engine.noteOffRange  then pcall(engine.noteOffRange,  lo, hi) end
end

local function drone_hard_kill(i)
  local s = drones[i]
  kill_range(i)
  stop_drone_lfo(i)
  s.running=false; s.launched={}; s.drone_id=nil; s.drone_start=0
  last_stop[i] = util.time()
end

local function drone_is_running(i)
  local s = drones[i]; if not s then return false end
  if s.running then return true end
  if s.launched and #s.launched > 0 then return true end
  if s.drone_id ~= nil then return true end
  return false
end

local function voice_id_for(i, idx) return (drone_voice_offset[i] or 0) + idx end
local function det_for(idx, total, amt)
  if total <= 1 then return 0 end
  local center = (total + 1) / 2
  local offset = (idx - center)
  return offset * (amt or 0)
end

function launch_drone(i)
  local s = drones[i]; if not s then return end
  local now = util.time()
  if now < (toggle_guard_until[i] or 0) then return end
  if now - (last_stop[i] or 0) < STOP_COOLDOWN then return end

  kill_range(i)
  s.running = true; s.launched = {}; s.drone_id = now; s.drone_start = now
  _call(engine.oscWaveShape, (s.waveform or 1) - 1)
  apply_env(s)
  apply_drone_filter(i)
  _set_range_level(i, 0.0)

  clock.run(function()
    local my_id = now
    local target = s.mix or 0.7
    local vs, idx = {}, 0
    local function still_mine() return s.running and s.drone_id == my_id end
    local function note_on_det(vid, hz) pcall(engine.noteOn, vid, hz, target) end

    if s.chord_ix and s.chord_ix > 1 then
      local chord = CHORDS[s.chord_ix] and CHORDS[s.chord_ix].semitones or {}
      local base_hz = s.base_hz or 220
      for _, semis in ipairs(chord) do
        if not still_mine() then return end
        local hz_tone = base_hz * (2^(semis/12))
        for v=1, s.voices do
          if not still_mine() then return end
          idx = idx + 1; if idx > VOICE_SPAN then break end
          local vid = voice_id_for(i, idx)
          local hz  = math.max(20, hz_tone + det_for(v, s.voices, s.detune))
          note_on_det(vid, hz)
          vs[#vs+1] = vid
          if START_STAGGER_SEC > 0 then clock.sleep(START_STAGGER_SEC) end
        end
        if idx >= VOICE_SPAN then break end
      end
    else
      for v=1, s.voices do
        if not still_mine() then return end
        idx = idx + 1; if idx > VOICE_SPAN then break end
        local vid = voice_id_for(i, idx)
        local hz  = math.max(20, (s.base_hz or 220) + det_for(v, s.voices, s.detune))
        note_on_det(vid, hz)
        vs[#vs+1] = vid
        if START_STAGGER_SEC > 0 then clock.sleep(START_STAGGER_SEC) end
      end
    end

    if not still_mine() then return end
    s.launched = vs

    local steps = 10
    local dt = (START_RAMP_SEC > 0) and (START_RAMP_SEC / steps) or 0
    for k = 1, steps do
      if not still_mine() then return end
      local lvl = target * (k / steps)
      _set_range_level(i, lvl)
      if dt > 0 then clock.sleep(dt) end
    end
    if still_mine() then _set_range_level(i, target) end

    if s.lfo.enabled and not s.lfo.running then start_drone_lfo(i) end
    redraw()
  end)
end

local function smooth_kill(i, fade_sec)
  local s = drones[i]
  if smooth_kill_clock[i] then pcall(clock.cancel, smooth_kill_clock[i]) end
  local now = util.time()
  last_stop[i] = now
  toggle_guard_until[i] = now + (fade_sec or 0.35) + 0.05
  s.running = false
  local steps = 10
  local dt = (fade_sec or 0.35) / steps
  local base = drone_voice_offset[i] or 0
  local lo, hi = base + 1, base + VOICE_SPAN
  smooth_kill_clock[i] = clock.run(function()
    for k = steps, 1, -1 do
      local lvl = (k-1)/steps
      if engine.setLevelRange then pcall(engine.setLevelRange, lo, hi, lvl)
      elseif engine.setAmpRange then pcall(engine.setAmpRange, lo, hi, lvl) end
      clock.sleep(dt)
    end
    drone_hard_kill(i)
    smooth_kill_clock[i] = nil
  end)
end

local function can_launch(i)
  local now = util.time()
  if now < (toggle_guard_until[i] or 0) then return false end
  if (now - (last_stop[i] or 0)) < STOP_COOLDOWN then return false end
  return true
end

local function toggle_drone(i)
  if drone_is_running(i) then smooth_kill(i, 0.35)
  else if not can_launch(i) then return end; kill_range(i); launch_drone(i) end
end

----------------------------------------------------------------
-- Params bridge (FX/LFO/Beats)
----------------------------------------------------------------
local function PARAM_SET(key, v)
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

  elseif key=="lfo_on"     then lfo_on = (v==true or v==2); redraw()
  elseif key=="lfo_target" then lfo_target = v; redraw()
  elseif key=="lfo_wave"   then lfo_wave = v; redraw()
  elseif key=="lfo_freq"   then lfo_freq = v; redraw()
  elseif key=="lfo_depth"  then lfo_depth = v; redraw()

  elseif key=="beat1_steps"  then beat[1].steps  = v; refresh_pat(1); redraw()
  elseif key=="beat1_fills"  then beat[1].fills  = v; refresh_pat(1); redraw()
  elseif key=="beat1_rotate" then beat[1].rotate = v; refresh_pat(1); redraw()
  elseif key=="beat1_div_ix" then beat[1].div_ix = v; redraw()
  elseif key=="beat1_tune"   then beat[1].tune_hz = v; redraw()
  elseif key=="beat1_decay"  then beat[1].decay   = v; redraw()
  elseif key=="beat1_amp"    then beat[1].amp     = v; redraw()
  elseif key=="beat1_drum_ix"then beat[1].drum_ix = v; redraw()

  elseif key=="beat2_steps"  then beat[2].steps  = v; refresh_pat(2); redraw()
  elseif key=="beat2_fills"  then beat[2].fills  = v; refresh_pat(2); redraw()
  elseif key=="beat2_rotate" then beat[2].rotate = v; refresh_pat(2); redraw()
  elseif key=="beat2_div_ix" then beat[2].div_ix = v; redraw()
  elseif key=="beat2_tune"   then beat[2].tune_hz = v; redraw()
  elseif key=="beat2_decay"  then beat[2].decay   = v; redraw()
  elseif key=="beat2_amp"    then beat[2].amp     = v; redraw()
  elseif key=="beat2_drum_ix"then beat[2].drum_ix = v; redraw()
  end
end

----------------------------------------------------------------
-- Presets (P tab) — kills all voices/beats before load
----------------------------------------------------------------
local function kill_all_sound()
  for i=1,DRONES do drone_hard_kill(i) end
  stop_beat(1); stop_beat(2)
  if engine.panic then pcall(engine.panic) end
end

local function preset_count()
  if Presets and Presets.count then return Presets.count() end
  if Presets and Presets.names then return #(Presets.names()) end
  return 0
end

local function preset_names()
  if Presets and Presets.names then
    local t = Presets.names()
    if t and #t > 0 then return t end
  end
  local n = preset_count()
  local out = {}
  for i=1,n do out[i] = ("Preset %d"):format(i) end
  return (#out>0) and out or {"(none)"}
end

local function preset_desc(ix)
  if Presets and Presets.desc then
    local d = Presets.desc(ix)
    if d then return d end
  end
  return ""
end

local function apply_preset(ix)
  kill_all_sound()
  if Presets and Presets.apply then
    local ok = pcall(Presets.apply, ix)
    if ok then redraw(); return end
  end
  local P = nil
  if Presets and Presets.get then
    local ok, val = pcall(Presets.get, ix); if ok then P = val end
  end
  if not P then return end

  -- drones
  if P.drones then
    for i=1,math.min(#P.drones, 2) do
      local s = drones[i]; local d = P.drones[i]
      if s and d then
        s.base_hz  = d.base_hz  or s.base_hz
        s.voices   = d.voices   or d.partials or s.voices
        s.chord_ix = d.chord_ix or s.chord_ix
        s.detune   = d.detune   or s.detune
        s.waveform = d.waveform or s.waveform
        s.attack   = d.attack   or s.attack
        s.decay    = d.decay    or s.decay
        s.sustain  = d.sustain  or s.sustain
        s.release  = d.release  or s.release
        s.mix      = d.mix      or s.mix
        s.filt_cutoff = d.filt_cutoff or s.filt_cutoff
        s.filt_res    = d.filt_res    or s.filt_res
        apply_env(s); apply_drone_mix(i); apply_drone_filter(i)
      end
    end
  end

  -- beats (+ options)
  if P.beats then
    local b1 = P.beats[1] or {}
    local b2 = P.beats[2] or {}
    for i,bp in ipairs({b1,b2}) do
      local t = beat[i]
      t.steps   = bp.steps   or t.steps
      t.fills   = bp.fills   or t.fills
      t.rotate  = bp.rotate  or t.rotate
      t.div_ix  = bp.div_ix  or t.div_ix
      t.tune_hz = bp.tune_hz or t.tune_hz
      t.decay   = bp.decay   or t.decay
      t.amp     = bp.amp     or t.amp
      t.drum_ix = bp.drum_ix or t.drum_ix
      t.global_prob  = bp.global_prob  or t.global_prob
      t.swing        = bp.swing        or t.swing
      t.humanize_ms  = bp.humanize_ms  or t.humanize_ms
      t.ratchet      = bp.ratchet      or t.ratchet
      t.ratchet_shape= bp.ratchet_shape or t.ratchet_shape
      t.delay_on       = (bp.delay_on == true) or t.delay_on
      t.delay_time_ms  = bp.delay_time_ms or t.delay_time_ms
      t.delay_fb       = bp.delay_fb or t.delay_fb
      t.delay_repeats  = bp.delay_repeats or t.delay_repeats
      refresh_pat(i)
    end
  end

  -- lfo / fx
  if P.lfo then
    lfo_on    = (P.lfo.on == true)
    lfo_target= P.lfo.target or lfo_target
    lfo_wave  = P.lfo.wave   or lfo_wave
    lfo_freq  = P.lfo.freq   or lfo_freq
    lfo_depth = P.lfo.depth  or lfo_depth
  end
  if P.fx then
    base_main_level = P.fx.main_level or base_main_level
    if P.fx.sub then
      subosc_level  = (P.fx.sub.level  ~= nil) and P.fx.sub.level  or subosc_level
      subosc_detune = (P.fx.sub.detune ~= nil) and P.fx.sub.detune or subosc_detune
      subosc_wave   = P.fx.sub.wave    or subosc_wave
    end
    if P.fx.filter then
      fx_cutoff     = P.fx.filter.cutoff    or fx_cutoff
      fx_resonance  = P.fx.filter.resonance or fx_resonance
    end
    if P.fx.reverb then
      rvb_mix  = (P.fx.reverb.mix  ~= nil) and P.fx.reverb.mix  or rvb_mix
      rvb_room = (P.fx.reverb.room ~= nil) and P.fx.reverb.room or rvb_room
      rvb_damp = (P.fx.reverb.damp ~= nil) and P.fx.reverb.damp or rvb_damp
    end
    if P.fx.noise  ~= nil then noise_level = P.fx.noise end
    if P.fx.chorus ~= nil then chorus_mix  = P.fx.chorus end
    set_engine_mix_and_fx()
  end
  redraw()
end

----------------------------------------------------------------
-- Options UI (auto-vis rows, early scroll, right gutter)
----------------------------------------------------------------
local function _draw_opts_panel_inverted(title_unused, rows, cursor, first)
  rows   = rows or {}
  cursor = util.clamp(cursor or 1, 1, math.max(1, #rows))
  first  = util.clamp(first  or 1, 1, math.max(1, #rows))

  local lh     = OPTS_LH
  local x0     = 3
  local y0     = OPTS_Y0
  local header = 4   -- tiny spacer (no visible title text)

  local right_limit = (UI and UI.LAMP_X and UI.LAMP_LABEL_GAP)
                      and (UI.LAMP_X - UI.LAMP_LABEL_GAP - 6)
                      or 110
  local w = math.max(40, right_limit - x0)

  local vis = _opts_vis_rows()
  local total = #rows
  local max_first = math.max(1, total - vis + 1)

  if total > vis then
    local last = first + vis - 1
    if cursor <= (first + OPTS_EDGE_PAD) then
      first = math.max(1, cursor - OPTS_EDGE_PAD)
    elseif cursor >= (last - OPTS_EDGE_PAD) then
      first = math.min(max_first, cursor - (vis - 1 - OPTS_EDGE_PAD))
    end
  else
    first = 1
  end

  local h = header + vis * lh
  screen.level(15); screen.rect(x0, y0, w, h); screen.fill()
  screen.level(2);  screen.rect(x0, y0, w, h); screen.stroke()

  local y = y0 + header - 1
  for j = 1, vis do
    local idx = first + j - 1
    if idx > total then break end
    local txt = rows[idx] or ""
    local is_sel = (idx == cursor)

    if is_sel then
      screen.level(0)
      screen.rect(x0 + 2, y - 7, w - 4, lh)
      screen.fill()
      screen.level(15)
    else
      screen.level(0)
    end

    screen.move(x0 + 6, y)
    screen.text(txt)
    y = y + lh
  end

  return first
end

local function draw_drones_opts(i)
  local s = drones[i]
  local rows = {
    ("LFO enabled: " .. ((s.lfo.enabled) and "on" or "off")),
    ("LFO shape: " .. (s.lfo.shape or "sine")),
    ("LFO rate: " .. string.format("%.2f", s.lfo.rate_hz or 0.15)),
    ("LFO depth: " .. string.format("%.2f", s.lfo.depth or 0.15)),
    ("Unipolar: " .. ((s.lfo.unipolar) and "on" or "off")),
    ("Target: " .. (s.lfo.target or "mix")),
    ("Filter Hz: " .. string.format("%.0f", s.filt_cutoff or 12000)),
    ("Filter Q: "  .. string.format("%.2f", s.filt_res or 0.20)),
    ("Attack: " .. string.format("%.2f", s.attack)),
    ("Decay: "  .. string.format("%.2f", s.decay)),
    ("Sustain: ".. string.format("%.2f", s.sustain)),
    ("Release: ".. string.format("%.2f", s.release)),
  }
  local nf = _draw_opts_panel_inverted(nil, rows, DRONE_OPTS_CURSOR[i], DRONE_OPTS_FIRST[i])
  if nf then DRONE_OPTS_FIRST[i] = nf end
end

local function draw_beats_opts(tid)
  local t = beat[tid]
  local rows = {
    ("Reverb mix: " .. string.format("%.2f", rvb_mix or 0)),
    ("Probability: " .. string.format("%.2f", t.global_prob or 1.0)),
    ("Swing: "       .. string.format("%.2f", t.swing or 0.0)),
    ("Drum: "        .. drum_name(t.drum_ix or 1)),
    ("Humanize ms: " .. tostring(t.humanize_ms or 0)),
    ("Ratchet: "     .. tostring(t.ratchet or 1) .. " (" .. (t.ratchet_shape or "even") .. ")"),
    ("Delay: "       .. ((t.delay_on and "on") or "off")),
    ("Delay ms: "    .. tostring(t.delay_time_ms or 160)),
    ("Delay fb: "    .. string.format("%.2f", t.delay_fb or 0.35)),
    ("Delay reps: "  .. tostring(t.delay_repeats or 4)),
    ("Steps: "       .. tostring(t.steps)),
    ("Fills: "       .. tostring(t.fills)),
    ("Rotate: "      .. tostring(t.rotate)),
    ("Div: "         .. ({"1/1","1/2","1/4","1/8"})[t.div_ix] or "?"),
  }
  local nf = _draw_opts_panel_inverted(nil, rows, BEAT_OPTS_CURSOR[tid], BEAT_OPTS_FIRST[tid])
  if nf then BEAT_OPTS_FIRST[tid] = nf end
end

----------------------------------------------------------------
-- UI
----------------------------------------------------------------
function redraw()
  screen.clear()
  if UI and UI.FONT_FACE_ID then pcall(screen.font_face, UI.FONT_FACE_ID) end
  if Grid and Grid.redraw then Grid.redraw() end

  UI.draw_frame()
  UI.draw_tabs(TAB_TITLES, tab_selected)

  -- P tab
  if tab_selected == 7 then
    local names = preset_names()
    local ix    = util.clamp(preset_ui.sel, 1, #names)
    local desc  = preset_desc(ix) or ""
    if UI.draw_preset_overlay_2pane then
      UI.draw_preset_overlay_2pane("Musical Presets", names, ix, desc, {
        first = preset_ui.first, edge_pad = 1
      })
    elseif UI.draw_preset_picker then
      UI.draw_preset_picker("Presets", names, ix)
    end
    screen.update()
    return
  end

  if tab_selected <= 2 then
    local i = tab_selected
    if options_mode[i==1 and "A" or "B"] then
      draw_drones_opts(i)
      UI.draw_status_lamps(drones, beat[1].on, beat[2].on)
    else
      local s = drones[i]
      local chord_label = (CHORDS[s.chord_ix] and CHORDS[s.chord_ix].name) or "Off"
      local labels = {"On","Chord","Wave","Base","Voices","Det"}
      local values = {
        (s.running and "[X]" or "[ ]"),
        chord_label,
        ({"Sine","Tri","Saw","Square"})[s.waveform],
        math.floor(s.base_hz).."Hz",
        s.voices,
        string.format("%.2f", s.detune),
      }
      if UI.draw_two_col_split then UI.draw_two_col_split(labels, values, 3, param_selected, UI.drone_xy)
      else                          UI.draw_two_col(labels, values, param_selected, UI.drone_xy) end
      UI.draw_status_lamps(drones, beat[1].on, beat[2].on)
    end

  elseif tab_selected == 3 or tab_selected == 4 then
    local i = (tab_selected==3) and 1 or 2
    if options_mode[tostring(i)] then
      draw_beats_opts(i)
      UI.draw_status_lamps(drones, beat[1].on, beat[2].on)
    else
      local dnm = drum_name(beat[i].drum_ix or 1)
      local tone_ok = not DRUM_TUNELESS[dnm]
      local tune_txt  = tone_ok and (string.format("%.0fHz", beat[i].tune_hz)) or "—"
      local decay_txt = tone_ok and (string.format("%.2f",   beat[i].decay))   or "—"
      local L = {"Run","Steps","Fills","Rotate","Div","Drum","Tune","Decay"}
      local V = {
        beat[i].on and "[X]" or "[ ]",
        beat[i].steps, beat[i].fills, beat[i].rotate,
        ({"1/1","1/2","1/4","1/8"})[beat[i].div_ix],
        dnm, tune_txt, decay_txt,
      }
      UI.draw_two_col(L, V, param_selected, UI.beat_xy)
      UI.draw_pattern_bar(beat[i].pat or {}, beat[i].on, beat[i].step or 1)
      UI.draw_status_lamps(drones, beat[1].on, beat[2].on)
    end

  elseif tab_selected == 5 then
    local L = {"LFO","Type","Wave","Freq","Depth",  "Lvl","Wave","Det","Rvb","Noise","Safe"}
    local V = {
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
      (safety.on and "[X]" or "[ ]"),
    }
    if UI.draw_two_col_split then UI.draw_two_col_split(L, V, 6, param_selected, UI.mod_xy)
    else                          UI.draw_two_col(L, V, param_selected, UI.mod_xy) end
    UI.draw_status_lamps(drones, beat[1].on, beat[2].on)

  elseif tab_selected == 6 then
    local function mix_display(i) return drones[i].mix_live or drones[i].mix or 0 end
    local names  = {"A","B","1","2"}
    local values = {mix_display(1), mix_display(2), beat[1].amp or 0.95, beat[2].amp or 0.95}
    UI.draw_mix_bars(names, values, param_selected, 1.5)
    UI.draw_status_lamps(drones, beat[1].on, beat[2].on)
  end

  screen.update()
end

----------------------------------------------------------------
-- Encoders / Keys
----------------------------------------------------------------
function enc(n, d)
  -- E1: cycle tabs ALWAYS, including P
  if n == 1 then
    tab_selected = util.wrap(tab_selected + ((d>0) and 1 or -1), 1, 7)
    param_selected = 1
    redraw()
    return
  end

  -- P tab: E2 scrolls list (with early scrolling)
  if tab_selected == 7 and n == 2 and d ~= 0 then
    local names = preset_names()
    if #names > 0 then
      local step = (d > 0) and 1 or -1
      local old  = preset_ui.sel
      preset_ui.sel = util.clamp(preset_ui.sel + step, 1, #names)

      local per   = UI.PRESET_LIST_ROWS or 6
      local edge  = 1
      local last  = (preset_ui.first or 1) + per - 1

      if preset_ui.sel <= (preset_ui.first + edge) then
        preset_ui.first = math.max(1, preset_ui.sel - edge)
      elseif preset_ui.sel >= (last - edge) then
        preset_ui.first = math.max(1, math.min(#names - per + 1, preset_ui.sel - (per - 1 - edge)))
      end

      if preset_ui.sel ~= old then redraw() end
    end
    return
  end

  -- DRONES
  if tab_selected <= 2 then
    local i, s = tab_selected, drones[tab_selected]
    local in_opts = options_mode[tab_selected==1 and "A" or "B"]
    if n == 2 then
      if in_opts then
        if k1_held then
          local vis = _opts_vis_rows()
          local total = 12
          DRONE_OPTS_FIRST[i] = util.clamp(DRONE_OPTS_FIRST[i] + ((d>0) and 1 or -1) * vis, 1, math.max(1, total - vis + 1))
        else
          DRONE_OPTS_CURSOR[i] = util.clamp(DRONE_OPTS_CURSOR[i] + ((d>0) and 1 or -1), 1, 12)
        end
      else
        param_selected = util.wrap(param_selected + ((d>0) and 1 or -1), 1, 6)
      end
      redraw(); return
    elseif n == 3 then
      if in_opts then
        local cur = DRONE_OPTS_CURSOR[i]
        if     cur == 1 then s.lfo.enabled = not s.lfo.enabled; if s.lfo.enabled and not s.lfo.running then start_drone_lfo(i) else if s.lfo.running then stop_drone_lfo(i) end end
        elseif cur == 2 then local L={"sine","tri","saw","square"}; local ix=1 for k,v in ipairs(L) do if v==(s.lfo.shape or "sine") then ix=k end end; ix=util.wrap(ix+((d>0)and 1 or -1),1,#L); s.lfo.shape=L[ix]
        elseif cur == 3 then s.lfo.rate_hz = util.clamp((s.lfo.rate_hz or 0.15) + d*0.01, 0.01, 8)
        elseif cur == 4 then s.lfo.depth   = util.clamp((s.lfo.depth   or 0.15) + d*0.01, 0, 1.5)
        elseif cur == 5 then s.lfo.unipolar = not (s.lfo.unipolar)
        elseif cur == 6 then local T={"mix","pan","cutoff"}; local ix=1 for k,v in ipairs(T) do if v==(s.lfo.target or "mix") then ix=k end end; ix=util.wrap(ix+((d>0)and 1 or -1),1,#T); s.lfo.target=T[ix]
        elseif cur == 7 then s.filt_cutoff = util.clamp((s.filt_cutoff or 12000) + d*50, 80, 20000); apply_drone_filter(i)
        elseif cur == 8 then s.filt_res    = util.clamp((s.filt_res or 0.20) + d*0.01, 0.0, 0.99);   apply_drone_filter(i)
        elseif cur == 9 then s.attack = util.clamp(s.attack + d*0.01, 0, 5)
        elseif cur ==10 then s.decay  = util.clamp(s.decay  + d*0.01, 0, 5)
        elseif cur ==11 then s.sustain= util.clamp(s.sustain+ d*0.01, 0, 1)
        elseif cur ==12 then s.release= util.clamp(s.release+ d*0.01, 0, 10)
        end
        apply_env(s)
      else
        if     param_selected == 1 then toggle_drone(i)
        elseif param_selected == 2 then s.chord_ix = util.wrap((s.chord_ix or 1) + ((d>0) and 1 or -1), 1, #CHORDS)
        elseif param_selected == 3 then s.waveform = util.wrap(s.waveform + ((d>0) and 1 or -1), 1, 4); _call(engine.oscWaveShape, (s.waveform or 1) - 1)
        elseif param_selected == 4 then s.base_hz  = math.max(20, s.base_hz + d)
        elseif param_selected == 5 then s.voices   = util.clamp(s.voices + ((d>0) and 1 or -1), 1, 16)
        elseif param_selected == 6 then s.detune   = util.clamp(s.detune + d*0.05, 0, 10)
        end
        apply_env(s)
      end
      redraw(); return
    end
  end

  -- BEATS
  if tab_selected == 3 or tab_selected == 4 then
    local i = (tab_selected==3) and 1 or 2
    local in_opts = options_mode[tostring(i)] == true
    if n == 2 then
      if in_opts then
        if k1_held then
          local vis = _opts_vis_rows()
          local total = 14
          BEAT_OPTS_FIRST[i] = util.clamp(BEAT_OPTS_FIRST[i] + ((d>0) and 1 or -1) * vis, 1, math.max(1, total - vis + 1))
        else
          BEAT_OPTS_CURSOR[i] = util.clamp(BEAT_OPTS_CURSOR[i] + ((d>0) and 1 or -1), 1, 14)
        end
      else
        param_selected = util.wrap(param_selected + ((d>0) and 1 or -1), 1, 8)
      end
      redraw(); return
    elseif n == 3 then
      if in_opts then
        local t = beat[i]
        local cur = BEAT_OPTS_CURSOR[i]
        if     cur == 1  then rvb_mix         = util.clamp((rvb_mix or 0) + d*0.02, 0, 1); set_engine_mix_and_fx()
        elseif cur == 2  then t.global_prob   = util.clamp((t.global_prob or 1) + d*0.01, 0, 1)
        elseif cur == 3  then t.swing         = util.clamp((t.swing or 0) + d*0.01, 0, 0.6)
        elseif cur == 4  then t.drum_ix       = util.wrap((t.drum_ix or 1) + ((d>0) and 1 or -1), 1, #DRUM_NAMES)
        elseif cur == 5  then t.humanize_ms   = util.clamp((t.humanize_ms or 0) + d, 0, 25)
        elseif cur == 6  then t.ratchet       = util.clamp((t.ratchet or 1) + d, 1, 8)
        elseif cur == 7  then t.delay_on      = not t.delay_on
        elseif cur == 8  then t.delay_time_ms = util.clamp((t.delay_time_ms or 160) + d*5, 10, 2000)
        elseif cur == 9  then t.delay_fb      = util.clamp((t.delay_fb or 0.35) + d*0.02, 0.0, 0.95)
        elseif cur == 10 then t.delay_repeats = util.clamp((t.delay_repeats or 4) + d, 0, 12)
        elseif cur == 11 then t.steps         = util.clamp((t.steps or 16) + d, 1, 64); refresh_pat(i)
        elseif cur == 12 then t.fills         = util.clamp((t.fills or 8) + d, 0, 64);  refresh_pat(i)
        elseif cur == 13 then t.rotate        = util.clamp((t.rotate or 0) + d, -64, 64); refresh_pat(i)
        elseif cur == 14 then t.div_ix        = util.wrap((t.div_ix or 3) + ((d>0) and 1 or -1), 1, 4)
        end
      else
        if     param_selected == 1 then if beat[i].on then stop_beat(i) else start_beat(i) end
        elseif param_selected == 2 then beat[i].steps  = util.clamp(beat[i].steps + ((d>0) and 1 or -1), 1, 32); refresh_pat(i)
        elseif param_selected == 3 then beat[i].fills  = util.clamp(beat[i].fills + ((d>0) and 1 or -1), 0, beat[i].steps); refresh_pat(i)
        elseif param_selected == 4 then beat[i].rotate = util.clamp(beat[i].rotate + ((d>0) and 1 or -1), -64, 64); refresh_pat(i)
        elseif param_selected == 5 then beat[i].div_ix = util.wrap(beat[i].div_ix + ((d>0) and 1 or -1), 1, #beat_divs)
        elseif param_selected == 6 then beat[i].drum_ix = util.wrap((beat[i].drum_ix or 1) + ((d>0) and 1 or -1), 1, #DRUM_NAMES)
        elseif param_selected == 7 then local dnm = drum_name(beat[i].drum_ix or 1); if not DRUM_TUNELESS[dnm] then beat[i].tune_hz= util.clamp(beat[i].tune_hz + d, 20, 120) end
        elseif param_selected == 8 then local dnm = drum_name(beat[i].drum_ix or 1); if not DRUM_TUNELESS[dnm] then beat[i].decay  = util.clamp(beat[i].decay + d*0.02, 0.05, 2.0) end
        end
      end
      redraw(); return
    end
  end

  -- M (mod)
  if tab_selected == 5 then
    if n == 2 then
      param_selected = util.wrap(param_selected + ((d>0) and 1 or -1), 1, 11); redraw(); return
    elseif n == 3 then
      if     param_selected == 1  then lfo_on = not lfo_on
      elseif param_selected == 2  then lfo_target    = util.wrap(lfo_target + ((d>0) and 1 or -1), 1, 3)
      elseif param_selected == 3  then lfo_wave      = util.wrap(lfo_wave + ((d>0) and 1 or -1), 1, 4)
      elseif param_selected == 4  then lfo_freq      = util.clamp(lfo_freq + d*0.1, 0, 40)
      elseif param_selected == 5  then lfo_depth     = util.clamp(lfo_depth + d*0.02, 0, 1)
      elseif param_selected == 6  then subosc_level  = util.clamp(subosc_level + d*0.05, 0, 1)
      elseif param_selected == 7  then subosc_wave   = util.wrap(subosc_wave + ((d>0) and 1 or -1), 1, 4)
      elseif param_selected == 8  then subosc_detune = util.clamp(subosc_detune + d*0.1, 0, 12)
      elseif param_selected == 9  then rvb_mix       = util.clamp(rvb_mix + d*0.02, 0, 1)
      elseif param_selected == 10 then noise_level   = util.clamp(noise_level + d*0.02, 0, 1)
      elseif param_selected == 11 then safety.on     = not safety.on
      end
      set_engine_mix_and_fx(); redraw(); return
    end
  end

  -- MIX
  if tab_selected == 6 then
    if n == 2 then
      param_selected = util.wrap(param_selected + ((d>0) and 1 or -1), 1, 4); redraw(); return
    elseif n == 3 then
      if     param_selected == 1 then drones[1].mix = util.clamp((drones[1].mix or 0.7)+d*0.02, 0, 1.5); apply_drone_mix(1)
      elseif param_selected == 2 then drones[2].mix = util.clamp((drones[2].mix or 0.7)+d*0.02, 0, 1.5); apply_drone_mix(2)
      elseif param_selected == 3 then beat[1].amp   = util.clamp((beat[1].amp or 0.95)+d*0.02, 0, 1.5)
      elseif param_selected == 4 then beat[2].amp   = util.clamp((beat[2].amp or 0.95)+d*0.02, 0, 1.5)
      end
      redraw(); return
    end
  end
end

function key(n, z)
  if n==1 then k1_held = (z==1); return end
  if n==2 then k2_held = (z==1) end
  if n==3 then k3_held = (z==1) end
  if z ~= 1 then return end

  -- K1+K2 = toggle Options (entity pages only)
  if ((n==2 and k1_held) or (n==1 and k2_held)) then
    if is_entity_page() then
      local nm = entity_key_for_tab(tab_selected)
      options_mode[nm] = not options_mode[nm]
      redraw()
      return
    end
  end

  -- P tab actions
  if tab_selected == 7 then
    if n == 2 then -- K2 loads
      apply_preset(util.clamp(preset_ui.sel, 1, math.max(1, preset_count())))
      redraw()
      return
    end
  end

  -- K3 = PANIC (K1+K3 saves)
  if n == 3 then
    if k1_held then
      util.make_dir(norns.state.data)
      params:write(norns.state.data .. "autosave.pset")
      return
    end
    kill_all_sound()
    return
  end

  -- K2 = context toggle
  if n == 2 then
    if tab_selected <= 2 then
      toggle_drone(tab_selected)
    elseif tab_selected == 3 then
      if beat[1].on then stop_beat(1) else start_beat(1) end
    elseif tab_selected == 4 then
      if beat[2].on then stop_beat(2) else start_beat(2) end
    end
    redraw(); return
  end
end

----------------------------------------------------------------
-- Grid setup (robust attach: defer + hotplug retries)
----------------------------------------------------------------
local function grid_setup_once()
  if not Grid or not Grid.setup then return end
  if Grid.set_flip_y then pcall(Grid.set_flip_y, false) end
  Grid.setup({
    redraw = redraw,
    k1_held = function() return k1_held end,

    drone_is_running = function(i) return drone_is_running(i) end,
    drone_toggle = function(i) toggle_drone(i); redraw() end,

    beat_is_on = function(i) return beat[i].on end,
    beat_toggle = function(i) if beat[i].on then stop_beat(i) else start_beat(i) end end,

    get_mix = function(i) return drones[i].mix_live or drones[i].mix or 0 end,
    set_mix = function(i,v)
      drones[i].mix = util.clamp(v,0,1.5)
      drones[i].mix_live = drones[i].mix
      apply_drone_mix(i)
      redraw()
    end,

    get_beat_amp = function(i) return beat[i].amp or 0.95 end,
    set_beat_amp = function(i,v) beat[i].amp = util.clamp(v,0,1.5); redraw() end,

    goto_tab = function(ix)
      tab_selected = util.clamp(ix,1,7)
      param_selected = 1
      redraw()
    end,
    -- bottom-row options toggles (needed by lib/grid.lua)
    drone_options_toggle = function(i)
      local key = (i == 1) and "A" or "B"
      options_mode[key] = not options_mode[key]
      redraw()
    end,

    beat_options_toggle = function(i)
      local key = tostring(i) -- "1" or "2"
      options_mode[key] = not options_mode[key]
      redraw()
    end,

    -- bottom-row options toggles
    toggle_options = function(kind)
      if kind=="A" or kind=="B" or kind=="1" or kind=="2" then
        options_mode[kind] = not options_mode[kind]
        redraw()
      end
    end,
    is_options = function(kind) return (options_mode[kind] == true) end,

    -- Drone helpers
    drone_cycle_chord = function(i, dir)
      local s = drones[i]
      s.chord_ix = util.wrap((s.chord_ix or 1) + (dir or 1), 1, #CHORDS)
      apply_env(s); redraw()
    end,
    drone_cycle_wave = function(i, dir)
      local s=drones[i]; s.waveform = util.wrap((s.waveform or 1)+(dir or 1),1,4); _call(engine.oscWaveShape,(s.waveform-1)); redraw()
    end,
    drone_base      = function(i,d) local s=drones[i]; s.base_hz = math.max(20,(s.base_hz or 220)+d); apply_env(s); redraw() end,
    drone_partials  = function(i,d) local s=drones[i]; s.voices = util.clamp((s.voices or 3)+d,1,16); apply_env(s); redraw() end,
    drone_detune    = function(i,d) local s=drones[i]; s.detune = util.clamp((s.detune or 0)+d,0,10); apply_env(s); redraw() end,

    -- Beat helpers (mapping you specified)
    beat_cycle_div   = function(i, dir) beat[i].div_ix = util.wrap(beat[i].div_ix + (dir or 1), 1, #beat_divs); redraw() end,
    beat_change_drum = function(i, dir) beat[i].drum_ix = util.wrap((beat[i].drum_ix or 1) + (dir or 1), 1, #DRUM_NAMES); redraw() end,
    beat_cycle_drum  = function(i, dir) beat[i].drum_ix = util.wrap((beat[i].drum_ix or 1) + (dir or 1), 1, #DRUM_NAMES); redraw() end,
    beat_tune        = function(i, d) local dn=drum_name(beat[i].drum_ix or 1); if not DRUM_TUNELESS[dn] then beat[i].tune_hz = util.clamp((beat[i].tune_hz or 48)+d,20,120) end; redraw() end,
    beat_decay       = function(i, d) local dn=drum_name(beat[i].drum_ix or 1); if not DRUM_TUNELESS[dn] then beat[i].decay  = util.clamp((beat[i].decay or 0.6)+d,0.05,2.0) end; redraw() end,
    beat_amp         = function(i, d) beat[i].amp = util.clamp((beat[i].amp or 0.95)+d,0,1.5); redraw() end,
  })
end

-- Defer + retry attaches (handles midigrid enumeration races)
local function grid_setup_robust()
  clock.run(function()
    clock.sleep(0.20); grid_setup_once()
    clock.sleep(0.50); grid_setup_once()
    clock.sleep(1.00); grid_setup_once()
  end)
end

-- Hot-plug hooks
if midi then
  local _midi_add = midi.add
  midi.add = function(dev, ...)
    if _midi_add then _midi_add(dev, ...) end
    clock.run(function() clock.sleep(0.20); grid_setup_once() end)
  end
  local _midi_remove = midi.remove
  midi.remove = function(dev, ...)
    if _midi_remove then _midi_remove(dev, ...) end
    clock.run(function() clock.sleep(0.10); grid_setup_once() end)
  end
end
if grid then
  local _grid_add = grid.add
  grid.add = function(dev, ...)
    if _grid_add then _grid_add(dev, ...) end
    clock.run(function() clock.sleep(0.10); grid_setup_once() end)
  end
  local _grid_remove = grid.remove
  grid.remove = function(dev, ...)
    if _grid_remove then _grid_remove(dev, ...) end
    clock.run(function() clock.sleep(0.50); grid_setup_once() end)
  end
end

----------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------
local function autosave_path() return norns.state.data .. "autosave.pset" end
local function force_silent_boot()
  for i=1,DRONES do drone_hard_kill(i) end
  stop_beat(1); stop_beat(2)
  redraw()
end

function init()
  Params.setup({
    DRONES = DRONES,
    drones_settings = drones,
    apply_env = apply_env,
    set_engine_mix_and_fx = set_engine_mix_and_fx,

    refresh_beat1_pat = function() refresh_pat(1) end,
    refresh_beat2_pat = function() refresh_pat(2) end,
    start_beat1 = function() start_beat(1) end,
    stop_beat1  = function() stop_beat(1) end,
    start_beat2 = function() start_beat(2) end,
    stop_beat2  = function() stop_beat(2) end,

    apply_drone_mix = apply_drone_mix,
    redraw = redraw,
    set = PARAM_SET,
  })

  local p = autosave_path()
  if util.file_exists(p) then params:read(p) else util.make_dir(norns.state.data) params:write(p) end
  params:bang()

  force_silent_boot()

  clock.run(function()
    clock.sleep(0.15)
    set_engine_mix_and_fx()
    start_lfo()
    start_safety()
    for i=1,DRONES do if drones[i].lfo.enabled then start_drone_lfo(i) end; apply_drone_filter(i) end
    redraw()
  end)

  grid_setup_robust()
end

function cleanup()
  stop_lfo()
  stop_safety()
  if Grid and Grid.cleanup then pcall(Grid.cleanup) end
  for i=1,DRONES do drone_hard_kill(i); stop_drone_lfo(i) end
  stop_beat(1); stop_beat(2)
  util.make_dir(norns.state.data)
  params:write(autosave_path())
end
