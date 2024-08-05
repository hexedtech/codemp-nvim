local native = require('codemp.loader')() -- make sure we can load the native library correctly, otherwise no point going forward

local client = require('codemp.client')
local buffers = require('codemp.buffer')
local workspace = require('codemp.workspace')

-- TODO nvim docs say that we should stop all threads before exiting nvim
--  but we like to live dangerously (:
vim.loop.new_thread({}, function()
	vim.loop.sleep(500) -- sleep a bit leaving user config time to override logger opts
	local _codemp = require('codemp.loader')()
	local logger = _codemp.setup_tracing()
	while true do
		print(logger:recv())
	end
end)

local active_workspace = nil -- TODO dont use a single global one!!!

local function filter(needle, haystack)
	local hints = {}
	for _, opt in pairs(haystack) do
		if vim.startswith(opt, needle) then
			table.insert(hints, opt)
		end
	end
	return hints
end

vim.api.nvim_create_user_command(
	"MP",
	function (args)
		if args.fargs[1] == "login" then
			client.login(args.fargs[2], args.fargs[3], args.fargs[4])
		elseif args.fargs[1] == "create" then
			if #args.fargs < 2 then error("missing buffer name") end
			if active_workspace == nil then error("connect to a workspace first") end
			buffers.create(active_workspace, args.fargs[2])
		elseif args.fargs[1] == "join" then
			if #args.fargs < 2 then error("missing workspace name") end
			active_workspace = args.fargs[2]
			workspace.join(active_workspace)
		elseif args.fargs[1] == "attach" then
			if #args.fargs < 2 then error("missing buffer name") end
			if active_workspace == nil then error("connect to a workspace first") end
			buffers.attach(active_workspace, args.fargs[2], args.bang)
		elseif args.fargs[1] == "sync" then
			if active_workspace == nil then error("connect to a workspace first") end
			buffers.sync(active_workspace)
		elseif args.fargs[1] == "buffers" then
			if active_workspace == nil then error("connect to a workspace first") end
			workspace.buffers(active_workspace)
		elseif args.fargs[1] == "users" then
			if active_workspace == nil then error("connect to a workspace first") end
			workspace.users(active_workspace)
		elseif args.fargs[1] == "detach" then
			if #args.fargs < 2 then error("missing buffer name") end
			if active_workspace == nil then error("connect to a workspace first") end
			buffers.detach(active_workspace, args.fargs[2])
		elseif args.fargs[1] == "leave" then
			if active_workspace == nil then error("connect to a workspace first") end
			workspace.leave()
			active_workspace = nil
		end
	end,
	{
		nargs = "+",
		complete = function (lead, cmd, _pos)
			local args = vim.split(cmd, " ", { plain = true, trimempty = false })
			local stage = #args
			if stage == 1 then
				return { "MP" }
			elseif stage == 2 then
				return filter(lead, {'login', 'create', 'join', 'attach', 'sync', 'buffers', 'users', 'detach', 'leave'})
			elseif stage == 3 then
				if args[#args-1] == 'attach' or args[#args-1] == 'detach' then
					if active_workspace ~= nil then
						local ws = native.get_workspace(active_workspace)
						if ws ~= nil then
							return filter(lead, ws.filetree)
						end
					end
				end

				return {}
			end
		end,
	}
)

return {
	native = native,
	client = client,
	buffers = buffers,
	workspace = workspace,
	utils = require('codemp.utils'),
	async = require('codemp.async'),
}
