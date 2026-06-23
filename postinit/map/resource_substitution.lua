GLOBAL.setfenv(1, GLOBAL)

local Resource_Substitution = require("map/resource_substitution")

local ad_substitution_list = 
{
    ["tree"] = 		        {"evergreen_burnt", "evergreen_stump", "evergreen_sparse", "marsh_tree"},
    ["trees"] = 		    {"evergreen_burnt", "evergreen_stump", "evergreen_sparse", "marsh_tree"},
	["smallmammal"] = 		{"depleted_grass"},
    ["rabbithole"] = 	    {"depleted_grass"},
    ["perma_grass"] = 	    {"depleted_grass", "flower"},
    ["perma_sapling"] = 	{"marsh_bush"},
}

local _GetSubstitute = Resource_Substitution.GetSubstitute
Resource_Substitution.GetSubstitute = function(item, ...)
	if ad_substitution_list[item] ~= nil then
		return GetRandomItem(ad_substitution_list[item])
	end
    return _GetSubstitute(item, ...)
end