local bridge = require("codemp.neo-tree.bridge")

local M = { name = "codemp" }

M.navigate = function(state, path)
	if path == nil then
		path = vim.fn.getcwd()
	end
	state.path = path
	bridge.update_state(state)
end

M.setup = function(config, global_config)
end

M.default_config = {
	renderers = {
		title = {
			{ "name" },
		},
		spacer = {
			{ "indent" },
		},
		root = {
			{ "icon" },
			{ "name" },
		},
		workspace = {
			{ "indent" },
			{ "icon" },
			{ "name" },
		},
		user = {
			{ "indent" },
			{ "icon" },
			{ "name" },
		},
		buffer = {
			{ "indent" },
			{ "icon" },
			{ "users" },
			{ "name" },
		},
		entry = {
			{ "indent" },
			{ "icon" },
			{ "name" },
		},
		button = {
			{ "indent" },
			{ "icon" },
			{ "name" },
		},
	},
}

return M
