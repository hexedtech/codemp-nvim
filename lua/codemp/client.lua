local workspace = require("codemp.workspace")

local function connect()
	---@type Config
	local tmp_cfg = vim.tbl_extend('force', {}, CODEMP.config)
	if not tmp_cfg.username then
		tmp_cfg.username = vim.g.codemp_username or vim.fn.input("username > ", "")
	end
	if not tmp_cfg.password then
		tmp_cfg.password = vim.g.codemp_password or vim.fn.input("password > ", "")
	end
	CODEMP.native.connect(tmp_cfg):and_then(function (client)
		CODEMP.client = client
		require('codemp.window').update()
		workspace.list()
	end)
end

return {
	connect = connect
}
