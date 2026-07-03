--------------------------------------------------------------------------
-- src/audio/sfx.lua
-- Event-name -> file mapping so audio assets can be swapped without code
-- changes. Ships silent-safe: any missing file just logs once and no-ops.
-- Layering: dice rattle -> land -> win chime; the "streak riser" pitches
-- up with the win streak; music ducks during near-miss slow-mo.
--------------------------------------------------------------------------

local sfx = {}

-- Drop .ogg files with these names into assets/sfx to bring events alive.
local eventFiles = {
  dice_rattle  = "assets/sfx/dice_rattle.ogg",
  dice_land    = "assets/sfx/dice_land.ogg",
  win_chime    = "assets/sfx/win_chime.ogg",
  lose_thud    = "assets/sfx/lose_thud.ogg",
  chip_place   = "assets/sfx/chip_place.ogg",
  chip_slide   = "assets/sfx/chip_slide.ogg",
  streak_riser = "assets/sfx/streak_riser.ogg",
  jackpot      = "assets/sfx/jackpot_fanfare.ogg",
  unlock       = "assets/sfx/unlock_reveal.ogg",
  ui_click     = "assets/sfx/ui_click.ogg",
  near_miss    = "assets/sfx/near_miss_whoosh.ogg",
}
local MUSIC_FILE = "assets/music/casino_ambience.ogg"

local sources = {}
local missing = {}
local music = nil
local musicVol, sfxVol = 0.7, 1.0
local duckLevel, duckTime = 1, 0

function sfx.load(settings)
  if settings then
    musicVol = settings.musicVol or musicVol
    sfxVol = settings.sfxVol or sfxVol
  end
  for name, path in pairs(eventFiles) do
    if love.filesystem.getInfo(path) then
      sources[name] = love.audio.newSource(path, "static")
    end
  end
  if love.filesystem.getInfo(MUSIC_FILE) then
    music = love.audio.newSource(MUSIC_FILE, "stream")
    music:setLooping(true)
    music:setVolume(musicVol)
    music:play()
  end
end

--- Play an event. opts = { pitch, volume }.
function sfx.play(name, opts)
  local src = sources[name]
  if not src then
    if not missing[name] then
      missing[name] = true
      print("[sfx] no asset for '" .. name .. "' (drop one in assets/sfx)")
    end
    return
  end
  opts = opts or {}
  local inst = src:clone() -- allow overlapping plays (layering)
  inst:setPitch(opts.pitch or 1)
  inst:setVolume((opts.volume or 1) * sfxVol)
  inst:play()
end

--- The streak riser: pitch climbs with the win streak.
function sfx.streakRiser(streak)
  sfx.play("streak_riser", { pitch = math.min(2, 1 + streak * 0.08) })
end

--- Duck the music bed (near-miss slow-mo). Recovers over `dur` seconds.
function sfx.duck(dur)
  duckLevel = 0.25
  duckTime = dur or 1.0
  sfx.play("near_miss", { volume = 0.8 })
end

function sfx.setVolumes(musicV, sfxV)
  musicVol, sfxVol = musicV, sfxV
  if music then music:setVolume(musicVol * duckLevel) end
end

function sfx.update(dt)
  if duckTime > 0 then
    duckTime = duckTime - dt
    if duckTime <= 0 then duckLevel = 1 end
  else
    duckLevel = math.min(1, duckLevel + dt * 2)
  end
  if music then music:setVolume(musicVol * duckLevel) end
end

return sfx
