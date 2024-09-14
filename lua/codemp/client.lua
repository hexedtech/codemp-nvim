local native = require("codemp.loader").load()
local session = require("codemp.session")
local workspace = require("codemp.workspace")

local function connect(host, username, password)
	if host == nil then host = 'http://code.mp:50053' end
	if username == nil then username = vim.g.codemp_username or vim.fn.input("username > ", "") end
	if password == nil then password = vim.g.codemp_password or vim.fn.input("password > ", "") end
	session.client = native.connect(host, username, password):await()
	require('codemp.window').update()
	vim.schedule(function () workspace.list() end)
end

return {
	connect = connect
}
