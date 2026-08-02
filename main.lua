-- The badge boost glitch is the most defining mechanic in Generation 1 and
-- sadly one of the few things not present in the Gen 1 recomp. Here's a
-- rundown of what it does:
--
-- Badge Boost Glitch:
-- - In Gen I, the 1st, 3rd, 5th, and 7th badges (Brock, Lt. Surge, Koga,
--   and Blaine) each give a 12.5% in-battle boost to one stat.
-- - Whenever one of your Pokemon's stats is successfully raised or lowered
--   in battle, the game accidentally reapplies those badge boosts.
-- - This can happen when an opponent uses Growl, Leer, or Tail Whip, or when
--   you use moves like Defense Curl, Agility, or Swords Dance.
-- - The stat that was directly changed is recalculated normally. However,
--   every other badge-boosted stat gets another 12.5% boost.
-- - For example, if you use Defense Curl, your Defense rises normally, but
--   your badge-boosted Attack, Speed, and Special can each get an extra
--   12.5% boost.
-- - These extra boosts stack each time a stat is changed, up to the game's
--   stat cap.
-- - A stat loses its stacked extra boosts when that same stat is recalculated,
--   such as when its stat stage changes, when the Pokemon levels up, switches
--   out, or when the battle ends.
--
-- More detail: https://www.dragonflycave.com/mechanics/gen-i-stat-modification/

return function(mod)
  local function req(p) local ok, m = pcall(require, p); return ok and m or nil end

  -- Keep state when the mod is reloaded.
  local C = _G.__KANTO_BADGE_GLITCH or {}
  _G.__KANTO_BADGE_GLITCH = C

  C.game = C.game or req("src.core.Game")
  C.BattleState = C.BattleState or req("src.battle.BattleState")
  C.Stats = C.Stats or req("src.pokemon.Stats")
  C.Damage = C.Damage or req("src.battle.Damage")
  mod.events:on("game.ready", function(ev) C.game = (ev and ev.game) or C.game end)

  local function currentBattle()
    local g = C.game; local stk = g and g.stack
    if not (stk and stk.states and C.BattleState) then return nil end
    for i = #stk.states, 1, -1 do
      if getmetatable(stk.states[i]) == C.BattleState then return stk.states[i] end
    end
    return nil
  end

  local GLITCH_STATS = { "attack", "defense", "speed", "special" }

  local function clamp(v) return math.max(1, math.min(999, v)) end

  -- Find the badge boost for a stat.
  local function badgeBoostRow(battler, stat)
    local badges = battler.badges
    if not badges then return nil end
    local rows = battler.badgeBoosts or (C.Damage and C.Damage.BADGE_BOOSTS) or {}
    for _, row in ipairs(rows) do
      if row.stat == stat and badges[row.badge] then return row end
    end
    return nil
  end

  local function freshValue(battler, stat, baseVal)
    local stage = battler.stages and battler.stages[stat] or 0
    local v = C.Stats.applyStage(baseVal, stage)
    local row = badgeBoostRow(battler, stat)
    if row then v = math.floor(v * (row.num or 9) / (row.den or 8)) end
    return clamp(v)
  end

  -- Track each battler only for the current battle.
  local tracked = setmetatable({}, { __mode = "k" })
  local lastLevel = setmetatable({}, { __mode = "k" })

  local function ensureTracked(battler)
    local st = tracked[battler]
    -- Start over for a switch, Haze, or any engine reset.
    if st and st.mon == battler.mon and battler.curStats == st.copy then
      return st
    end
    local base = {}
    for _, k in ipairs(GLITCH_STATS) do base[k] = battler.mon.stats[k] end
    local copy = {}
    for k, v in pairs(battler.mon.stats) do copy[k] = v end
    if battler.curStats then
      for k, v in pairs(battler.curStats) do copy[k] = v end
    end
    -- Apply the normal badge boost when the Pokemon enters battle.
    for _, k in ipairs(GLITCH_STATS) do
      copy[k] = freshValue(battler, k, base[k])
    end
    battler.curStats = copy
    local lastStages = {}
    for _, k in ipairs(GLITCH_STATS) do lastStages[k] = battler.stages and battler.stages[k] or 0 end
    st = { mon = battler.mon, base = base, copy = copy, lastStages = lastStages }
    tracked[battler] = st
    return st
  end

  local function pollBattler(battler)
    if not (battler and battler.mon and battler.mon.stats) then return end
    if lastLevel[battler.mon] ~= battler.mon.level then
      lastLevel[battler.mon] = battler.mon.level
      tracked[battler] = nil   -- Leveling up clears the extra boosts.
    end
    local st = ensureTracked(battler)
    local stages = battler.stages or {}
    local changed = {}
    local anyChanged = false
    for _, k in ipairs(GLITCH_STATS) do
      local cur = stages[k] or 0
      if cur ~= st.lastStages[k] then
        changed[k] = true; anyChanged = true; st.lastStages[k] = cur
      end
    end
    if not anyChanged then return end
    for _, k in ipairs(GLITCH_STATS) do
      if changed[k] then
        battler.curStats[k] = freshValue(battler, k, st.base[k])
      else
        local row = badgeBoostRow(battler, k)
        if row then
          battler.curStats[k] = clamp(math.floor(battler.curStats[k] * (row.num or 9) / (row.den or 8)))
        end
      end
    end
  end

  local function onFrame()
    local battle = currentBattle()
    if not battle then return end
    if battle.player then pollBattler(battle.player) end
    if battle.enemy then pollBattler(battle.enemy) end
  end

  if not C.wrappedUpdate and C.game and C.game.update then
    C.origUpdate = C.game.update
    C.game.update = function(self, dt)
      C.origUpdate(self, dt)
      pcall(onFrame)
    end
    C.wrappedUpdate = true
  end
end
