-- lib/constants.lua
-- Small shared constants for dronedrone

local C = {}

----------------------------------------------------------------
-- Labels / UI
----------------------------------------------------------------
-- Tab order for the top nav (A, B, beat 1, beat 2, Mod, Mix)
C.TAB_TITLES   = { "A", "B", "1", "2", "Mod", "Mix" }
-- Drone labels (left/right)
C.DRONE_NAMES  = { "A", "B" }
-- Drum labels (index maps directly to engine routing in trigger_drum)
C.DRUM_NAMES   = { "Kick", "Snare", "CH", "OH", "Clap", "Rim", "Cow", "Clv", "Tom" }

-- How many rows the preset list shows (used by UI overlay scroll math)
C.PRESET_LIST_ROWS = 6

----------------------------------------------------------------
-- Engine voice mapping
----------------------------------------------------------------
-- Each drone gets a block of IDs so partials never collide
C.DRONE_VOICE_OFFSET = { 0, 32 }
C.VOICE_SPAN         = 32


-------------
-- Chords
-------------
C.CHORDS = {
  { name = "Off",  semitones = {} },        -- keep old single-note/partials behavior
  { name = "Maj",  semitones = {0, 4, 7} },
  { name = "Min",  semitones = {0, 3, 7} },
  { name = "Sus2", semitones = {0, 2, 7} },
  { name = "Sus4", semitones = {0, 5, 7} },
  { name = "Maj7", semitones = {0, 4, 7, 11} },
  { name = "Min7", semitones = {0, 3, 7, 10} },
  { name = "Dom7", semitones = {0, 4, 7, 10} },
  { name = "Add9", semitones = {0, 4, 7, 14} },
}

----------------------------------------------------------------
-- Euclidean / beat timing
----------------------------------------------------------------
-- Clock divisions shown in UI (index -> value)
C.BEAT_DIVS = { 1, 1/2, 1/4, 1/8 }

----------------------------------------------------------------
-- Ranges / clamps (used across UI, Beats, and safety)
----------------------------------------------------------------
C.TUNE_MIN   = 20
C.TUNE_MAX   = 120
C.DECAY_MIN  = 0.05
C.DECAY_MAX  = 2.0
C.AMP_MIN    = 0.0
C.AMP_MAX    = 1.5

-- Per-drone mix fader max on Mix page
C.MIX_MAX    = 1.5

-- After a soft stop, how long to wait before allowing relaunch
C.STOP_COOLDOWN = 0.30

----------------------------------------------------------------
-- Optional defaults (only use if you want one place to tweak)
----------------------------------------------------------------
C.DEFAULTS = {
  -- Drone envelope defaults (A/D/S/R)
  drone_env = { attack = 0.60, decay = 1.00, sustain = 0.80, release = 2.50 },

  -- Global mix/FX defaults
  fx = {
    main_level = 1.0,
    noise      = 0.10,
    chorus     = 0.20,
    filter     = { cutoff = 12000, resonance = 0.20 },
    reverb     = { mix = 0.25, room = 0.60, damp = 0.50 },
    limiter    = { thresh = 0.95, dur = 0.01 },
    sub        = { level = 0.50, detune = 0.0, wave = 1 }, -- 1=Sine,2=Tri,3=Saw,4=Square
  },

  -- Global LFO defaults
  lfo = {
    on    = true,
    target= 1,    -- 1=Res, 2=Amp, 3=Pan
    wave  = 1,    -- 1=Sine, 2=Tri, 3=Saw, 4=Square
    freq  = 2.0,
    depth = 0.20,
  },
}

return C
