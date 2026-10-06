-- Hit from talents. The character sheet's Hit Rating only converts rating, but the server adds
-- talent hit flat on top of it (SPELL_AURA_MOD_HIT_CHANCE, to melee and ranged alike, see
-- Player::UpdateMeleeHitChances), so the sheet under-reports. Ranks, values and weapon
-- requirements below are read from 3.3.5 Spell.dbc.
local _, ns = ...

-- Spell.dbc's EquippedItemSubClassMask bits, by enUS item subtype.
local SUBCLASS_BIT = {
    ["One-Handed Axes"] = 0,   ["Two-Handed Axes"] = 1,    ["Bows"] = 2,     ["Guns"] = 3,
    ["One-Handed Maces"] = 4,  ["Two-Handed Maces"] = 5,   ["Polearms"] = 6,
    ["One-Handed Swords"] = 7, ["Two-Handed Swords"] = 8,  ["Staves"] = 10,
    ["Fist Weapons"] = 13,     ["Miscellaneous"] = 14,     ["Daggers"] = 15, ["Thrown"] = 16,
    ["Crossbows"] = 18,        ["Wands"] = 19,             ["Fishing Poles"] = 20,
}

-- Keyed by class so Mage's Precision (spell hit only) can't match Rogue's. `weapons` is the mask the
-- talent's aura needs on some equipped weapon; without one the server takes the aura off.
-- Shaman's Dual Wield Specialization has no weapon requirement in the DBC, so the server counts
-- it even with one weapon.
local HIT_TALENTS = {
    ROGUE       = { { name = "Precision", perRank = 1, weapons = 0x5a09d,
                      needs = "a dagger, fist weapon, one-handed axe, mace or sword, or a ranged weapon" } },
    WARRIOR     = { { name = "Precision", perRank = 1, weapons = 0x2a5f3,
                      needs = "a melee weapon" } },
    DEATHKNIGHT = { { name = "Nerves of Cold Steel", perRank = 1, weapons = 0xa091,
                      needs = "a one-handed weapon" } },
    HUNTER      = { { name = "Focused Aim", perRank = 1 } },
    SHAMAN      = { { name = "Dual Wield Specialization", perRank = 2 } },
    PALADIN     = { { name = "Enlightened Judgements", perRank = 2 } },
}

local function hasBit(mask, bitIndex)
    return math.floor(mask / 2 ^ bitIndex) % 2 == 1
end

-- Main hand, off hand and ranged, the same slots the server scans.
local function hasFittingWeapon(mask)
    for slot = 16, 18 do
        local link = GetInventoryItemLink("player", slot)
        local subType = link and select(7, GetItemInfo(link))
        local bitIndex = subType and SUBCLASS_BIT[subType]
        if bitIndex and hasBit(mask, bitIndex) then return true end
    end
    return false
end

-- Active spec only, which is what GetTalentInfo reads by default.
local function talentRank(name)
    for tab = 1, GetNumTalentTabs() do
        for i = 1, GetNumTalents(tab) do
            local talentName, _, _, _, rank, maxRank = GetTalentInfo(tab, i)
            if talentName == name then return rank or 0, maxRank or 0 end
        end
    end
    return 0, 0
end

-- Hit % the talents add, plus one entry per talent the player has points in.
function ns.TalentHit()
    local _, class = UnitClass("player")
    local total, sources = 0, {}
    for _, t in ipairs(HIT_TALENTS[class] or {}) do
        local rank, maxRank = talentRank(t.name)
        if rank > 0 then
            local active = not t.weapons or hasFittingWeapon(t.weapons)
            local pct = rank * t.perRank
            if active then total = total + pct end
            sources[#sources + 1] = { name = t.name, rank = rank, maxRank = maxRank, pct = pct,
                active = active, needs = t.needs }
        end
    end
    return total, sources
end

-- Hit on top of rating. GetHitModifier, where the client has it, also sees buffs, so take whichever
-- is larger rather than adding them and counting the talents twice.
function ns.ExtraHit()
    local talents, sources = ns.TalentHit()
    local modifier = GetHitModifier and GetHitModifier() or 0
    return math.max(talents, modifier), talents, sources
end

-- ---------------------------------------------------------------------------------------------
-- Character sheet: the melee and ranged Hit Rating rows (stock and DragonUI both fill them
-- through PaperDollFrame_SetRating)
-- ---------------------------------------------------------------------------------------------

local WHITE = "|cffffffff"
local GREEN = "|cff20ff20"
local GREY = "|cff999999"
local CLOSE = "|r"

local function pct(v)
    return string.format("%.2f%%", v)
end

local function trimmed(v)
    return (string.format("%.2f", v):gsub("%.?0+$", "")) .. "%"
end

local function bossLines(kind, lines)
    local info = ns.InfoForKind and ns.InfoForKind(kind)
    if not info then return end
    local F = ns.Formulas
    local boss = info.level + 3
    local special = F.Miss(info.effective, boss, info.hit, false)
    local text = string.format("Against a level %d boss your %s miss %s%s%s",
        boss, kind == "ranged" and "shots" or "special attacks", WHITE, pct(special), CLOSE)
    if info.dualWield then
        text = text .. string.format(" and your white swings %s%s%s (dual wield)",
            WHITE, pct(F.Miss(info.effective, boss, info.hit, true)), CLOSE)
    end
    lines[#lines + 1] = text .. "."
    if special > 0 then
        lines[#lines + 1] = string.format("%s more hit would stop %s missing.", trimmed(special),
            kind == "ranged" and "shots" or "special attacks")
    end
end

if PaperDollFrame_SetRating then
    hooksecurefunc("PaperDollFrame_SetRating", function(statFrame, ratingIndex)
        local kind = (ratingIndex == CR_HIT_MELEE and "main") or (ratingIndex == CR_HIT_RANGED and "ranged")
        if not kind then return end
        local extra, talents, sources = ns.ExtraHit()
        if extra <= 0 and #sources == 0 then return end

        local rating = GetCombatRating(ratingIndex)
        local fromRating = GetCombatRatingBonus(ratingIndex)
        local text = statFrame:GetName() and _G[statFrame:GetName() .. "StatText"]
        if text and extra > 0 then
            text:SetText(rating .. " " .. GREEN .. "+" .. trimmed(extra) .. CLOSE)
        end

        local lines = {}
        lines[#lines + 1] = string.format("%sTotal hit: %s%s", WHITE, pct(fromRating + extra), CLOSE)
        lines[#lines + 1] = string.format("%s from %d hit rating", pct(fromRating), rating)
        for _, s in ipairs(sources) do
            if s.active then
                lines[#lines + 1] = string.format("%s+%s%s from %s (%d/%d)", GREEN, trimmed(s.pct), CLOSE,
                    s.name, s.rank, s.maxRank)
            else
                lines[#lines + 1] = string.format("%s%s (%d/%d) is off: it needs %s.%s", GREY, s.name,
                    s.rank, s.maxRank, s.needs, CLOSE)
            end
        end
        if extra > talents then
            lines[#lines + 1] = string.format("%s+%s%s from buffs", GREEN, trimmed(extra - talents), CLOSE)
        end
        lines[#lines + 1] = GREY .. "The number on the sheet is rating only. The server adds talent "
            .. "hit on top of it." .. CLOSE
        bossLines(kind, lines)

        statFrame.tooltip2 = (statFrame.tooltip2 and (statFrame.tooltip2 .. "\n\n") or "")
            .. table.concat(lines, "\n")
    end)
end
