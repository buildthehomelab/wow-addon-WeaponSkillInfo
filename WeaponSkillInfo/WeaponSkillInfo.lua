local ADDON, ns = ...
local F = ns.Formulas

-- enUS item subtypes -> the skill line that governs them. Shields, relics, fishing poles and
-- off-hand frills aren't here, so they get no skill info.
local SKILL_BY_SUBTYPE = {
    ["One-Handed Swords"] = "Swords",       ["Two-Handed Swords"] = "Two-Handed Swords",
    ["One-Handed Axes"]   = "Axes",         ["Two-Handed Axes"]   = "Two-Handed Axes",
    ["One-Handed Maces"]  = "Maces",        ["Two-Handed Maces"]  = "Two-Handed Maces",
    ["Daggers"]           = "Daggers",      ["Fist Weapons"]      = "Fist Weapons",
    ["Staves"]            = "Staves",       ["Polearms"]          = "Polearms",
    ["Bows"]              = "Bows",         ["Guns"]              = "Guns",
    ["Crossbows"]         = "Crossbows",    ["Thrown"]            = "Thrown",
    ["Wands"]             = "Wands",
}

local RANGED_SKILLS = { Bows = true, Guns = true, Crossbows = true, Thrown = true, Wands = true }

local WEAPON_SKILLS = { Unarmed = true }
for _, skill in pairs(SKILL_BY_SUBTYPE) do WEAPON_SKILLS[skill] = true end

local SLOTS = {
    { button = "CharacterMainHandSlot",      id = 16, kind = "main" },
    { button = "CharacterSecondaryHandSlot", id = 17, kind = "off" },
    { button = "CharacterRangedSlot",        id = 18, kind = "ranged" },
}
local SLOT_BY_BUTTON = {}
for _, s in ipairs(SLOTS) do SLOT_BY_BUTTON[s.button] = s end

-- Cat, Bear, Dire Bear: the server treats feral combat skill as always maxed.
local FERAL_FORMS = { [1] = true, [5] = true, [8] = true }

local GOLD = { 1, 0.82, 0 }
local WHITE = { 1, 1, 1 }
local GREY = { 0.6, 0.6, 0.6 }

-- ---------------------------------------------------------------------------------------------
-- Reading the player's skill
-- ---------------------------------------------------------------------------------------------

-- Skills under a collapsed header aren't returned, which is why callers have a fallback.
local function findSkillLine(name)
    for i = 1, GetNumSkillLines() do
        local lineName, isHeader, _, rank, temp, modifier, maxRank = GetSkillLineInfo(i)
        if not isHeader and lineName == name then
            return rank, (temp or 0) + (modifier or 0), maxRank
        end
    end
end

local function ratingBonus(kind)
    local total = 0
    if CR_WEAPON_SKILL then total = total + GetCombatRatingBonus(CR_WEAPON_SKILL) end
    local perHand = (kind == "main" and CR_WEAPON_SKILL_MAINHAND)
                 or (kind == "off" and CR_WEAPON_SKILL_OFFHAND)
                 or (kind == "ranged" and CR_WEAPON_SKILL_RANGED)
    if perHand then total = total + GetCombatRatingBonus(perHand) end
    return math.floor(total)
end

local function inFeralForm()
    local _, class = UnitClass("player")
    return class == "DRUID" and GetShapeshiftFormID and FERAL_FORMS[GetShapeshiftFormID() or 0]
end

local function hasOffhandWeapon()
    return OffhandHasWeapon and OffhandHasWeapon() and true or false
end

-- Skill name for what's in a slot; nil when the slot holds nothing that uses a weapon skill.
local function skillForSlot(slot)
    local link = GetInventoryItemLink("player", slot.id)
    if not link then
        return slot.kind == "main" and "Unarmed" or nil
    end
    local subType = select(7, GetItemInfo(link))
    return SKILL_BY_SUBTYPE[subType]
end

local function slotForSkill(name)
    for _, slot in ipairs(SLOTS) do
        if skillForSlot(slot) == name then return slot end
    end
end

-- Everything the tooltip needs about one weapon skill. `slot` is where it's equipped, or nil.
local function buildInfo(name, slot)
    local level = UnitLevel("player")
    local kind = slot and slot.kind or (RANGED_SKILLS[name] and "ranged" or "main")
    local base, bonus, max = findSkillLine(name)

    if not base and slot then
        if kind == "ranged" and UnitRangedAttack then
            base, bonus = UnitRangedAttack("player")
        elseif UnitAttackBothHands then
            local mainBase, mainMod, offBase, offMod = UnitAttackBothHands("player")
            if kind == "main" then base, bonus = mainBase, mainMod else base, bonus = offBase, offMod end
        end
    else
        bonus = (bonus or 0) + ratingBonus(kind)
    end
    if not base or base <= 0 then return nil end

    max = (max and max > 0) and max or level * 5
    local info = {
        name = name, kind = kind, equipped = slot ~= nil, level = level,
        base = base, bonus = bonus or 0, max = max,
        effective = base + (bonus or 0),
        feral = kind == "main" and slot ~= nil and inFeralForm(),
    }
    if info.feral then info.effective = level * 5 end

    if kind == "ranged" then
        info.hit = GetCombatRatingBonus(CR_HIT_RANGED)
        info.expertise = 0
        info.dualWield = false
        info.speed = UnitRangedDamage("player")
    else
        info.hit = GetCombatRatingBonus(CR_HIT_MELEE) + (GetHitModifier and GetHitModifier() or 0)
        local mainExp, offExp = 0, 0
        if GetExpertisePercent then mainExp, offExp = GetExpertisePercent() end
        info.expertise = (kind == "off" and offExp or mainExp) or 0
        -- Only white swings carry the penalty, and only while something is in the off hand.
        info.dualWield = slot ~= nil and hasOffhandWeapon()
        local mainSpeed, offSpeed = UnitAttackSpeed("player")
        info.speed = kind == "off" and offSpeed or mainSpeed
    end
    return info
end

function ns.InfoForSlot(slot)
    local name = skillForSlot(slot)
    return name and buildInfo(name, slot)
end

function ns.InfoForSkillName(name)
    if not WEAPON_SKILLS[name] then return nil end
    return buildInfo(name, slotForSkill(name))
end

-- ---------------------------------------------------------------------------------------------
-- Tooltip
-- ---------------------------------------------------------------------------------------------

-- Graded by what the gap costs in miss chance against your own level, which is what you feel.
local function gapColor(info)
    local penalty = F.Miss(info.effective, info.level, 0, false) - F.Miss(info.max, info.level, 0, false)
    if penalty <= 0.05 then return 0.25, 1, 0.25 end
    if penalty < 5 then return 1, 1, 0.2 end
    if penalty < 15 then return 1, 0.6, 0.1 end
    return 1, 0.25, 0.25
end
ns.GapColor = gapColor

local function pct(v)
    return string.format("%.1f%%", v)
end

local function comma(n)
    local s = tostring(math.floor(n + 0.5))
    while true do
        local replaced
        s, replaced = s:gsub("^(%d+)(%d%d%d)", "%1,%2")
        if replaced == 0 then return s end
    end
end

local function line(tt, text, color, wrap)
    tt:AddLine(text, color[1], color[2], color[3], wrap)
end

local function whatItMeans(info)
    local weapon = info.name == "Unarmed" and "fighting without a weapon" or ("using " .. info.name:lower())
    if info.feral then
        return "In Bear or Cat Form the server counts your weapon skill as maxed, so the table below is "
            .. "what you get while shifted."
    end
    if info.base >= info.max then
        return string.format("%d is your skill at %s and %d is the most you can have at level %d "
            .. "(5 per level). You're capped: the cap rises by 5 each level, so it starts climbing "
            .. "again when you ding.", info.base, weapon, info.max, info.level)
    end
    return string.format("%d is how practised you are at %s. %d is the most you can have at level "
        .. "%d (5 per level). You're %d short, and against mobs every point short makes you miss "
        .. "more and get dodged more.", info.base, weapon, info.max, info.level, info.max - info.base)
end

function ns.AddSkillLines(tt, info)
    local level = info.level
    local melee = info.kind ~= "ranged"
    local r, g, b = gapColor(info)

    tt:AddLine(" ")
    tt:AddDoubleLine("Weapon skill: " .. info.name, info.effective .. " / " .. info.max,
        GOLD[1], GOLD[2], GOLD[3], r, g, b)
    line(tt, whatItMeans(info), WHITE, true)
    if info.bonus > 0 and not info.feral then
        line(tt, string.format("Includes +%d from gear, talents or buffs (%d base).", info.bonus, info.base), GREY, true)
    end

    -- Per-swing outcomes against mobs from your level up to a raid boss.
    tt:AddLine(" ")
    tt:AddDoubleLine("Against a mob of level", melee and "Miss  Dodge  Glance" or "Miss  Dodge",
        GOLD[1], GOLD[2], GOLD[3], GOLD[1], GOLD[2], GOLD[3])
    for d = 0, 3 do
        local target = level + d
        local miss, dodge, glance = F.Outcomes(info.effective, level, target, info.hit, info.expertise,
            info.dualWield, melee)
        local right = pct(miss) .. "   " .. pct(dodge)
        if melee then
            right = right .. "   " .. (glance > 0 and pct(glance) or "--")
        end
        local label = string.format("%d  (def %d)%s", target, F.Defense(target), d == 3 and "  boss" or "")
        tt:AddDoubleLine(label, right, 0.85, 0.85, 0.85, 1, 1, 1)
    end

    if info.effective < info.max then
        local miss, dodge = F.Outcomes(info.max, level, level, info.hit, info.expertise, info.dualWield, melee)
        line(tt, string.format("At %d skill it would be %s miss and %s dodge against level %d.",
            info.max, pct(miss), pct(dodge), level), { 0.5, 1, 0.5 }, true)
    end

    local notes = {}
    if info.hit > 0 then
        notes[#notes + 1] = string.format("Your %s hit is counted.", pct(info.hit))
    end
    if info.dualWield then
        notes[#notes + 1] = "Miss includes the 19% dual-wield penalty, which only white swings pay."
    end
    if melee then
        notes[#notes + 1] = "Glancing blows only happen against mobs above your level, and each "
            .. "one does 10% less damage per level of difference (up to 30%)."
    end
    notes[#notes + 1] = string.format("Low skill does not lower your crit chance, and against "
        .. "players your skill always counts as %d.", info.max)
    line(tt, table.concat(notes, " "), GREY, true)

    -- How long until it's capped, if it isn't.
    local cap = level * 5
    if info.base < cap and not info.feral then
        local intellect = select(2, UnitStat("player", 4)) or 0
        local chance = F.SkillUpChance(info.base, level, level, intellect)
        local swings = F.SwingsToCap(info.base, level, level, intellect)
        tt:AddLine(" ")
        line(tt, "Raising it", GOLD)
        local text = string.format("Each swing at a level %d mob has a %s chance to add a point. "
            .. "Reaching %d takes about %s swings", level, pct(chance), cap, comma(swings))
        if info.equipped and info.speed and info.speed > 0 then
            local minutes = swings * info.speed / 60
            text = text .. string.format(" (%s of auto-attack at your %.2fs speed)",
                minutes >= 90 and string.format("%.1f hours", minutes / 60)
                or string.format("%d min", math.max(1, math.floor(minutes + 0.5))), info.speed)
        end
        text = text .. ". Higher-level mobs and more Intellect speed it up. Crits and blocked "
            .. "swings don't count, and fighting players never raises it."
        if not info.equipped then
            text = text .. " Equip a weapon of this type to train it."
        end
        line(tt, text, WHITE, true)
    end
end

-- ---------------------------------------------------------------------------------------------
-- Character window: weapon slot badges and tooltips
-- ---------------------------------------------------------------------------------------------

local function badgeFor(button)
    if not button.WeaponSkillInfoText then
        local text = button:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
        text:SetPoint("TOPLEFT", button, "TOPLEFT", 2, -2)
        button.WeaponSkillInfoText = text
    end
    return button.WeaponSkillInfoText
end

local function updateBadge(slot)
    local button = _G[slot.button]
    if not button then return end
    local text = badgeFor(button)
    local info = WeaponSkillInfoDB.badges and ns.InfoForSlot(slot)
    if info and not info.feral and info.base < info.max then
        text:SetText(info.effective)
        text:SetTextColor(gapColor(info))
        text:Show()
    else
        text:Hide()
    end
end

local function updateBadges()
    for _, slot in ipairs(SLOTS) do updateBadge(slot) end
end

-- Runs from the slot's own OnEnter and from its tooltip refreshes, after Blizzard has filled the
-- tooltip with the item (or the empty slot's name), so our block always lands at the bottom.
hooksecurefunc("PaperDollItemSlotButton_OnEnter", function(button)
    local slot = SLOT_BY_BUTTON[button:GetName() or ""]
    if not slot or not GameTooltip:IsOwned(button) then return end
    local info = ns.InfoForSlot(slot)
    if not info then return end
    ns.AddSkillLines(GameTooltip, info)
    GameTooltip:Show()
end)

-- ---------------------------------------------------------------------------------------------
-- Skills tab: stock SkillFrame rows, and DragonUI's replacement rows
-- ---------------------------------------------------------------------------------------------

local function hookStockSkillRows()
    for i = 1, (SKILLS_TO_DISPLAY or 12) do
        local label = _G["SkillRankFrame" .. i .. "SkillName"]
        local hover = _G["SkillRankFrame" .. i .. "Border"] or _G["SkillRankFrame" .. i]
        if label and hover then
            hover:HookScript("OnEnter", function(self)
                local info = ns.InfoForSkillName(label:GetText() or "")
                if not info then return end
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(info.name, GOLD[1], GOLD[2], GOLD[3])
                ns.AddSkillLines(GameTooltip, info)
                GameTooltip:Show()
            end)
            hover:HookScript("OnLeave", function() GameTooltip:Hide() end)
        end
    end
end

-- DragonUI draws its own skill rows and stamps each with _skillName; its OnEnter ends in Show().
local decorated
hooksecurefunc(GameTooltip, "Show", function(tt)
    if decorated then return end
    local owner = tt:GetOwner()
    local name = owner and owner._skillName
    if not name then return end
    local info = ns.InfoForSkillName(name)
    if not info then return end
    decorated = true
    ns.AddSkillLines(tt, info)
    tt:Show()
end)
GameTooltip:HookScript("OnTooltipCleared", function() decorated = nil end)
GameTooltip:HookScript("OnHide", function() decorated = nil end)

-- ---------------------------------------------------------------------------------------------
-- Events and slash command
-- ---------------------------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("SKILL_LINES_CHANGED")
events:RegisterEvent("PLAYER_LEVEL_UP")
events:RegisterEvent("UNIT_INVENTORY_CHANGED")
events:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
events:SetScript("OnEvent", function(_, event, unit)
    if event == "PLAYER_LOGIN" then
        WeaponSkillInfoDB = WeaponSkillInfoDB or {}
        if WeaponSkillInfoDB.badges == nil then WeaponSkillInfoDB.badges = true end
        hookStockSkillRows()
        if PaperDollFrame then PaperDollFrame:HookScript("OnShow", updateBadges) end
    elseif event == "UNIT_INVENTORY_CHANGED" and unit ~= "player" then
        return
    end
    if WeaponSkillInfoDB then updateBadges() end
end)

local function printf(fmt, ...)
    DEFAULT_CHAT_FRAME:AddMessage("|cffffd100WeaponSkillInfo:|r " .. string.format(fmt, ...))
end

SLASH_WEAPONSKILLINFO1 = "/wsi"
SLASH_WEAPONSKILLINFO2 = "/weaponskill"
SlashCmdList.WEAPONSKILLINFO = function(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")
    if msg == "badges" then
        WeaponSkillInfoDB.badges = not WeaponSkillInfoDB.badges
        updateBadges()
        printf("slot badges %s.", WeaponSkillInfoDB.badges and "on" or "off")
        return
    end
    local any
    for _, slot in ipairs(SLOTS) do
        local info = ns.InfoForSlot(slot)
        if info then
            any = true
            local miss = F.Outcomes(info.effective, info.level, info.level, info.hit, info.expertise,
                info.dualWield, info.kind ~= "ranged")
            local r, g, b = gapColor(info)
            printf("%s |cff%02x%02x%02x%d/%d|r, %s miss vs level %d.", info.name,
                r * 255, g * 255, b * 255, info.effective, info.max, pct(miss), info.level)
        end
    end
    if not any then printf("no weapon skills in use.") end
    printf("hover a weapon slot for the full breakdown. /wsi badges toggles the slot numbers.")
end
