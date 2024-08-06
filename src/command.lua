local client = require('codemp.client')
local buffers = require('codemp.buffers')
local workspace = require('codemp.workspace')
local utils = require('codemp.utils')

local native = require('codemp.loader').load()

local function filter(needle, haystack)
	local hints = {}
	for _, opt in pairs(haystack) do
		if vim.startswith(opt, needle) then
			table.insert(hints, opt)
		end
	end
	return hints
end

local tree_buf = nil;

vim.api.nvim_create_user_command(
	"MP",
	function (args)
		if args.fargs[1] == "login" then
			client.login(args.fargs[2], args.fargs[3], args.fargs[4])
		elseif args.fargs[1] == "create" then
			if #args.fargs < 2 then error("missing buffer name") end
			if client.workspace == nil then error("connect to a workspace first") end
			buffers.create(client.workspace, args.fargs[2])
		elseif args.fargs[1] == "join" then
			if #args.fargs < 2 then error("missing workspace name") end
			client.workspace = args.fargs[2]
			workspace.join(client.workspace)
		elseif args.fargs[1] == "attach" then
			if #args.fargs < 2 then error("missing buffer name") end
			if client.workspace == nil then error("connect to a workspace first") end
			buffers.attach(client.workspace, args.fargs[2], args.bang)
		elseif args.fargs[1] == "sync" then
			if client.workspace == nil then error("connect to a workspace first") end
			buffers.sync(client.workspace)
		elseif args.fargs[1] == "buffers" then
			if client.workspace == nil then error("connect to a workspace first") end
			local tree = workspace.buffers(client.workspace)
			if tree_buf == nil then
				tree_buf = vim.api.nvim_create_buf(false, true)
				vim.api.nvim_buf_set_name(tree_buf, "codemp::" .. client.workspace)
				vim.api.nvim_set_option_value('buftype', 'nofile', { buf = tree_buf })
				vim.api.nvim_set_option_value('nomodifiable', true, { buf = tree_buf })
			end
			utils.buffer.set_content(tree_buf, "> " .. vim.fn.join(tree, "\n> "))
			vim.api.nvim_open_win(tree_buf, true, {
				win = 0,
				split = 'left',
				width = 20,
			})
		-- elseif args.fargs[1] == "users" then
		-- 	if client.workspace == nil then error("connect to a workspace first") end
		-- 	workspace.users(client.workspace)
		-- elseif args.fargs[1] == "detach" then
		-- 	if #args.fargs < 2 then error("missing buffer name") end
		-- 	if client.workspace == nil then error("connect to a workspace first") end
		-- 	buffers.detach(client.workspace, args.fargs[2])
		-- elseif args.fargs[1] == "leave" then
		-- 	if client.workspace == nil then error("connect to a workspace first") end
		-- 	workspace.leave()
		-- 	client.workspace = nil
		end
		if args.bang then
			print("pls stop shouting :'c")
		end
	end,
	{
		bang = true,
		desc = "codeMP main command",
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
					if client.workspace ~= nil then
						local ws = native.get_workspace(client.workspace)
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
