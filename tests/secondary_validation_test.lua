local secondary_handlers = {}

GLOBAL = _G
GLOBAL.setfenv = function()
end

Class = function()
    return {}
end

ShardWorldIndex =
{
    RegisterWorldIndexFileID = function()
    end,
    RegisterSecondaryTransitionHandler = function(_, operation, handler)
        secondary_handlers[operation] = handler
        return true
    end,
    RegisterForwardedTransitionHandler = function()
        return true
    end,
    Noop = function()
    end,
}

dofile("postinit/shardadventureindex.lua")

local begin = assert(secondary_handlers.BeginSecondaryAdventure)
local begin_opts =
{
    level_sequence = { "A", { id = "B" } },
    chapter = 2,
    chapter_revision = 3,
}
local valid, reason = begin.Validate(nil, begin_opts, nil)
assert(valid == true, reason)
assert(begin_opts.level_sequence[1] == "A")
assert(begin_opts.level_sequence[2].id == "B")
assert(begin_opts.chapter == 2)
assert(begin_opts.chapter_revision == 3)

local state =
{
    active = true,
    kind = "adventure",
    run_id = "run",
    sequence_id = "default",
    chapter = 2,
    chapter_revision = 4,
    level_sequence = { "A", "B", "C" },
}

local advance = assert(secondary_handlers.AdvanceSecondaryAdventure)
local advance_opts =
{
    run_id = "run",
    sequence_id = "default",
    chapter = 3,
    chapter_revision = 5,
}
valid, reason = advance.Validate(nil, advance_opts, state)
assert(valid == true, reason)
assert(advance_opts.chapter == 3)
assert(advance_opts.chapter_revision == 5)

local stale_advance =
{
    run_id = "run",
    sequence_id = "default",
    chapter = 3,
    chapter_revision = 4,
}
assert(advance.Validate(nil, stale_advance, state) == false)

local reset = assert(secondary_handlers.ResetSecondaryAdventure)
local reset_opts =
{
    run_id = "run",
    sequence_id = "default",
    chapter = 2,
    chapter_revision = 5,
}
valid, reason = reset.Validate(nil, reset_opts, state)
assert(valid == true, reason)
assert(reset_opts.chapter == 2)
assert(reset_opts.chapter_revision == 5)

local wrong_reset =
{
    run_id = "run",
    sequence_id = "default",
    chapter = 3,
    chapter_revision = 5,
}
assert(reset.Validate(nil, wrong_reset, state) == false)

print("secondary_validation_test: ok")
