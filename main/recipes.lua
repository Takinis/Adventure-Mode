local AddRecipeToFilter = AddRecipeToFilter
local AddRecipe2 = AddRecipe2
local AddSimPostInit = AddSimPostInit
GLOBAL.setfenv(1, GLOBAL)

local diviningrod = AddRecipe2("diviningrod", {Ingredient("twigs", 1), Ingredient("nightmarefuel", 4), Ingredient("gears", 1)}, TECH.NONE) -- SCIENCE_TWO does not work for whatever reason?!
AddRecipeToFilter("diviningrod", "MAGIC")

local function SetRecipeIngredients(recipe_name, ingredients)
    if AllRecipes[recipe_name] ~= nil then
        AllRecipes[recipe_name].ingredients = ingredients
    end
end

AddSimPostInit(function()
    if not ShardGameIndex:IsAdventureActive() then
        return
    end
    SetRecipeIngredients("boat_item", {Ingredient("boards", 9999)})
    SetRecipeIngredients("boat_grass_item", {Ingredient("cutgrass", 9999), Ingredient("twigs", 9999)})
end)