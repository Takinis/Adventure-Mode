local AddUserCommand = AddUserCommand
local AddClientModRPCHandler = AddClientModRPCHandler
GLOBAL.setfenv(1, GLOBAL)

local VoteUtil = require("voteutil")

local COMMAND_NAME = "adventuremode_enter"
local VOTE_EXPIRY_PADDING = 5

local function CanStartAdventureVote(_command, caller)
    if TheWorld == nil or not TheWorld.ismastersim then
        return true
    end

    local pending = TheWorld._adventure_entry_vote
    if pending == nil or pending.starteruserid ~= caller.userid or
        pending.portal == nil or not pending.portal:IsValid() or
        pending.portal._adventure_transitioning or
        pending.expires_at < GetTime() or
        ShardGameIndex == nil or ShardGameIndex.adventure == nil or
        not ShardWorldIndex:IsMasterShard() or
        ShardGameIndex.adventure:IsActive() then
        return false, "ADVENTUREMODE"
    end

    pending.started = true
    pending.expires_at = GetTime() + TUNING.ADVENTURE_ENTRY_VOTE_TIMEOUT + VOTE_EXPIRY_PADDING
    return true
end

local function EnterAdventureAfterVote(params)
    if params == nil or params.voteselection ~= 1 or TheWorld == nil or not TheWorld.ismastersim then
        return
    end

    local pending = TheWorld._adventure_entry_vote
    TheWorld._adventure_entry_vote = nil

    if pending ~= nil and pending.started and pending.expires_at >= GetTime() and
        pending.portal ~= nil and pending.portal:IsValid() and
        ShardGameIndex ~= nil and ShardGameIndex.adventure ~= nil and
        ShardWorldIndex:IsMasterShard() and not ShardGameIndex.adventure:IsActive() then
        pending.portal:Adventure()
    end
end

AddUserCommand(COMMAND_NAME, {
    prettyname = nil,
    desc = nil,
    permission = COMMAND_PERMISSION.ADMIN,
    confirm = false,
    slash = false,
    usermenu = false,
    servermenu = false,
    params = {},
    vote = true,
    votetimeout = TUNING.ADVENTURE_ENTRY_VOTE_TIMEOUT,
    voteminpasscount = 1,
    votecountvisible = true,
    voteallownotvoted = true,
    voteoptions = nil,
    votetitlefmt = nil,
    votenamefmt = nil,
    votepassedfmt = nil,
    votefailedfmt = nil,
    votecanstartfn = CanStartAdventureVote,
    voteresultfn = VoteUtil.YesNoMajorityVote,
    serverfn = EnterAdventureAfterVote,
})

AddClientModRPCHandler("AdventureMode", "StartAdventureVote", function()
    TheNet:StartVote(smallhash(COMMAND_NAME))
end)

AddClientModRPCHandler("AdventureMode", "AdventureVoteDenied", function(message)
    if ThePlayer ~= nil and ThePlayer.components.talker ~= nil then
        ThePlayer.components.talker:Say(message or STRINGS.UI.ADVENTUREMODE_VOTE.FAILED)
    end
end)
