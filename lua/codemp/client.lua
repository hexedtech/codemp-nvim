local session = require("codemp.session")
local workspace = require("codemp.workspace")

local function connect()
	if CODEMP.config.username == nil then
		CODEMP.config.username = vim.g.codemp_username or vim.fn.input("username > ", "")
	end
	if CODEMP.config.password == nil then
		CODEMP.config.password = vim.g.codemp_password or vim.fn.input("password > ", "")
	end
	session.client = CODEMP.native.connect(CODEMP.config):await()
	require('codemp.window').update()
	vim.schedule(function () workspace.list() end)
end

return {
	connect = connect
}
