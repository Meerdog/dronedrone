-- lib/presets.lua
-- Central place to define musical presets.

local M = {}

----------------------------------------------------------------
-- PRESET LIST
-- Fields:
--   name, desc
--   drones: { [1] = {...}, [2] = {...} }  -- base_hz, partials, detune, waveform(1..4), attack, decay, sustain, release, mix
--   beats : { [1] = {...}, [2] = {...} }  -- steps, fills, rotate, div_ix(1..4), drum_ix(1..9), tune_hz, decay, amp
--   lfo   : { on, target(1..3), wave(1..4), freq, depth }
--   fx    : { main_level, sub={level,detune,wave}, chorus, noise, filter={cutoff,resonance}, reverb={mix,room,damp} }
----------------------------------------------------------------

M.list = {

  ----------------------------------------------------------------
  -- 1) Dark Glacier — auto-loads (first preset)
  ----------------------------------------------------------------
  {
    name = "Dark Glacier",
    desc = "Slow, brooding tri/saw",
    drones = {
      { base_hz=360, partials=3, detune=0.50, waveform=2, attack=0.60, decay=1.00, sustain=0.80, release=2.50, mix=0.70 },
      { base_hz=340, partials=4, detune=0.60, waveform=3, attack=0.70, decay=1.10, sustain=0.75, release=2.80, mix=0.70 },
    },
    beats = {
      { steps=16, fills=5, rotate=0, div_ix=3, drum="Kick", drum_ix=1, tune_hz=48, decay=0.60, amp=0.95 }, -- Kick
      { steps=16, fills=8, rotate=0, div_ix=3, drum="Tom",  drum_ix=9, tune_hz=55, decay=0.45, amp=0.95 }, -- Tom
    },
    lfo = { on=true, target=2, wave=1, freq=2.0, depth=0.20 }, -- Amp
    fx  = {
      main_level = 1.0,
      sub    = { level=0.50, detune=0.00, wave=1 },
      chorus = 0.20, noise=0.00,
      filter = { cutoff=12000, resonance=0.20 },
      reverb = { mix=0.25, room=0.60, damp=0.50 },
    },
  },

  ----------------------------------------------------------------
  -- 2) Meadow Glow — warm/soft variant, tweaked beats
  ----------------------------------------------------------------
  {
    name = "Meadow Glow",
    desc = "Gentle, airy pad/clap",
    drones = {
      { base_hz=224, partials=5, detune=0.34, waveform=1, attack=0.55, decay=0.95, sustain=0.82, release=2.30, mix=0.75 },
      { base_hz=272, partials=4, detune=0.42, waveform=2, attack=0.62, decay=1.05, sustain=0.76, release=2.50, mix=0.72 },
    },
    beats = {
      -- Clap on a 12-step, slightly rotated; snare half-time-ish with rotate
      { steps=12, fills=5, rotate=2, div_ix=2, drum="Clap",  drum_ix=5, tune_hz=0,   decay=0.28, amp=0.88 }, -- Clap
      { steps=16, fills=6, rotate=3, div_ix=2, drum="Snare", drum_ix=2, tune_hz=170, decay=0.38, amp=0.92 }, -- Snare
    },
    lfo = { on=true, target=1, wave=2, freq=0.6, depth=0.32 }, -- Resonance, triangle
    fx  = {
      main_level = 0.90,
      sub    = { level=0.40, detune=0.05, wave=2 },
      chorus = 0.26, noise=0.04,
      filter = { cutoff=9200, resonance=0.24 },
      reverb = { mix=0.30, room=0.56, damp=0.46 },
    },
  },

  ----------------------------------------------------------------
  -- 3) Neon Artery — like City Neon, hats busier & offset
  ----------------------------------------------------------------
  {
    name = "Neon Artery",
    desc = "Bright saws, busy hats",
    drones = {
      { base_hz=328, partials=6, detune=0.30, waveform=3, attack=0.22, decay=0.70, sustain=0.64, release=1.60, mix=0.80 },
      { base_hz=262, partials=5, detune=0.27, waveform=3, attack=0.20, decay=0.76, sustain=0.60, release=1.70, mix=0.78 },
    },
    beats = {
      -- Denser CH with rotate, OH sparser but longer decay
      { steps=16, fills=10, rotate=1, div_ix=3, drum="CH", drum_ix=3, tune_hz=0, decay=0.16, amp=0.92 }, -- CH
      { steps=16, fills=4,  rotate=5, div_ix=3, drum="OH", drum_ix=4, tune_hz=0, decay=0.34, amp=0.86 }, -- OH
    },
    lfo = { on=true, target=3, wave=3, freq=0.9, depth=0.25 }, -- Pan, saw
    fx  = {
      main_level = 0.95,
      sub    = { level=0.28, detune=0.04, wave=3 },
      chorus = 0.18, noise=0.02,
      filter = { cutoff=13000, resonance=0.18 },
      reverb = { mix=0.17, room=0.40, damp=0.40 },
    },
  },

  ----------------------------------------------------------------
  -- 4) Cavern Echo — cousin of Cavern Choir, sparser low hits + tom
  ----------------------------------------------------------------
  {
    name = "Cavern Echo",
    desc = "Wide pads, sparse pulses",
    drones = {
      { base_hz=188, partials=7, detune=0.56, waveform=2, attack=0.74, decay=1.20, sustain=0.85, release=3.20, mix=0.80 },
      { base_hz=232, partials=6, detune=0.50, waveform=1, attack=0.80, decay=1.30, sustain=0.82, release=3.40, mix=0.78 },
    },
    beats = {
      -- Rare kick on whole notes + gentle tom pattern on 12 w/ rotate
      { steps=16, fills=2, rotate=0, div_ix=1, drum="Kick", drum_ix=1, tune_hz=42,  decay=0.72, amp=0.88 }, -- Kick
      { steps=12, fills=3, rotate=2, div_ix=2, drum="Tom",  drum_ix=9, tune_hz=140, decay=0.28, amp=0.76 }, -- Tom
    },
    lfo = { on=true, target=2, wave=1, freq=0.35, depth=0.30 }, -- Amp, sine
    fx  = {
      main_level = 0.85,
      sub    = { level=0.56, detune=0.08, wave=1 },
      chorus = 0.30, noise=0.00,
      filter = { cutoff=8200, resonance=0.22 },
      reverb = { mix=0.40, room=0.72, damp=0.56 },
    },
  },

}

----------------------------------------------------------------
-- HELPER API
----------------------------------------------------------------
function M.names()
  local t = {}
  for i,p in ipairs(M.list) do t[i] = p.name end
  return t
end

function M.desc(i)
  local p = M.list[i]
  return p and p.desc or ""
end

function M.get(i) return M.list[i] end
function M.count() return #M.list end

return M
