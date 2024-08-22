local state = require('codemp.state')
local buffers = require('codemp.buffers')
local workspace = require('codemp.workspace')
local utils = require('codemp.utils')
local window = require('codemp.window')

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

-- always available
local base_actions = {
	connect = function(host)
		if host == nil then host = 'http://codemp.alemi.dev:50053' end
		local user = vim.g.codemp_username or vim.fn.input("username > ", "")
		local password = vim.g.codemp_password or vim.fn.input("password > ", "")
		state.client = native.connect(host, user, password):await()
		print(" ++ connected to " .. host .. " as " .. user)
	end,
}

-- only available if state.client is not nil
local connected_actions = {
	id = function()
		print("> codemp::" .. state.client.id)
	end,

	toggle = function()
		window.toggle()
	end,

	join = function(ws)
		if ws == nil then error("missing workspace name") end
		state.workspace = ws
		workspace.join(ws)
		print(" >< joined workspace " .. ws)
	end,

	start = function(ws)
		if ws == nil then error("missing workspace name") end
		state.client:create_workspace(ws):await()
		print(" <> created workspace " .. ws)
	end,

	available = function()
		for _, ws in ipairs(state.client:list_workspaces(true, false):await()) do
			print(" ++ " .. ws)
		end
		for _, ws in ipairs(state.client:list_workspaces(false, true):await()) do
			print(" -- " .. ws)
		end
	end,

	invite = function(user)
		local ws
		if state.workspace ~= nil then
			ws = state.workspace
		else
			ws = vim.fn.input("workspace > ", "")
		end
		state.client:invite_to_workspace(ws, user):await()
		print(" ][ invited " .. user .. " to workspace " .. ws)
	end,

	disconnect = function()
		print(" xx disconnecting client " .. state.client.id)
		state.client = nil -- should drop and thus close everything
	end,
}

-- only available if state.workspace is not nil
local joined_actions = {
	create = function(path)
		if path == nil then error("missing buffer name") end
		buffers.create(path)
	end,

	share = function(path)
		if path == nil then
			local cwd = vim.fn.getcwd()
			local full_path = vim.fn.expand("%:p")
			path = string.gsub(full_path, cwd .. "/", "") 
		end
		if #path > 0 then
			local buf = vim.api.nvim_get_current_buf()
			buffers.create(path)
			local content = utils.buffer.get_content(buf)
			buffers.attach(path, true, content)
			window.update() -- TODO would be nice to do automatically inside
		else
			print(" !! empty path or open a file")
		end
	end,

	delete = function(path)
		if path == nil then error("missing buffer name") end
		buffers.delete(path)
	end,

	buffers = function()
		workspace.open_buffer_tree()
	end,

	sync = function()
		buffers.sync()
	end,

	attach = function(path, bang)
		if path == nil then error("missing buffer name") end
		buffers.attach(path, bang)
	end,

	detach = function(path)
		if path == nil then error("missing buffer name") end
		buffers.detach(path)
		window.update() -- TODO would be nice to do automatically inside
	end,

	leave = function(ws)
		if ws == nil then error("missing workspace to leave") end
		state.client:leave_workspace(ws)
	end,
}

vim.api.nvim_create_user_command(
	"MP",
	function (args)
		local action = args.fargs[1]
		local fn = nil

		if base_actions[action] ~= nil then
			fn = base_actions[action]
		end

		if state.client ~= nil and connected_actions[action] ~= nil then
			fn = connected_actions[action]
		end

		if state.workspace ~= nil and joined_actions[action] ~= nil then
			fn = joined_actions[action]
		end

		if fn ~= nil then
			fn(args.fargs[2], args.bang)
		else
			print(" ?? invalid command")
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
				local suggestions = {}
				local n = 0
				for sugg, _ in pairs(base_actions) do
					n = n + 1
					suggestions[n] = sugg
				end
				if state.client ~= nil then
					for sugg, _ in pairs(connected_actions) do
						n = n + 1
						suggestions[n] = sugg
					end
				end
				if state.workspace ~= nil then
					for sugg, _ in pairs(joined_actions) do
						n = n + 1
						suggestions[n] = sugg
					end
				end
				return filter(lead, suggestions)
			elseif stage == 3 then
				if args[#args-1] == 'attach' or args[#args-1] == 'detach' then
					if state.client ~= nil and state.workspace ~= nil then
						local ws = state.client:get_workspace(state.workspace)
						if ws ~= nil then
							return filter(lead, ws:filetree())
						end
					end
				end

				return {}
			end
		end,
	}
)
