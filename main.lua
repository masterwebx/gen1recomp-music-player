-- Music Player: SELECT + A opens a song list (in-game Font / ListMenu).
-- START toggles favorites. SELECT + START plays favorites in a loop
-- (one-shot each track, then next). SELECT in the list restores map music.
-- While a custom track is locked, a now-playing chip sits bottom-left.

local mod = ...

local ListMenu = require("src.ui.ListMenu")
local Music = require("src.core.Music")
local Font = require("src.render.Font")
local Strings = require("src.core.Strings")
local Sound = require("src.core.Sound")

local lockedSong = nil
local vizClock = 0
local favorites = {}       -- songId -> true
local favoritesMode = false
local favAdvancing = false -- re-entrancy guard while swapping tracks
local audioState = nil     -- Music.lua's private state table (captured below)

local playFavoriteTrack, advanceFavorite

local function loadFavorites()
  favorites = {}
  local stored = mod.save:get("favorites", nil)
  if type(stored) ~= "table" then return end
  for k, v in pairs(stored) do
    if type(k) == "string" and v then
      favorites[k] = true
    elseif type(v) == "string" then
      favorites[v] = true
    end
  end
end

local function saveFavorites()
  local list = {}
  for id in pairs(favorites) do list[#list + 1] = id end
  table.sort(list)
  mod.save:set("favorites", list)
end

loadFavorites()

local function prettyLabel(id)
  local s = tostring(id or "")
  s = s:gsub("^Music_", "")
  s = s:gsub("([a-z])([A-Z])", "%1 %2")
  s = s:gsub("([A-Za-z])([0-9])", "%1 %2")
  s = s:gsub("([0-9])([A-Za-z])", "%1 %2")
  s = s:gsub("_", " ")
  s = s:gsub("%s+", " ")
  s = s:upper()
  return s
end

local function fitLabel(text, maxPx)
  maxPx = maxPx or (14 * 8)
  if Font.width(text) <= maxPx then return text end
  local s = text
  while #s > 1 and Font.width(s .. ".") > maxPx do
    s = s:sub(1, #s - 1)
  end
  return s .. "."
end

local function songTempo(id)
  local h = 0
  for i = 1, #id do h = (h * 33 + id:byte(i)) % 997 end
  return 96 + (h % 64)
end

local function collectSongs(data)
  local songs = data and data.audio and data.audio.songs
  local ids = {}
  if type(songs) == "table" then
    for id in pairs(songs) do
      if type(id) == "string" then ids[#ids + 1] = id end
    end
  end
  table.sort(ids, function(a, b)
    return prettyLabel(a) < prettyLabel(b)
  end)
  return ids
end

local function favoriteList(data)
  local all = collectSongs(data)
  local out = {}
  for _, id in ipairs(all) do
    if favorites[id] then out[#out + 1] = id end
  end
  return out
end

local function playSong(game, songId)
  if not songId then return end
  favoritesMode = false
  lockedSong = songId
  vizClock = 0
  Music.play(game.data, songId, true, { reason = "music_player" })
end

local function restoreMap(game)
  lockedSong = nil
  favoritesMode = false
  local ow = game.overworld
  if ow and ow.map then
    Music.playMap(game.data, ow.map.id, game.save and game.save.onBike,
                  ow.player and ow.player.surfing)
  else
    Music.restoreMap(game.data)
  end
end

-- Favorites use Music.playOnce so the engine arms pendingRestore and calls
-- Music.restoreMap when the track ends - that is the reliable end signal.
playFavoriteTrack = function(game, songId, skips)
  if not songId or not game or not game.data then return end
  skips = skips or 0
  favoritesMode = true
  lockedSong = songId
  vizClock = 0
  -- stop first so a one-song playlist can re-trigger the same id
  Music.stop()
  if not Music.playOnce(game.data, songId) then
    -- Def failed; skip ahead (cap so a bad set cannot infinite-loop).
    if skips >= 32 then
      favoritesMode = false
      restoreMap(game)
      return
    end
    local list = favoriteList(game.data)
    if #list == 0 then
      favoritesMode = false
      restoreMap(game)
      return
    end
    local idx = 1
    for i, id in ipairs(list) do
      if id == songId then idx = i + 1; break end
    end
    if idx > #list then idx = 1 end
    if list[idx] == songId then
      favoritesMode = false
      restoreMap(game)
      return
    end
    playFavoriteTrack(game, list[idx], skips + 1)
  end
end

advanceFavorite = function(game)
  if not game or not game.data then return end
  local list = favoriteList(game.data)
  if #list == 0 then
    favoritesMode = false
    restoreMap(game)
    return
  end
  local idx = 1
  for i, id in ipairs(list) do
    if id == lockedSong then
      idx = i + 1
      break
    end
  end
  if idx > #list then idx = 1 end
  playFavoriteTrack(game, list[idx])
end

local function startFavorites(game)
  local list = favoriteList(game.data)
  if #list == 0 then
    Sound.play(game.data, "Denied")
    return
  end
  local startId = list[1]
  if lockedSong then
    for _, id in ipairs(list) do
      if id == lockedSong then
        startId = id
        break
      end
    end
  end
  Sound.play(game.data, "Start_Menu")
  playFavoriteTrack(game, startId)
end

local function toggleFavorite(songId)
  if not songId then return false end
  if favorites[songId] then
    favorites[songId] = nil
  else
    favorites[songId] = true
  end
  saveFavorites()
  return favorites[songId] and true or false
end

local function itemRight(songId)
  local fav = favorites[songId]
  local playing = lockedSong == songId
  if fav and playing then return "*F" end
  if fav then return "F" end
  if playing then return "*" end
  return nil
end

local function refreshItems(items)
  for _, it in ipairs(items) do
    if type(it.value) == "string" then
      it.label = fitLabel(prettyLabel(it.value), 13 * 8)
      it.right = itemRight(it.value)
    end
  end
end

local function openPlayer(game)
  local ids = collectSongs(game.data)
  local items = {}
  for _, id in ipairs(ids) do
    items[#items + 1] = { label = fitLabel(prettyLabel(id), 13 * 8), value = id }
  end
  refreshItems(items)

  local menu = ListMenu.new(game, Strings("MUSIC"), items, {
    kind = "MusicPlayer",
    rows = 6,
    wrap = true,
    pageJump = true,
    keyRepeat = true,
    footer = Strings("A PLAY  START FAV  SEL MAP  B BACK"),
    onSelectKey = function()
      restoreMap(game)
      refreshItems(items)
    end,
    onChoose = function(item)
      if item and item.value then
        playSong(game, item.value)
        refreshItems(items)
      end
    end,
    onCancel = function() end,
  })
  menu._musicPlayer = true
  menu._musicPlayerItems = items
  if lockedSong then
    for i, it in ipairs(items) do
      if it.value == lockedSong then
        menu.index = i
        break
      end
    end
  end
  game.stack:push(menu)
end

mod.hooks:wrap("music.select", function(next, song, ctx)
  ctx = ctx or {}
  if lockedSong and ctx.reason == "map" then
    return lockedSong
  end
  return next(song, ctx)
end)

-- Favorites playlist: playOnce arms pendingRestore; when the track ends the
-- engine calls restoreMap. Intercept that to queue the next favorite instead
-- of bringing map music back (and instead of relying on Source:isPlaying).
do
  local function unwrapMusicFn(fn, upName)
    while type(fn) == "function" do
      local info = debug.getinfo(fn, "S")
      local src = info and info.source or ""
      if not src:find("MusicPlayer", 1, true) then break end
      local inner
      for i = 1, 8 do
        local name, val = debug.getupvalue(fn, i)
        if name == upName and type(val) == "function" then
          inner = val
          break
        end
      end
      if not inner then break end
      fn = inner
    end
    return fn
  end

  local function captureAudioState()
    if audioState then return end
    for _, fn in ipairs({
      Music.playOnce, Music.play, Music.stop, Music.update, Music.restoreMap,
    }) do
      local f = fn
      if type(f) == "function" then
        for i = 1, 32 do
          local name, val = debug.getupvalue(f, i)
          if name == "state" and type(val) == "table" then
            audioState = val
            return
          end
        end
      end
    end
  end
  captureAudioState()

  local baseRestore = unwrapMusicFn(Music.restoreMap, "baseRestore")
  function Music.restoreMap(data)
    if favoritesMode and lockedSong and not favAdvancing then
      captureAudioState()
      local ended = audioState and audioState.current
      local Game = require("src.core.Game")
      -- playOnce finished: current is still our track (or already cleared).
      -- Only treat a *different* current label as an interrupt (heal jingle).
      if ended == nil or ended == lockedSong then
        favAdvancing = true
        advanceFavorite(Game)
        favAdvancing = false
        return
      end
      playFavoriteTrack(Game, lockedSong)
      return
    end
    return baseRestore(data)
  end
end

-- Scissor in canvas pixels even when the caller has scale()/translate().
local function scissorTransformed(x, y, w, h)
  local x1, y1, x2, y2
  if love.graphics.transformPoint then
    x1, y1 = love.graphics.transformPoint(x, y)
    x2, y2 = love.graphics.transformPoint(x + w, y + h)
  else
    local t = love.graphics.getTransform and love.graphics.getTransform()
    if t then
      x1, y1 = t:transformPoint(x, y)
      x2, y2 = t:transformPoint(x + w, y + h)
    else
      x1, y1, x2, y2 = x, y, x + w, y + h
    end
  end
  local sx = math.floor(math.min(x1, x2) + 0.5)
  local sy = math.floor(math.min(y1, y2) + 0.5)
  local sw = math.max(1, math.ceil(math.abs(x2 - x1)))
  local sh = math.max(1, math.ceil(math.abs(y2 - y1)))
  local prev = { love.graphics.getScissor() }
  love.graphics.setScissor(sx, sy, sw, sh)
  return prev
end

local function restoreScissor(prev)
  if prev and prev[1] then
    love.graphics.setScissor(prev[1], prev[2], prev[3], prev[4])
  else
    love.graphics.setScissor()
  end
end

-- Never love.graphics.scale(0.5) on Font - fractional scale shreds NN glyphs.
-- Long titles scroll like a radio billboard instead of being abbreviated.
local function drawNowPlayingChip(originX, originY)
  local name = prettyLabel(lockedSong)
  local tempo = songTempo(lockedSong)
  local beat = (vizClock * tempo / 3600) % 1
  local pulse = math.sin(beat * math.pi * 2)
  if pulse < 0 then pulse = 0 end

  local viewW = 12 * 8
  local bars = 5
  local barAreaW = bars * 4 - 1
  local boxW = math.max(viewW, barAreaW) + 4
  local boxH = 8 + 2 + 10
  local textX = originX + 2
  local textY = originY + 1

  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.rectangle("fill", originX, originY, boxW, boxH)
  love.graphics.setColor(0, 0, 0, 1)
  love.graphics.rectangle("line", originX, originY, boxW, boxH)

  love.graphics.setColor(1, 1, 1, 1)
  local textW = Font.width(name)
  if textW <= viewW then
    Font.draw(name, textX, textY)
  else
    -- Hold, then scroll, with a gap before the name repeats.
    local sep = "   "
    local loopW = textW + Font.width(sep)
    local hold = 90
    local pxPerFrame = 1 / 3
    local scrollSpan = loopW / pxPerFrame
    local phase = vizClock % (hold + scrollSpan)
    local scroll = 0
    if phase >= hold then
      scroll = math.floor((phase - hold) * pxPerFrame)
    end
    local prev = scissorTransformed(textX, textY, viewW, 8)
    Font.draw(name, textX - scroll, textY)
    Font.draw(name, textX - scroll + loopW, textY)
    restoreScissor(prev)
  end

  love.graphics.setColor(0, 0, 0, 1)
  local baseY = originY + boxH - 2
  for i = 1, bars do
    local phase = beat + (i - 1) * 0.17
    local h = 2 + math.floor(
      (0.35 + 0.65 * math.abs(math.sin(phase * math.pi * 2))) * 8)
    if i == 3 then h = math.max(h, 2 + math.floor(pulse * 10)) end
    love.graphics.rectangle("fill",
      originX + 2 + (i - 1) * 4, baseY - h, 3, h)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

local function shouldShowHud()
  if not lockedSong then return false end
  local Game = require("src.core.Game")
  local ow = Game.overworld
  if not ow then return false end
  if Game.stack and Game.stack:top() ~= ow then return false end
  return true
end

do
  local baseListUpdate = ListMenu.update
  if not ListMenu._musicPlayerStartKey then
    ListMenu._musicPlayerStartKey = true
  end
  -- Always rebind so START-fav works after hot reload.
  local prevList = ListMenu._musicPlayerListBase
  if not prevList then
    local info = debug.getinfo(ListMenu.update, "S")
    local src = info and info.source or ""
    if src:find("MusicPlayer", 1, true) then
      for i = 1, 8 do
        local name, val = debug.getupvalue(ListMenu.update, i)
        if name == "baseListUpdate" and type(val) == "function" then
          prevList = val
          break
        end
      end
    end
    prevList = prevList or ListMenu.update
    ListMenu._musicPlayerListBase = prevList
  end
  function ListMenu:update(dt)
    if self._musicPlayer and not self.script then
      local input = self.game.input
      if input:wasPressed("start") then
        local item = self.items[self.index]
        if item and item.value then
          toggleFavorite(item.value)
          Sound.play(self.game.data, "Press_AB")
          refreshItems(self._musicPlayerItems or self.items)
        end
        return
      end
    end
    return ListMenu._musicPlayerListBase(self, dt)
  end
end

do
  local OverworldState = require("src.world.OverworldController")
  -- Always rebind hotkeys so SELECT+START is picked up after reload.
  local baseInput = OverworldState._musicPlayerInputBase
  if not baseInput then
    local info = debug.getinfo(OverworldState.handleInput, "S")
    local src = info and info.source or ""
    if src:find("MusicPlayer", 1, true) then
      for i = 1, 8 do
        local name, val = debug.getupvalue(OverworldState.handleInput, i)
        if name == "baseInput" and type(val) == "function" then
          baseInput = val
          break
        end
      end
    end
    baseInput = baseInput or OverworldState.handleInput
    OverworldState._musicPlayerInputBase = baseInput
  end
  OverworldState._musicPlayerHotkey = true
  function OverworldState:handleInput()
    local Game = require("src.core.Game")
    local input = Game and Game.input
    if input and not self.player.moving and input:isDown("select") then
      if input:wasPressed("start") then
        startFavorites(Game)
        return
      end
      if input:wasPressed("a") then
        Sound.play(Game.data, "Start_Menu")
        openPlayer(Game)
        return
      end
    end
    return OverworldState._musicPlayerInputBase(self)
  end

  if not OverworldState._musicPlayerHudClock then
    OverworldState._musicPlayerHudClock = true
    local baseUpdate = OverworldState.update
    function OverworldState:update(dt)
      if lockedSong then vizClock = vizClock + 1 end
      return baseUpdate(self, dt)
    end
  end

  local function unwrapMusicDrawUI(fn)
    while type(fn) == "function" do
      local info = debug.getinfo(fn, "S")
      local src = info and info.source or ""
      if not src:find("MusicPlayer", 1, true) then break end
      local inner
      for i = 1, 8 do
        local name, val = debug.getupvalue(fn, i)
        if not name then break end
        if (name == "baseUI" or name == "base") and type(val) == "function" then
          inner = val
          break
        end
      end
      if not inner then break end
      fn = inner
    end
    return fn
  end

  OverworldState._musicPlayerHudBaseUI =
    unwrapMusicDrawUI(OverworldState.drawUI)
  OverworldState._musicPlayerHudV2 = true
  OverworldState._musicPlayerHudV3 = true
  function OverworldState:drawUI()
    OverworldState._musicPlayerHudBaseUI(self)
    if not shouldShowHud() then return end
    local Game = require("src.core.Game")
    if Game.renderer and Game.renderer.worldOverride then
      return
    end
    drawNowPlayingChip(1, 144 - 22)
  end
end

do
  local Renderer = require("src.render.Renderer")
  local prevEnd = Renderer._musicPlayerEndFrameBase or Renderer.endFrame
  do
    local info = debug.getinfo(Renderer.endFrame, "S")
    local src = info and info.source or ""
    if src:find("MusicPlayer", 1, true) then
      for i = 1, 8 do
        local name, val = debug.getupvalue(Renderer.endFrame, i)
        if name == "baseEnd" and type(val) == "function" then
          prevEnd = val
          break
        end
      end
    end
  end
  Renderer._musicPlayerEndFrameBase = prevEnd
  Renderer._musicPlayerHudV3 = true
  Renderer._musicPlayerHudEndWrap = true
  function Renderer:endFrame(zones, worldZones)
    if shouldShowHud() and self.worldOverride and self.worldOverride.getHeight then
      local world = self.worldOverride
      local prev = love.graphics.getCanvas()
      pcall(function()
        love.graphics.setCanvas(world)
        love.graphics.push()
        love.graphics.origin()
        local scale = 2
        local chipH = 20
        love.graphics.translate(6, world:getHeight() - chipH * scale - 6)
        love.graphics.scale(scale, scale)
        drawNowPlayingChip(0, 0)
        love.graphics.pop()
      end)
      if prev then love.graphics.setCanvas(prev) else love.graphics.setCanvas() end
    end
    return Renderer._musicPlayerEndFrameBase(self, zones, worldZones)
  end
end

mod.events:on("save.loaded", function()
  lockedSong = nil
  favoritesMode = false
  favAdvancing = false
  vizClock = 0
  loadFavorites()
end)

-- Hide catalog/manifest "GH …" detail rows (overlap footer on short screens).
mod.events:once("mods.loaded", function()
  local ok, ManagerState = pcall(require, "src.mods.ManagerState")
  if not ok or not ManagerState or ManagerState._ghDetailRowsHidden then return end
  local orig = ManagerState.detailRows
  if type(orig) ~= "function" then return end
  function ManagerState:detailRows(m)
    local rows = orig(self, m) or {}
    local out = {}
    for _, r in ipairs(rows) do
      local lab = tostring(r.label or "")
      if not lab:match("^[Gg][Hh]%s") and lab ~= "GH" then
        out[#out + 1] = r
      end
    end
    return out
  end
  ManagerState._ghDetailRowsHidden = true
end)

mod.exports.lockedSong = function() return lockedSong end
mod.exports.favoritesMode = function() return favoritesMode end
mod.log:info("music player ready (SELECT+A; START fav; SELECT+START queue)")
