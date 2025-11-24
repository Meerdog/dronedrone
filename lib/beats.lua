-- lib/beats.lua
-- Euclidean beat module for dronedrone
-- Uses lib/constants.lua and optional lib/engine_bus.lua

local M = {}

-- injected deps / context (some get safe defaults)
local EB, params, util, on_redraw

-- -----------------------------------------------------------
-- constants (ALWAYS have a default so calls before setup() are safe)
-- -----------------------------------------------------------
local function _load_constants()
  local ok, mod = pcall(function() return include("lib/constants") end)
  if ok and type(mod) == "table" then return mod end
  -- Safe defaults
  return {
    BEAT_DIVS  = {1, 1/2, 1/4, 1/8},
    DRUM_NAMES = {"Kick","Snare","CH","OH","Clap","Rim","Cow","Clv","Tom"},
    DRUM_TUNELESS = { Clap=true, Rim=true, Cow=true, Clv=true },
    LIMITS = {
      TUNE_HZ = {20, 120},
      DECAY   = {0.05, 2.0},
      AMP     = {0.0, 1.5},
    },
  }
end

-- Start with safe constants; setup() can override later.
local C = _load_constants()

-- -----------------------------------------------------------
-- module state (two tracks)
-- -----------------------------------------------------------
local S = {
  [1] = { on=false, steps=16, fills=5, rotate=0, div_ix=3,
          drum_ix=1, tune_hz=48, decay=0.60, amp=0.95,
          pattern={}, step=1, clock=nil, started_at=0, host_mode=false },
  [2] = { on=false, steps=16, fills=8, rotate=0, div_ix=3,
          drum_ix=1, tune_hz=55, decay=0.45, amp=0.95,
          pattern={}, step=1, clock=nil, started_at=0, host_mode=false },
}

-- -----------------------------------------------------------
-- helpers
-- -----------------------------------------------------------
local function _names() return (C and C.DRUM_NAMES) or {} end
local function _name(ix)
  local n = _names()
  return n[((ix or 1)-1) % math.max(1, #n) + 1] or "Kick"
end

local function _is_tuneless(name)
  local m = (C and C.DRUM_TUNELESS) or {}
  return m[name] == true
end

-- safe call
local function _call(fn, ...)
  if not fn then return false end
  local ok = pcall(fn, ...)
  return ok
end

-- engine drum router (only used in self-contained mode)
local function _trigger_drum(st)
  local name = _name(st.drum_ix)
  local amp, tone, dec = st.amp or 1.0, st.tune_hz or 50, st.decay or 0.5

  -- Try EngineBus unified trigger first (if available)
  if EB and EB.trigger_drum then
    EB.trigger_drum(name, amp, tone, dec)
    return
  end

  -- Fall back to raw engine calls
  if     name == "Kick"  then _call(engine.kick,    amp, tone, dec)
  elseif name == "Snare" then _call(engine.snare,   amp, tone, dec)
  elseif name == "CH"    then _call(engine.ch,      amp, tone, dec)
  elseif name == "OH"    then _call(engine.oh,      amp, tone, dec)
  elseif name == "Clap"  then _call(engine.clap,    amp)
  elseif name == "Rim"   then _call(engine.rimshot, amp)
  elseif name == "Cow"   then _call(engine.cowbell, amp)
  elseif name == "Clv"   then _call(engine.claves,  amp)
  elseif name == "Tom"   then _call(engine.mt,      amp, tone, dec)
  end
end

-- -----------------------------------------------------------
-- Euclid + pattern refresh
-- -----------------------------------------------------------
local function _euclid(steps, fills, rotate)
  local pat, bucket = {}, 0
  steps = math.max(1, steps or 1)
  fills = math.max(0, math.min(fills or 0, steps))
  for i=1,steps do
    bucket = bucket + fills
    if bucket >= steps then bucket = bucket - steps; pat[i] = 1 else pat[i] = 0 end
  end
  local rot = ((rotate or 0) % steps + steps) % steps
  if rot ~= 0 then
    local out = {}
    for i=1,steps do out[i] = pat[((i-1-rot) % steps)+1] end
    pat = out
  end
  return pat
end

local function _refresh(i)
  local st = S[i]; if not st then return end
  st.pattern = _euclid(st.steps, st.fills, st.rotate)
  if st.step > st.steps then st.step = 1 end
end

local function _stop_clock(i)
  local st = S[i]; if not st then return end
  if st.clock then pcall(clock.cancel, st.clock) end
  st.clock = nil
end

-- -----------------------------------------------------------
-- public API
-- -----------------------------------------------------------
function M.setup(opts)
  EB        = opts and opts.EngineBus or nil
  local newC = (opts and opts.constants) or _load_constants()
  -- normalize & ensure minimal fields
  newC.LIMITS        = newC.LIMITS        or { TUNE_HZ={20,120}, DECAY={0.05,2.0}, AMP={0.0,1.5} }
  newC.BEAT_DIVS     = newC.BEAT_DIVS     or {1, 1/2, 1/4, 1/8}
  newC.DRUM_NAMES    = newC.DRUM_NAMES    or {"Kick","Snare","CH","OH","Clap","Rim","Cow","Clv","Tom"}
  newC.DRUM_TUNELESS = newC.DRUM_TUNELESS or { Clap=true, Rim=true, Cow=true, Clv=true }
  C = newC

  params    = opts and opts.params or nil
  util      = (opts and opts.util) or require "util"
  on_redraw = opts and opts.on_redraw or nil

  _refresh(1); _refresh(2)
end

-- expose helpers
function M.euclid(steps, fills, rotate) return _euclid(steps, fills, rotate) end
function M.names() return _names() end
function M.drum_name(ix) return _name(ix) end

function M.state(i) return S[i] end
function M.is_on(i) return S[i] and S[i].on == true end
function M.refresh(i) _refresh(i); if on_redraw then on_redraw() end end

-- Start clock.
-- Mode A (hosted): start(i, {div=..., get_step=fn, step_cb=fn}, pattern_provider_fn)
-- Mode B (self-contained): start(i) with no extra args
function M.start(i, cfg, pattern_provider)
  local st = S[i]; if not st then return end
  M.stop(i)

  -- FINAL GUARD: ensure C exists even if setup() was never called
  if not C or type(C) ~= "table" then C = _load_constants() end
  C.BEAT_DIVS = C.BEAT_DIVS or {1, 1/2, 1/4, 1/8}

  st.on = true
  st.started_at = (util and util.time and util.time()) or os.time()

  local hosted = (type(cfg) == "table" and type(pattern_provider) == "function")
  st.host_mode = hosted

  if hosted then
    st.clock = clock.run(function()
      local div = cfg.div or (C.BEAT_DIVS[st.div_ix] or 1/4)
      while st.on do
        clock.sync(div)
        local pat = pattern_provider() or {}
        local step = (cfg.get_step and cfg.get_step()) or st.step
        local active = (pat[step] == 1) and 1 or 0
        if cfg.step_cb then cfg.step_cb(active) end
        if on_redraw then on_redraw() end
      end
    end)
  else
    _refresh(i)
    st.clock = clock.run(function()
      local div = C.BEAT_DIVS[st.div_ix] or 1/4
      while st.on do
        clock.sync(div)
        if st.pattern[st.step] == 1 then _trigger_drum(st) end
        st.step = (st.step % st.steps) + 1
        if on_redraw then on_redraw() end
      end
    end)
  end
end

function M.stop(i)
  local st = S[i]; if not st then return end
  st.on = false
  st.started_at = 0
  _stop_clock(i)
end

-- --------- Self-contained setters ----------
function M.set_steps(i, v)
  local st=S[i]; if not st then return end
  st.steps = math.max(1, math.floor(v or st.steps)); _refresh(i)
end

function M.set_fills(i, v)
  local st=S[i]; if not st then return end
  st.fills = math.max(0, math.min(math.floor(v or st.fills), st.steps)); _refresh(i)
end

function M.set_rotate(i, v)
  local st=S[i]; if not st then return end
  st.rotate = math.floor(v or st.rotate); _refresh(i)
end

function M.set_div_ix(i, v)
  local st=S[i]; if not st then return end
  local n=#(C.BEAT_DIVS or {1,1/2,1/4,1/8})
  st.div_ix = ((v-1) % math.max(1,n)) + 1
end

function M.set_drum_ix(i, v)
  local st=S[i]; if not st then return end
  local n=#(C.DRUM_NAMES or {"Kick","Snare","CH","OH","Clap","Rim","Cow","Clv","Tom"})
  st.drum_ix = ((v-1) % math.max(1,n)) + 1
end

function M.set_tune_hz(i, v)
  local st=S[i]; if not st then return end
  local lo,hi = (C.LIMITS.TUNE_HZ or {20,120})[1], (C.LIMITS.TUNE_HZ or {20,120})[2]
  local name = _name(st.drum_ix)
  if _is_tuneless(name) then return end
  st.tune_hz = math.max(lo, math.min(hi, math.floor(v or st.tune_hz)))
end

function M.set_decay(i, v)
  local st=S[i]; if not st then return end
  local lo,hi = (C.LIMITS.DECAY or {0.05,2.0})[1], (C.LIMITS.DECAY or {0.05,2.0})[2]
  local name = _name(st.drum_ix)
  if _is_tuneless(name) then return end
  st.decay = math.max(lo, math.min(hi, v or st.decay))
end

function M.set_amp(i, v)
  local st=S[i]; if not st then return end
  local lo,hi = (C.LIMITS.AMP or {0.0,1.5})[1], (C.LIMITS.AMP or {0.0,1.5})[2]
  st.amp = math.max(lo, math.min(hi, v or st.amp))
end

return M
