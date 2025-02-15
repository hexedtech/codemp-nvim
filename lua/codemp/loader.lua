---@module 'annotations'

---@return Codemp?
local function load()
	local ok, native = pcall(require, "codemp.native")
	if ok then return native end
	print(native)
	return nil
end

return {
	load = load,
}
