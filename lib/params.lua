-- lib/params.lua
-- Sequential, non-nested groups with exact counts.
-- Wires every param to the host script via ctx.set(key, value).

local cs = require "controlspec"

local Params = {}

local function ctrl(min, max, warp, step, default, units)
  return cs.new(min, max, warp, step or 0, default, units)
end

function Params.setup(ctx)

  ----------------------------------------------------------------
-- GROUP X: Musical Presets  (1 param)
----------------------------------------------------------------
params:add_group("Musical Presets", 1)

-- helper: apply a table of fields to a drone; if it’s running, relaunch it
local function _set_drone(slot, t)
  if not ctx or not ctx.drones_settings or not ctx.drones_settings[slot] then return end
  local s = ctx.drones_settings[slot]
  local was_running = (ctx.drone_is_running and ctx.drone_is_running(slot)) or false

  if was_running and ctx.stop_drone then ctx.stop_drone(slot) end
  for k, v in pairs(t or {}) do s[k] = v end
  if ctx.apply_env then ctx.apply_env(s) end
  if ctx.apply_drone_mix then ctx.apply_drone_mix(slot) end
  if was_running and ctx.launch_drone then ctx.launch_drone(slot) end
end

params:add_option(
  "musical_preset_load",
  "Load Musical Preset",{
    "Warm Choir Bed  • tri stacks, slow res LFO",
    "Shimmer Wash     • saw/square + pan LFO",
    "Harmonic Fifths  • square stacks, gentle res",
    "Dark Glacier     • low tri/saw, amp LFO, big verb",},
  1
)

params:set_action("musical_preset_load", function(v)
  if v == 1 then return end

  if v == 2 then
    -- 1) Warm choir bed
    _set_drone(1, {waveform=2, partials=7, detune=0.35, attack=4.0, decay=1.0, sustain=0.85, release=14.0, base_hz=220, mix=0.80})
    _set_drone(2, {waveform=2, partials=6, detune=0.28, attack=4.0, decay=1.0, sustain=0.85, release=14.0, base_hz=330, mix=0.70})
    params:set("lfo_on", 2); params:set("lfo_target", 1); params:set("lfo_wave", 1); params:set("lfo_freq", 0.25); params:set("lfo_depth", 0.75)
    params:set("fx_cutoff", 3500); params:set("fx_reson", 0.32); params:set("fx_chorus", 0.22)
    params:set("fx_revmix", 0.30); params:set("fx_revroom", 0.70); params:set("fx_revdamp", 0.45); params:set("fx_noise", 0.04)
    params:set("sub_level", 0.05); params:set("sub_wave", 1); params:set("sub_detune", 0.0)

  elseif v == 3 then
    -- 2) Shimmer wash
    _set_drone(1, {waveform=3, partials=9, detune=0.20, attack=2.5, decay=1.0, sustain=0.85, release=10.0, mix=0.75})
    _set_drone(2, {waveform=4, partials=5, detune=0.15, attack=2.5, decay=1.0, sustain=0.85, release=10.0, mix=0.75})
    params:set("lfo_on", 2); params:set("lfo_target", 3); params:set("lfo_wave", 2); params:set("lfo_freq", 0.08); params:set("lfo_depth", 0.70)
    params:set("fx_cutoff", 7000); params:set("fx_reson", 0.22); params:set("fx_chorus", 0.28)
    params:set("fx_revmix", 0.32); params:set("fx_revroom", 0.70); params:set("fx_revdamp", 0.40); params:set("fx_noise", 0.08)
    params:set("sub_level", 0.25); params:set("sub_wave", 2); params:set("sub_detune", 0.3)

  elseif v == 4 then
    -- 3) Harmonic organ  (B = 5th above A; leave base_hz as-is unless you want to set it)
    _set_drone(1, {waveform=4, partials=6, detune=0.15, attack=1.5, decay=1.0, sustain=0.90, release=8.0,  mix=0.85})
    _set_drone(2, {waveform=4, partials=4, detune=0.12, attack=1.5, decay=1.0, sustain=0.90, release=8.0,  mix=0.75})
    params:set("lfo_on", 2); params:set("lfo_target", 1); params:set("lfo_wave", 1); params:set("lfo_freq", 0.18); params:set("lfo_depth", 0.60)
    params:set("fx_cutoff", 2800); params:set("fx_reson", 0.40); params:set("fx_chorus", 0.18)
    params:set("fx_revmix", 0.25); params:set("fx_revroom", 0.65); params:set("fx_revdamp", 0.45); params:set("fx_noise", 0.03)
    params:set("sub_level", 0.00)

  elseif v == 5 then
    -- 4) Dark glacier
    _set_drone(1, {waveform=3, partials=5, detune=0.45, attack=5.0, decay=1.0, sustain=0.85, release=18.0, base_hz=65,  mix=0.70})
    _set_drone(2, {waveform=2, partials=7, detune=0.25, attack=5.0, decay=1.0, sustain=0.85, release=18.0, base_hz=131, mix=0.60})
    params:set("lfo_on", 2); params:set("lfo_target", 2); params:set("lfo_wave", 1); params:set("lfo_freq", 0.08); params:set("lfo_depth", 0.35)
    params:set("fx_cutoff", 2000); params:set("fx_reson", 0.35); params:set("fx_chorus", 0.20)
    params:set("fx_revmix", 0.35); params:set("fx_revroom", 0.80); params:set("fx_revdamp", 0.55); params:set("fx_noise", 0.05)
    params:set("sub_level", 0.30); params:set("sub_wave", 2); params:set("sub_detune", 0.4)
  end

  if ctx.set_engine_mix_and_fx then ctx.set_engine_mix_and_fx() end
  if ctx.redraw then ctx.redraw() end

  -- return selector to neutral so it doesn’t reload on save
  params:set("musical_preset_load", 1)
end)



  ----------------------------------------------------------------
  -- GROUP 1: Mix & Sub  (4 params)
  ----------------------------------------------------------------
  params:add_group("Mix & Sub", 4)

  params:add{
    type="control", id="main_level", name="Main Level",
    controlspec = ctrl(0, 1, 'lin', 0, 1.0),
    formatter = function(p) return string.format("%.2f", p:get()) end,
  }
  params:set_action("main_level", function(v) ctx.set("main_level", v) end)

  params:add{
    type="control", id="sub_level", name="Sub Level",
    controlspec = ctrl(0, 1, 'lin', 0, 0.5),
    formatter = function(p) return string.format("%.2f", p:get()) end,
  }
  params:set_action("sub_level", function(v) ctx.set("sub_level", v) end)

  params:add_option("sub_wave", "Sub Wave", {"Sine","Tri","Saw","Square"}, 1)
  params:set_action("sub_wave", function(ix) ctx.set("sub_wave", ix) end)

  params:add{
    type="control", id="sub_detune", name="Sub Detune (st)",
    controlspec = ctrl(0, 12, 'lin', 0, 0.0, "st"),
    formatter = function(p) return string.format("%.1f st", p:get()) end,
  }
  params:set_action("sub_detune", function(v) ctx.set("sub_detune", v) end)

  ----------------------------------------------------------------
  -- GROUP 2: FX  (7 params)  (UI-hidden in your app, but saved here)
  ----------------------------------------------------------------
  params:add_group("FX", 7)

  params:add{
    type="control", id="fx_chorus", name="Chorus Mix",
    controlspec = ctrl(0, 1, 'lin', 0, 0.2),
    formatter = function(p) return string.format("%.2f", p:get()) end,
  }
  params:set_action("fx_chorus", function(v) ctx.set("fx_chorus", v) end)

  params:add{
    type="control", id="fx_noise", name="Noise Level",
    controlspec = ctrl(0, 1, 'lin', 0, 0.1),
    formatter = function(p) return string.format("%.2f", p:get()) end,
  }
  params:set_action("fx_noise", function(v) ctx.set("fx_noise", v) end)

  params:add{
    type="control", id="fx_revmix", name="Reverb Mix",
    controlspec = ctrl(0, 1, 'lin', 0, 0.25),
    formatter = function(p) return string.format("%.2f", p:get()) end,
  }
  params:set_action("fx_revmix", function(v) ctx.set("fx_revmix", v) end)

  params:add{
    type="control", id="fx_revroom", name="Reverb Room",
    controlspec = ctrl(0, 1, 'lin', 0, 0.6),
    formatter = function(p) return string.format("%.2f", p:get()) end,
  }
  params:set_action("fx_revroom", function(v) ctx.set("fx_revroom", v) end)

  params:add{
    type="control", id="fx_revdamp", name="Reverb Damp",
    controlspec = ctrl(0, 1, 'lin', 0, 0.5),
    formatter = function(p) return string.format("%.2f", p:get()) end,
  }
  params:set_action("fx_revdamp", function(v) ctx.set("fx_revdamp", v) end)

  params:add{
    type="control", id="fx_cutoff", name="Filter Cutoff",
    controlspec = ctrl(20, 20000, 'exp', 0, 12000, "Hz"),
  }
  params:set_action("fx_cutoff", function(v) ctx.set("fx_cutoff", v) end)

  params:add{
    type="control", id="fx_reson", name="Filter Resonance",
    controlspec = ctrl(0.05, 0.99, 'lin', 0, 0.20),
    formatter = function(p) return string.format("%.2f", p:get()) end,
  }
  params:set_action("fx_reson", function(v) ctx.set("fx_reson", v) end)

  ----------------------------------------------------------------
  -- GROUP 3: LFO  (5 params)
  ----------------------------------------------------------------
  params:add_group("LFO", 5)

  params:add_option("lfo_on", "LFO On", {"off","on"}, 2)
  params:set_action("lfo_on", function(ix) ctx.set("lfo_on", ix) end)

  -- 1=Res, 2=Amp, 3=Pan (Pan does nothing unless engine exposes setPanRange)
  params:add_option("lfo_target", "LFO Target", {"Res","Amp","Pan"}, 1)
  params:set_action("lfo_target", function(ix) ctx.set("lfo_target", ix) end)

  params:add_option("lfo_wave", "LFO Wave", {"Sine","Tri","Saw","Square"}, 1)
  params:set_action("lfo_wave", function(ix) ctx.set("lfo_wave", ix) end)

  params:add{
    type="control", id="lfo_freq", name="LFO Freq",
    controlspec = ctrl(0, 40, 'lin', 0, 2.0, "Hz"),
    formatter = function(p) return string.format("%.1f Hz", p:get()) end,
  }
  params:set_action("lfo_freq", function(v) ctx.set("lfo_freq", v) end)

  params:add{
    type="control", id="lfo_depth", name="LFO Depth",
    controlspec = ctrl(0, 1, 'lin', 0, 0.20),
    formatter = function(p) return string.format("%.2f", p:get()) end,
  }
  params:set_action("lfo_depth", function(v) ctx.set("lfo_depth", v) end)

  ----------------------------------------------------------------
  -- GROUP 4: Beat 1  (8 params)
  ----------------------------------------------------------------
  params:add_group("Beat 1", 8)

  params:add_option("beat1_run", "Run", {"off","on"}, 1)
  params:set_action("beat1_run", function(ix)
    if ix == 2 and ctx.start_beat1 then ctx.start_beat1() end
    if ix == 1 and ctx.stop_beat1  then ctx.stop_beat1()  end
  end)

  params:add{
    type="control", id="beat1_steps", name="Steps",
    controlspec = ctrl(1, 32, 'lin', 1, 16),
  }
  params:set_action("beat1_steps", function(v) ctx.set("beat1_steps", v) end)

  params:add{
    type="control", id="beat1_fills", name="Fills",
    controlspec = ctrl(0, 32, 'lin', 1, 5),
  }
  params:set_action("beat1_fills", function(v) ctx.set("beat1_fills", v) end)

  params:add{
    type="control", id="beat1_rotate", name="Rotate",
    controlspec = ctrl(-64, 64, 'lin', 1, 0),
  }
  params:set_action("beat1_rotate", function(v) ctx.set("beat1_rotate", v) end)

  params:add_option("beat1_div_ix", "Division", {"1/1","1/2","1/4","1/8"}, 3)
  params:set_action("beat1_div_ix", function(ix) ctx.set("beat1_div_ix", ix) end)

  params:add{
    type="control", id="beat1_tune", name="Tune (Hz)",
    controlspec = ctrl(20, 120, 'lin', 1, 48, "Hz"),
  }
  params:set_action("beat1_tune", function(v) ctx.set("beat1_tune", v) end)

  params:add{
    type="control", id="beat1_decay", name="Decay",
    controlspec = ctrl(0.05, 2.0, 'lin', 0, 0.60, "s"),
    formatter = function(p) return string.format("%.2f s", p:get()) end,
  }
  params:set_action("beat1_decay", function(v) ctx.set("beat1_decay", v) end)

  params:add{
    type="control", id="beat1_amp", name="Amp",
    controlspec = ctrl(0, 1.5, 'lin', 0, 0.95),
    formatter = function(p) return string.format("%.2f", p:get()) end,
  }
  params:set_action("beat1_amp", function(v) ctx.set("beat1_amp", v) end)

  ----------------------------------------------------------------
  -- GROUP 5: Beat 2  (8 params)
  ----------------------------------------------------------------
  params:add_group("Beat 2", 8)

  params:add_option("beat2_run", "Run", {"off","on"}, 1)
  params:set_action("beat2_run", function(ix)
    if ix == 2 and ctx.start_beat2 then ctx.start_beat2() end
    if ix == 1 and ctx.stop_beat2  then ctx.stop_beat2()  end
  end)

  params:add{
    type="control", id="beat2_steps", name="Steps",
    controlspec = ctrl(1, 32, 'lin', 1, 16),
  }
  params:set_action("beat2_steps", function(v) ctx.set("beat2_steps", v) end)

  params:add{
    type="control", id="beat2_fills", name="Fills",
    controlspec = ctrl(0, 32, 'lin', 1, 8),
  }
  params:set_action("beat2_fills", function(v) ctx.set("beat2_fills", v) end)

  params:add{
    type="control", id="beat2_rotate", name="Rotate",
    controlspec = ctrl(-64, 64, 'lin', 1, 0),
  }
  params:set_action("beat2_rotate", function(v) ctx.set("beat2_rotate", v) end)

  params:add_option("beat2_div_ix", "Division", {"1/1","1/2","1/4","1/8"}, 3)
  params:set_action("beat2_div_ix", function(ix) ctx.set("beat2_div_ix", ix) end)

  params:add{
    type="control", id="beat2_tune", name="Tune (Hz)",
    controlspec = ctrl(20, 120, 'lin', 1, 55, "Hz"),
  }
  params:set_action("beat2_tune", function(v) ctx.set("beat2_tune", v) end)

  params:add{
    type="control", id="beat2_decay", name="Decay",
    controlspec = ctrl(0.05, 2.0, 'lin', 0, 0.45, "s"),
    formatter = function(p) return string.format("%.2f s", p:get()) end,
  }
  params:set_action("beat2_decay", function(v) ctx.set("beat2_decay", v) end)

  params:add{
    type="control", id="beat2_amp", name="Amp",
    controlspec = ctrl(0, 1.5, 'lin', 0, 0.85),
    formatter = function(p) return string.format("%.2f", p:get()) end,
  }
  params:set_action("beat2_amp", function(v) ctx.set("beat2_amp", v) end)

  ----------------------------------------------------------------
  -- GROUP 6: Mix Page (bars)  (2 params)
  ----------------------------------------------------------------
  params:add_group("Mix Page", 2)

  params:add{
    type="control", id="Amix", name="A Mix",
    controlspec = ctrl(0, 1.5, 'lin', 0, (ctx.drones_settings and ctx.drones_settings[1] and ctx.drones_settings[1].mix) or 0.7),
    formatter = function(p) return string.format("%.2f", p:get()) end,
  }
  params:set_action("Amix", function(v)
    if ctx.drones_settings and ctx.drones_settings[1] then
      ctx.drones_settings[1].mix = v
    end
    if ctx.apply_drone_mix then ctx.apply_drone_mix(1) end
    if ctx.redraw then ctx.redraw() end
  end)

  params:add{
    type="control", id="Bmix", name="B Mix",
    controlspec = ctrl(0, 1.5, 'lin', 0, (ctx.drones_settings and ctx.drones_settings[2] and ctx.drones_settings[2].mix) or 0.7),
    formatter = function(p) return string.format("%.2f", p:get()) end,
  }
  params:set_action("Bmix", function(v)
    if ctx.drones_settings and ctx.drones_settings[2] then
      ctx.drones_settings[2].mix = v
    end
    if ctx.apply_drone_mix then ctx.apply_drone_mix(2) end
    if ctx.redraw then ctx.redraw() end
  end)

  
end
return Params
