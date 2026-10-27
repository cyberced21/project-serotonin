class_name TierEffect
extends Resource
## One perk a building tier gives. The values of every building's *current* tier add up per
## stat (Village.stat), and the systems that care read them:
##   xp_bonus            fraction extra XP in every skill (Skills.add_xp)
##   double_hit_chance   chance a tool hit counts twice (ResourceNode.hit)
##   streak_double       every Nth biting hit in a row on a node counts twice (ResourceNode.hit)
##   extra_logs          extra drops from trees (ResourceNode)
##   fish_calm           fraction off every fish's scare radius (FishSchool.disturb); on the rod, fish
##                       notice the float from further and nibble less (FishingLure)
##   bonus_fish_chance   chance a speared fish counts twice (SpearFishing)
##   strike_window       sharper eyes: longer to pull on the rod, a wider spear (+0.25 = 25%)
##   run_speed           fraction faster walking and sprinting (Player)
##   extra_ore           extra drops from rocks and veins (ResourceNode)
##   rock_regrow         fraction off the respawn time of rocks and veins (ResourceNode)

@export var stat: StringName = &"xp_bonus"
@export var value := 0.0
## Shown in the upgrade panel, e.g. "Sharper tools: 20% chance of a double hit".
@export var text := ""
