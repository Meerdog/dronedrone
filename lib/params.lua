-- lib/params.lua
-- Sequential, non-nested groups with exact counts.
-- Wires every param to the host script via ctx.set(key, value).

local cs = require "controlspec"

local Params = {}

local function ctrl(min, max, warp, step, default, units)
  return cs.new(min, max, warp, step or 0, default, units)
end

function Params.setup(ctx)
  params:clear()

  ----------------------------------------------------------
  -- Demo Presets
  ----------------------------------------------------------

  local util = require "util"

  -- ---------- Demo preset helpers ----------
  local function _snapshot_params()
    local snap = {}
    for i = 1, params.count do
      snap[i] = params:get(i)
    end
    return snap
  end

  local function _restore_params(snap)
    for i = 1, params.count do
      if snap[i] ~= nil then params:set(i, snap[i]) end
    end
  end

  local function _set(id, v)
    -- Safe setter by id string (uses params.lookup)
    if params.lookup and params.lookup[id] then
      params:set(params.lookup[id], v)
    end
  end

  local function _paths()
    local base = norns.state.data
    util.make_dir(base)
    return {
      flag       = base .. "presets_installed.flag",
      lfo_reso   = base .. "preset_lfo_reso.pset",
      lfo_pan    = base .. "preset_lfo_pan.pset",
      beats_dual = base .. "preset_beats_dual.pset",
    }
  end

  local function _write_pset(path)
    util.make_dir(norns.state.data)
    params:write(path)
    print("wrote preset → " .. path)
  end

  local function install_demo_presets_once()
    local p = _paths()
    if util.file_exists(p.flag) then
      print("demo presets already installed")
      return
    end

    local snap = _snapshot_params()

    ----------------------------------------------------------
    -- Preset 1: "lfo_reso_demo"  (obvious resonant wobble)
    ----------------------------------------------------------
    _set("beat1_run", 1); _set("beat2_run", 1)  -- keep beats off
    _set("lfo_on", 2)         -- on
    _set("lfo_target", 1)     -- Res
    _set("lfo_wave", 1)       -- Sine
    _set("lfo_freq", 0.4)
    _set("lfo_depth", 0.85)
    _set("fx_cutoff", 2500)
    _set("fx_reson", 0.45)
    _set("sub_level", 0.0)
    _write_pset(p.lfo_reso)

    ----------------------------------------------------------
    -- Preset 2: "lfo_pan_demo"  (clear left/right sweep)
    ----------------------------------------------------------
    _set("lfo_on", 2)
    _set("lfo_target", 3)   -- Pan (requires engine.setPanRange)
    _set("lfo_wave", 2)     -- Tri
    _set("lfo_freq", 0.25)
    _set("lfo_depth", 1.00)
    _set("Amix", 1.0); _set("Bmix", 1.0)
    _set("fx_cutoff", 6000)
    _set("fx_reson", 0.20)
    _set("sub_level", 0.25)
    _write_pset(p.lfo_pan)

    ----------------------------------------------------------
    -- Preset 3: "beats_dual_demo"  (two contrasting Euclids)
    ----------------------------------------------------------
    _set("lfo_on", 1)
    -- Beat 1
    _set("beat1_steps", 16); _set("beat1_fills", 5); _set("beat1_rotate", 0)
    _set("beat1_div", 3)     -- 1/4
    _set("beat1_tune", 48); _set("beat1_decay", 0.60); _set("beat1_amp", 0.95)
    _set("beat1_run", 1)
    -- Beat 2
    _set("beat2_steps", 16); _set("beat2_fills", 9); _set("beat2_rotate", 0)
    _set("beat2_div", 4)     -- 1/8
    _set("beat2_tune", 55); _set("beat2_decay", 0.45); _set("beat2_amp", 0.85)
    _set("beat2_run", 1)
    _write_pset(p.beats_dual)

    _restore_params(snap)

    local f = io.open(p.flag, "w"); if f then f:write("ok"); f:close() end
    print("demo presets installed (once)")
  end

  local function load_demo_preset(choice_index)
    -- choice_index: 1 = "—", 2 = LFO Reso, 3 = LFO Pan, 4 = Beats Dual
    local p = _paths()
    local map = { [2]=p.lfo_reso, [3]=p.lfo_pan, [4]=p.beats_dual }
    local file = map[choice_index]
    if not file then return end

    local ok, err = pcall(function()
      params:read(file)
      params:bang()
    end)
    if not ok then print("load preset failed: " .. (err or "?")) end
  end

  ----------------------------------------------------------------
  -- GROUP 0: DEMO PRESETS  (5 params)
  ----------------------------------------------------------------
  params:add_group("DEMO PRESETS", 5)

  -- 1) Write demo .pset files into dust/data/dronedrone (once)
  params:add_trigger("preset_install", "Install demo presets")
  params:set_action("preset_install", function()
    install_demo_presets_once()
  end)

  -- 2) Load one of the demo presets (dropdown)
  params:add_option(
    "preset_load",
    "Load demo (picker)",
    {"—","LFO Reso (demo)","LFO Pan (demo)","Beats Dual (demo)"},
    1
  )
  params:set_action("preset_load", function(v)
    if v > 1 then
      load_demo_preset(v)
      -- return selector to "—" so it doesn’t re-load on save
      params:set("preset_load", 1)
    end
  end)

  -- 3) One-tap triggers (do the same loads as above)
  params:add_trigger("preset_load_reso", "Load: LFO Reso (demo)")
  params:set_action("preset_load_reso", function() load_demo_preset(2) end)

  params:add_trigger("preset_load_pan", "Load: LFO Pan (demo)")
  params:set_action("preset_load_pan", function() load_demo_preset(3) end)

  params:add_trigger("preset_load_beats", "Load: Beats Dual (demo)")
  params:set_action("preset_load_beats", function() load_demo_preset(4) end)

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
