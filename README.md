# WeaponSkillInfo

A World of Warcraft 3.3.5a addon that explains what a weapon skill like **Swords 100/300** actually does to you, right in the character window.

The numbers come from AzerothCore's combat code, so they match what the server rolls rather than retail.

## What it adds

- **Weapon slot badges.** When a weapon's skill is below the cap for your level, its current skill shows in the corner of the main hand, off hand or ranged slot. The colour shows how much the gap hurts: green (no penalty), yellow, orange, red.
- **Weapon slot tooltips.** Hovering a weapon slot adds a breakdown under the item:
  - what the two numbers mean (your skill / the cap, 5 per level) and any bonus from gear
  - your miss, dodge and glancing-blow chance per swing against mobs of your level up to +3 (boss), with your hit, expertise and the dual-wield penalty counted
  - what those chances would be at full skill
  - your chance per swing to gain a point, and roughly how many swings (and minutes of auto-attack) until it's capped
- **Hit from talents on the character sheet.** The stock Hit Rating stat (and DragonUI's) only converts rating, but the server adds talent hit on top. The melee and ranged Hit Rating rows now show it next to the rating (`99 +5%`), and their tooltips break down the total (rating, each talent, buffs) and say how often your attacks still miss a boss. Talents counted: Rogue and Warrior Precision, Death Knight Nerves of Cold Steel, Hunter Focused Aim, Shaman Dual Wield Specialization, Paladin Enlightened Judgements. A talent that needs a certain weapon type is shown as off when you don't have one equipped.
- **Skills tab tooltips.** The same breakdown on every weapon skill row, in the stock Skills tab and in DragonUI's.
- `/wsi` prints each equipped weapon's skill and miss chance to chat. `/wsi badges` toggles the slot numbers.

## How weapon skill works on AzerothCore

Against a mob, with *gap* = mob level x 5 - your skill:

| | |
|---|---|
| Miss | 5%, +0.1% per point of gap up to 10, then +0.4% per point beyond that (+19% for white swings while dual wielding), minus your hit, capped at 60% |
| Dodge | 5% + 0.04% per point of gap, minus expertise (ranged attacks too) |
| Glancing | melee only, mobs above your level only: 10% + (mob defense - your skill, capped at your max), up to 40% |
| Crit | not affected by your current skill |
| PvP | your skill always counts as maxed |
| Skill-up chance | 3 x max(mob level - gray level, 3) x (cap - skill) / your level, x (1 + 2% per Intellect), at least 1% |

The 0.4%-per-point slope is why a weapon 50 points under the cap misses a same-level mob about 22% of the time.

## Install

Copy the `WeaponSkillInfo` folder into `Interface/AddOns`. enUS client only (skill names are matched by their English names).
