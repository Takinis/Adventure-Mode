GLOBAL.setfenv(1, GLOBAL)

require("map/storygen")

local _GenerationPipeline = Story.GenerationPipeline
function Story:GenerationPipeline(...)
	if self.level.overrides.is_adventure then
		self.map_tags.TagData.StagehandGarden = false
	end

	return _GenerationPipeline(self, ...)
end

local _RunTaskSubstitution = Story.RunTaskSubstitution
function Story:RunTaskSubstitution(task, items, ...)
	if task.substitutes ~= nil and items ~= nil then
		for k, v in pairs(items) do
			print("original", k, v)
		end
		for k,v in pairs(task.substitutes) do
			if items[k] ~= nil then
				if type(items[k]) == "table" then
					items[k] = items[k].weight
				end
			end
			print("override:", v.name, items[k], k, 0)
		end
	end

	return _RunTaskSubstitution(self, task, items, ...)
end
