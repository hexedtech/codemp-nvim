local native = require('codemp.loader').load()

local workspace = nil


local function login(username, password, ws)
	native.login(username, password, ws)
	print(" ++ logged in as '" .. username .. "' on " .. ws)
end

return {
	login = login,
	workspace = workspace,
}
