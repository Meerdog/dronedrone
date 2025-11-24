-- lib/engine_bus.lua
-- Thin wrapper around SuperCollider engine calls so the main script
-- never talks to `engine` directly.

local util = require "util"
local C    = include("lib/constants")

local Bus = {}

-- -----------------------------------------------------------
-- Helpers
-- -----------------------------------------------------------
local function _range_for_slot(slot)
  local base = (C.DRONE_VOICE_OFFSET[slot] or 0)
  return base + 1, base + C.VOICE_SPAN
end

local function _pcall(fn, ...)
  if not fn then return end
  pcall(fn, ...)
end

-- -----------------------------------------------------------
-- Global init / safety
-- -----------------------------------------------------------
function Bus.init()
  -- default limiter safety (if exposed by the engine)
  _pcall(engine.limitThresh, 0.95)
  _pcall(engine.limitDur,    0.01)
end

function Bus.panic()
  if engine.panic then pcall(engine.panic) end
end

-- -----------------------------------------------------------
-- Per-drone env / mix / pan
-- -----------------------------------------------------------
function Bus.apply_env(env)
  _pcall(engine.attack,  env.attack  or 0.60)
  _pcall(engine.decay,   env.decay   or 1.00)
  _pcall(engine.sustain, env.sustain or 0.80)
  _pcall(engine.release, env.release or 2.50)
end

function Bus.apply_drone_mix(slot, lvl)
  local lo, hi = _range_for_slot(slot)
  if engine.setLevelRange then
    _pcall(engine.setLevelRange, lo, hi, lvl or 0.7)
  elseif engine.setAmpRange then
    _pcall(engine.setAmpRange,   lo, hi, lvl or 0.7)
  end
end

function Bus.set_pan_range(slot, pan)
  local lo, hi = _range_for_slot(slot)
  _pcall(engine.setPanRange, lo, hi, util.clamp(pan or 0, -1, 1))
end

-- -----------------------------------------------------------
-- Global mix / FX
-- -----------------------------------------------------------
-- opts = {
--   main_level, noise, chorus,
--   sub_level, sub_detune, sub_wave (1..4 -> engine expects 0..3),
--   cutoff, resonance,
--   rvb_mix, rvb_room, rvb_damp
-- }
function Bus.set_mix_and_fx(opts)
  if not opts then return end

  _pcall(engine.mainOscLevel, opts.main_level or 1.0)
  _pcall(engine.noiseLevel,   opts.noise      or 0.10)
  _pcall(engine.chorusMix,    opts.chorus     or 0.20)

  -- sub osc (engine uses 0..3)
  if opts.sub_level  ~= nil then _pcall(engine.subOscLevel,  opts.sub_level)  end
  if opts.sub_detune ~= nil then _pcall(engine.subOscDetune, opts.sub_detune) end
  if opts.sub_wave   ~= nil then _pcall(engine.subOscWave,   (opts.sub_wave - 1)) end

  if engine.cutoff    and opts.cutoff    then engine.cutoff(opts.cutoff) end
  if engine.resonance and opts.resonance then engine.resonance(opts.resonance) end

  if opts.rvb_mix  ~= nil then _pcall(engine.reverbMix,  opts.rvb_mix)  end
  if opts.rvb_room ~= nil then _pcall(engine.reverbRoom, opts.rvb_room) end
  if opts.rvb_damp ~= nil then _pcall(engine.reverbDamp, opts.rvb_damp) end
end

-- -----------------------------------------------------------
-- Voice management (per slot)
-- -----------------------------------------------------------
function Bus.kill_range(slot)
  local lo, hi = _range_for_slot(slot)
  _pcall(engine.freeRange, lo, hi)
  if engine.setLevelRange then _pcall(engine.setLevelRange, lo, hi, 0) end
  _pcall(engine.noteOffRange, lo, hi)
end

function Bus.free_range_no_level(slot)
  local lo, hi = _range_for_slot(slot)
  _pcall(engine.noteOffRange, lo, hi)
  _pcall(engine.freeRange,    lo, hi)
end

function Bus.hard_kill(slot)
  local lo, hi = _range_for_slot(slot)
  _pcall(engine.freeRange, lo, hi)
  if engine.setLevelRange then
    _pcall(engine.setLevelRange, lo, hi, 0.0)
  elseif engine.setAmpRange then
    _pcall(engine.setAmpRange,   lo, hi, 0.0)
  end
  _pcall(engine.noteOffRange, lo, hi)
end

-- -----------------------------------------------------------
-- Osc / notes
-- -----------------------------------------------------------
-- 1..4 -> engine expects 0..3
function Bus.set_osc_wave_shape(wave_ix_1_based)
  _pcall(engine.oscWaveShape, (wave_ix_1_based or 1) - 1)
end

function Bus.note_on(voice_id, hz, amp)
  _pcall(engine.noteOn, voice_id, hz, amp)
end

function Bus.note_off(voice_id)
  _pcall(engine.noteOff, voice_id)
end

-- -----------------------------------------------------------
-- Drum router (index or name)
-- -----------------------------------------------------------
local DRUM_NAMES = C.DRUM_NAMES

local function _drum_name(ix_or_name)
  if type(ix_or_name) == "number" then
    return DRUM_NAMES[ix_or_name] or "Kick"
  end
  return ix_or_name or "Kick"
end

-- (amp, tone, decay) where appropriate; some instruments ignore tone/decay
function Bus.trigger_drum(ix_or_name, amp, tone, decay)
  local name = _drum_name(ix_or_name)

  if     name == "Kick"  and engine.kick    then engine.kick(amp, tone, decay)
  elseif name == "Snare" and engine.snare   then engine.snare(amp, tone, decay) -- snappy optional in engine
  elseif name == "CH"    and engine.ch      then engine.ch(amp, tone, decay)
  elseif name == "OH"    and engine.oh      then engine.oh(amp, tone, decay)
  elseif name == "Clap"  and engine.clap    then engine.clap(amp)
  elseif name == "Rim"   and engine.rimshot then engine.rimshot(amp)
  elseif name == "Cow"   and engine.cowbell then engine.cowbell(amp)
  elseif name == "Clv"   and engine.claves  then engine.claves(amp)
  elseif name == "Tom"   and engine.mt      then engine.mt(amp, tone, decay)
  end
end

return Bus
