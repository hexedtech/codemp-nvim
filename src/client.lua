local native = require('codemp.loader')()


local function login(username, password, workspace)
	native.login(username, password, workspace)
	print(" ++ logged in as '" .. username .. "' on " .. workspace)
end

return {
	login = login,
}
