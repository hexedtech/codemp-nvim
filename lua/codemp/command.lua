local session = require('codemp.session')
local buffers = require('codemp.buffers')
local workspace = require('codemp.workspace')
local utils = require('codemp.utils')
local client = require("codemp.client")

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
	toggle = function()
		require('codemp.window').toggle()
	end,

	connect = function(host)
		client.connect(host)
	end,
}

-- only available if state.client is not nil
local connected_actions = {
	id = function()
		print("> codemp::" .. session.client.id)
	end,

	join = function(ws)
		if ws == nil then
			local opts = { prompt = "Select workspace to join:", format_item = function (x) return x.name end }
			return vim.ui.select(session.available, opts, function (choice)
				if choice == nil then return end -- action canceled by user
				workspace.join(session.available[choice].name)
			end)
		else
			workspace.join(ws)
		end
	end,

	start = function(ws)
		if ws == nil then error("missing workspace name") end
		session.client:create_workspace(ws):await()
		vim.schedule(function () workspace.list() end)
		print(" <> created workspace " .. ws)
	end,

	available = function()
		for _, ws in ipairs(session.client:list_workspaces(true, false):await()) do
			print(" ++ " .. ws)
		end
		for _, ws in ipairs(session.client:list_workspaces(false, true):await()) do
			print(" -- " .. ws)
		end
	end,

	invite = function(user)
		local ws
		if session.workspace ~= nil then
			ws = session.workspace
		else
			ws = vim.fn.input("workspace > ", "")
		end
		session.client:invite_to_workspace(ws, user):await()
		print(" ][ invited " .. user .. " to workspace " .. ws)
	end,

	disconnect = function()
		print(" xx disconnecting client " .. session.client.id)
		session.client = nil -- should drop and thus close everything
	end,
}

-- only available if state.workspace is not nil
local joined_actions = {
	create = function(path)
		if path == nil then error("missing buffer name") end
		buffers.create(path)
	end,

	share = function(path, bang)
		if path == nil then
			local cwd = vim.fn.getcwd()
			local full_path = vim.fn.expand("%:p")
			path = string.gsub(full_path, cwd .. "/", "")
		end
		if #path > 0 then
			local buf = vim.api.nvim_get_current_buf()
			if not bang then buffers.create(path) end
			local content = utils.buffer.get_content(buf)
			buffers.attach(path, buf, content)
			require('codemp.window').update() -- TODO would be nice to do automatically inside
		else
			print(" !! empty path or open a file")
		end
	end,

	delete = function(path)
		if path == nil then error("missing buffer name") end
		session.workspace:delete(path):await()
		print(" xx  deleted buffer " .. path)
	end,

	buffers = function()
		workspace.open_buffer_tree()
	end,

	sync = function()
		buffers.sync()
	end,

	attach = function(path, bang)
		local function doit(p)
			local buffer = nil
			if bang then
				buffer = vim.api.nvim_get_current_buf()
			else
				buffer = vim.api.nvim_create_buf(true, false)
				vim.api.nvim_set_current_buf(buffer)
			end
			buffers.attach(p, buffer)
		end
		if path == nil then
			local filetree = session.workspace:filetree(nil, false)
			return vim.ui.select(filetree, { prompt = "Select buffer to attach to:" }, function (choice)
				if choice == nil then return end -- action canceled by user
				doit(filetree[choice])
			end)
		else
			doit(path)
		end
	end,

	detach = function(path)
		if path == nil then error("missing buffer name") end
		buffers.detach(path)
		require('codemp.window').update() -- TODO would be nice to do automatically inside
	end,

	leave = function(ws)
		if ws == nil then error("missing workspace to leave") end
		workspace.leave()
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

		if session.client ~= nil and connected_actions[action] ~= nil then
			fn = connected_actions[action]
		end

		if session.workspace ~= nil and joined_actions[action] ~= nil then
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
				if session.client ~= nil then
					for sugg, _ in pairs(connected_actions) do
						n = n + 1
						suggestions[n] = sugg
					end
				end
				if session.workspace ~= nil then
					for sugg, _ in pairs(joined_actions) do
						n = n + 1
						suggestions[n] = sugg
					end
				end
				return filter(lead, suggestions)
			elseif stage == 3 then
				if args[#args-1] == 'attach' or args[#args-1] == 'detach' then
					if session.client ~= nil and session.workspace ~= nil then
						if session.workspace ~= nil then
							return filter(lead, session.workspace:filetree())
						end
					end
				end

				return {}
			end
		end,
	}
)
