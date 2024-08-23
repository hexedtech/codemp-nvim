local native = require("codemp.loader").load()
local window = require("codemp.window")
local session = require("codemp.session")
local workspace = require("codemp.workspace")

local function connect(host, bang)
	if host == nil then host = 'http://codemp.alemi.dev:50054' end
	local user, password
	if bang then -- ignore configured values
		user = vim.fn.input("username > ", "")
		password = vim.fn.input("password > ", "")
	else
		user = vim.g.codemp_username or vim.fn.input("username > ", "")
		password = vim.g.codemp_password or vim.fn.input("password > ", "")
	end
	session.client = native.connect(host, user, password):await()
	session.available = workspace.list(session.client)
	window.update()
	print(" ++ connected to " .. host .. " as " .. user)
end

return {
	connect = connect
}
