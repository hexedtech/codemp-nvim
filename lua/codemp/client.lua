local workspace = require("codemp.workspace")

local function connect()
	if CODEMP.config.username == nil then
		CODEMP.config.username = vim.g.codemp_username or vim.fn.input("username > ", "")
	end
	if CODEMP.config.password == nil then
		CODEMP.config.password = vim.g.codemp_password or vim.fn.input("password > ", "")
	end
	CODEMP.native.connect(CODEMP.config):and_then(function (client)
		require('codemp.session').client = client
		require('codemp.window').update()
		workspace.list()
	end)
end

return {
	connect = connect
}
