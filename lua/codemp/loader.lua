---@module 'annotations'

---@return Codemp
local function load()
	local native, _ = require("codemp.native")
	return native
end

return {
	load = load,
}
