local function en_zh(en, zh)
    return (locale == "zh" or locale == "zhr" or locale == "zht") and zh or en
end

name = en_zh("Adventure Mode", "冒险模式")
description = ""
author = "Sydney & Ardent"
forumthread = ""

version = "1.0"
api_version = 10

dst_compatible = true

client_only_mod = false
all_clients_require_mod = true

icon_atlas = "modicon.xml"
icon = "modicon.tex"

priority = 9999
server_filter_tags = {"adventure","adventure mode"}

mod_dependencies = {}

configuration_options = {}
