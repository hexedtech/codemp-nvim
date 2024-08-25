local native = require("codemp.loader").load()
local window = require("codemp.window")
local session = require("codemp.session")
local workspace = require("codemp.workspace")

local function connect(host, username, password)
	if host == nil then host = 'http://codemp.dev:50053' end
	if username == nil then username = vim.g.codemp_username or vim.fn.input("username > ", "") end
	if password == nil then password = vim.g.codemp_password or vim.fn.input("password > ", "") end
	native.connect(host, username, password):and_then(function (client)
		session.client = client
		window.update()
		print(" ++ connected to " .. host .. " as " .. username)
		vim.schedule(function () workspace.list(client) end)
	end)
end

return {
	connect = connect
}
