-- lib/lpmini.lua — Launchpad Mini mk3 RGB driver (Programmer Mode)
-- Top-left origin selectable. Clean note<->XY mapping for mk3.
-- Dependencies: norns 'midi' library.

local midi = require "midi"

local LPMini = {}

-- Change this if your port name is different. (See SYSTEM > DEVICES)
local DEVNAME_HINT = "LPMiniMK3"

-- Set to true if (1,1) is the top-left pad. Flip if your grid looks upside-down.
local ORIGIN_TOP_LEFT = true

-- Internal
local dev = nil

-- ───────────────────────────── helpers ─────────────────────────────

local function sysex(bytes)
  if dev then dev:send(bytes) end
end

-- LP Mini mk3 grid uses note numbers 11..18 (row 1), 21..28 (row 2), ... 81..88.
-- We use 1-based x,y in [1..8], return MIDI note.
local function note_for(x, y)
  local yy = ORIGIN_TOP_LEFT and y or (9 - y)
  return (yy * 10) + x
end

-- Inverse: MIDI note -> (x,y) in [1..8]
local function xy_from_note(n)
  local raw_y = math.floor(n / 10)
  local x     = n % 10
  local y     = ORIGIN_TOP_LEFT and raw_y or (9 - raw_y)
  return x, y
end

-- ───────────────────────────── setup/teardown ─────────────────────────────

function LPMini.setup()
  -- find first matching device
  for id = 1, 16 do
    local m = midi.connect(id)
    if m and m.name and string.find(m.name, DEVNAME_HINT) then
      dev = m
      break
    end
  end
  if not dev then
    print("lpmini: device not found by name; falling back to MIDI 1")
    dev = midi.connect(1)
  end

  -- Enter Programmer Mode (mk3 Mini: device id 0x0D)
  sysex{0xF0,0x00,0x20,0x29,0x02,0x0D,0x0E,0x01,0xF7}

  -- MIDI input -> button callback
  dev.event = function(data)
    if not LPMini.on_press then return end
    local msg = midi.to_msg(data)
    if msg.type == "note_on" or msg.type == "note_off" then
      local x, y = xy_from_note(msg.note)
      if x >= 1 and x <= 8 and y >= 1 and y <= 8 then
        local z = (msg.type == "note_on" and msg.vel > 0) and 1 or 0
        LPMini.on_press(x, y, z)
      end
    end
  end
end

function LPMini.cleanup()
  if dev then
    -- Exit Programmer Mode
    sysex{0xF0,0x00,0x20,0x29,0x02,0x0D,0x0E,0x00,0xF7}
    dev:close()
    dev = nil
  end
end

-- ───────────────────────────── public API ─────────────────────────────

-- Call this once from grid.lua if your grid appears upside-down.
function LPMini.set_origin_top(is_top)
  ORIGIN_TOP_LEFT = (is_top ~= false)
end

-- Fast device clear (all pads off)
function LPMini.clear()
  -- mk3: "Set All Pads" SysEx (0x14) with 0 = off
  sysex{0xF0,0x00,0x20,0x29,0x02,0x0D,0x14,0x00,0xF7}
end

-- Set one pad to an RGB color (0..63 per channel on mk3)
function LPMini.led_rgb(x, y, r, g, b)
  local n = note_for(x, y)
  -- SysEx: Set LED RGB by Note
  sysex{0xF0,0x00,0x20,0x29,0x02,0x0D,0x03, n, r, g, b, 0xF7}
end

-- Palette index variant (0..127). Use if you prefer indexed colors.
function LPMini.led_idx(x, y, idx)
  local n = note_for(x, y)
  if dev then dev:note_on(n, idx, 1) end
end

-- Optional: simple LED test for orientation
function LPMini.test_corners()
  LPMini.clear()
  LPMini.led_rgb(1,1, 63,0,0)   -- red
  LPMini.led_rgb(8,1, 0,63,0)   -- green
  LPMini.led_rgb(1,8, 0,0,63)   -- blue
  LPMini.led_rgb(8,8, 63,63,0)  -- yellow
end

-- caller injects: LPMini.on_press = function(x,y,z) ... end

return LPMini
