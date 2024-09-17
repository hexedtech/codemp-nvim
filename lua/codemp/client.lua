local workspace = require("codemp.workspace")

local function connect()
	---@type Config
	local tmp_cfg = vim.tbl_extend('force', {}, CODEMP.config)
	if tmp_cfg.username == nil or #tmp_cfg.username == 0 then
		tmp_cfg.username = vim.g.codemp_username or vim.fn.input("username > ", "")
	end
	if tmp_cfg.password == nil or #tmp_cfg.password == 0 then
		tmp_cfg.password = vim.g.codemp_password or vim.fn.input("password > ", "")
	end
	print(" -- connecting ...")
	CODEMP.native.connect(tmp_cfg):and_then(function (client)
		print(" ++ connected")
		CODEMP.client = client
		require('codemp.window').update()
		workspace.list()
	end)
end

return {
	connect = connect
}
