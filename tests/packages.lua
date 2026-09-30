local config = require("tmux_picker.config")
local json = require("tmux_picker.json")
local packages = require("tmux_picker.packages")
local value = {path="a'path\nwith\tquotes\" and \\slashes", enabled=false, nested={1,2,3}}
local encoded = json.encode(value)
local decoded = assert(json.decode(encoded))
assert(decoded.path == value.path and decoded.enabled == false and decoded.nested[3] == 3)
config.plugins = {"owner/example.git", {repo="git@github.com:owner/other.git", name="custom", entry="lua/plugin.lua", version="v1", enabled=false}}
local specs = packages.specs()
assert(specs[1].name == "example" and specs[1].entry == "plugin.lua" and specs[1].enabled)
assert(specs[2].name == "custom" and not specs[2].enabled and specs[2].version == "v1")
for _, invalid in ipairs({{repo="owner/repo", name="../escape"}, {repo="owner/repo", entry="../plugin.lua"},
	{repo="owner/repo", enabled="false"}, {repo="owner/repo", version=false}}) do
	config.plugins = {invalid}
	assert(not pcall(packages.specs))
end
config.plugins = {"one/demo", "two/demo"}
assert(not pcall(packages.specs))
print("declarative plugin configuration tests passed")
