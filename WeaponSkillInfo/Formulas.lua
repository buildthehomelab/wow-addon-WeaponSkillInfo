-- AzerothCore's combat math for a player attacking a creature, so the tooltips quote the numbers
-- the server actually rolls, not retail's. Sources, all in azerothcore-wotlk:
--   Unit::MeleeSpellMissChance, Unit::RollMeleeOutcomeAgainst, Unit::GetUnitCriticalChance
--   Player::UpdateCombatSkills, Acore::XP::GetGrayLevel
-- Pure functions only: no WoW API, so they can be run under plain Lua.
local _, ns = ...
ns = ns or {}

local F = {}
ns.Formulas = F

local BASE_MISS = 5
local DUAL_WIELD_MISS = 19
local MISS_CAP = 60
local MOB_DODGE = 5
local GLANCE_CAP = 40

-- A creature's defense is always 5 x its level.
function F.Defense(level)
    return level * 5
end

-- Up to 10 points short costs 0.1% miss per point; past that, 0.4% per point. That second slope
-- is why a weapon 50 points under the cap misses a same-level mob about a fifth of the time.
function F.Miss(skill, targetLevel, hit, dualWield)
    local diff = F.Defense(targetLevel) - skill
    local miss = BASE_MISS
    if dualWield then miss = miss + DUAL_WIELD_MISS end
    if diff > 10 then
        miss = miss + 1 + (diff - 10) * 0.4
    else
        miss = miss + diff * 0.1
    end
    miss = miss - (hit or 0)
    if miss < 0 then return 0 end
    if miss > MISS_CAP then return MISS_CAP end
    return miss
end

-- Mobs dodge 5%, plus 0.04% per point of weapon skill under their defense. Applies to ranged too.
function F.Dodge(skill, targetLevel, expertise)
    local dodge = MOB_DODGE + (F.Defense(targetLevel) - skill) * 0.04 - (expertise or 0)
    return dodge > 0 and dodge or 0
end

-- Melee only, and only against mobs above your level. Skill above your cap doesn't help here.
function F.Glance(skill, playerLevel, targetLevel)
    if targetLevel <= playerLevel then return 0 end
    local capped = math.min(skill, playerLevel * 5)
    local glance = 10 + (F.Defense(targetLevel) - capped)
    if glance > GLANCE_CAP then glance = GLANCE_CAP end
    return glance > 0 and glance or 0
end

-- A glancing blow's damage cut depends on the level gap, not on skill.
function F.GlancePenalty(playerLevel, targetLevel)
    return math.min(math.max(targetLevel - playerLevel, 0), 3) * 10
end

-- The outcomes share one 100% roll in this order, so a slot can't take more than what the earlier
-- ones left over. Returns what actually happens per swing.
function F.Outcomes(skill, playerLevel, targetLevel, hit, expertise, dualWield, melee)
    local miss = F.Miss(skill, targetLevel, hit, dualWield)
    local dodge = math.min(F.Dodge(skill, targetLevel, expertise), 100 - miss)
    local glance = melee and math.min(F.Glance(skill, playerLevel, targetLevel), 100 - miss - dodge) or 0
    return miss, dodge, glance
end

function F.GrayLevel(level)
    if level <= 5 then return 0 end
    if level <= 39 then return level - 5 - math.floor(level / 10) end
    if level <= 59 then return level - 1 - math.floor(level / 5) end
    return level - 9
end

-- Chance (percent) that one swing raises base skill by a point. The server caps the counted mob
-- level at yours + 5, and never rolls below 1%.
function F.SkillUpChance(base, playerLevel, targetLevel, intellect)
    local gap = playerLevel * 5 - base
    if gap <= 0 then return 0 end
    local mobLevel = math.min(targetLevel, playerLevel + 5)
    local levelDiff = math.max(mobLevel - F.GrayLevel(playerLevel), 3)
    local chance = 3 * levelDiff * gap / playerLevel
    chance = chance + chance * 0.02 * (intellect or 0)
    if chance < 1 then chance = 1 end
    if chance > 100 then chance = 100 end
    return chance
end

-- Expected swings from `base` to the cap, one point per success (the server's default gain).
function F.SwingsToCap(base, playerLevel, targetLevel, intellect)
    local total = 0
    for s = base, playerLevel * 5 - 1 do
        total = total + 100 / F.SkillUpChance(s, playerLevel, targetLevel, intellect)
    end
    return total
end

return F
