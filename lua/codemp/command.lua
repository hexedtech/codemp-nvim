local buffers = require('codemp.buffers')
local workspace = require('codemp.workspace')
local utils = require('codemp.utils')
local client = require("codemp.client")

local function filter(needle, haystack, getter)
	local hints = {}
	for _, opt in pairs(haystack) do
		local hay = opt
		if getter ~= nil then
			hay = getter(opt)
		end
		if vim.startswith(hay, needle) then
			table.insert(hints, hay)
		end
	end
	return hints
end

-- always available
local base_actions = {
	toggle = function()
		require('codemp.window').toggle()
	end,

	connect = function()
		client.connect()
	end,
}

-- only available if state.client is not nil
local connected_actions = {
	id = function()
		print("> codemp::" .. CODEMP.client.id)
	end,

	join = function(ws)
		if ws == nil then
			local opts = { prompt = "Select workspace to join:", format_item = function (x) return x.name end }
			return vim.ui.select(CODEMP.available, opts, function (choice)
				if choice == nil then return end -- action canceled by user
				workspace.join(CODEMP.available[choice].name)
			end)
		else
			workspace.join(ws)
		end
	end,

	start = function(ws)
		if ws == nil then error("missing workspace name") end
		CODEMP.client:create_workspace(ws):and_then(function ()
			print(" <> created workspace " .. ws)
			workspace.list()
		end)
	end,

	available = function()
		CODEMP.available = {}
		for _, ws in ipairs(CODEMP.client:list_workspaces(true, false):await()) do
			print(" ++ " .. ws)
			table.insert(CODEMP.available, ws)
		end
		for _, ws in ipairs(CODEMP.client:list_workspaces(false, true):await()) do
			print(" -- " .. ws)
			table.insert(CODEMP.available, ws)
		end
		require('codemp.window').update()
	end,

	invite = function(user)
		local ws
		if CODEMP.workspace ~= nil then
			ws = CODEMP.workspace.name
		else
			ws = vim.fn.input("workspace > ", "")
		end
		CODEMP.client:invite_to_workspace(ws, user):and_then(function ()
			print(" :: invited " .. user .. " to workspace " .. ws)
		end)
	end,

	disconnect = function()
		if CODEMP.workspace ~= nil then
			print(" xx leaving workspace " .. CODEMP.workspace.name)
			workspace.leave()
		end
		print(" xx disconnecting client " .. CODEMP.client.id)
		CODEMP.client = nil -- should drop and thus close everything
		collectgarbage("collect") -- make sure we drop
		require('codemp.window').update()
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
			path = string.gsub(full_path, cwd .. utils.sep(), "")
			path = string.gsub(path, '\\', '/')
		end
		if #path > 0 then
			local buf = vim.api.nvim_get_current_buf()
			if not bang then buffers.create(path) end
			local content = utils.buffer.get_content(buf)
			buffers.attach(path, { buffer = buf, content = content, skip_exists_check = true })
			require('codemp.window').update() -- TODO would be nice to do automatically inside
		else
			print(" !! empty path or open a file")
		end
	end,

	delete = function(path)
		if path == nil then error("missing buffer name") end
		CODEMP.workspace:delete(path):and_then(function()
			print(" xx  deleted buffer " .. path)
		end)
	end,

	buffers = function()
		for _, buf in ipairs(CODEMP.workspace:filetree()) do
			if buffers.map_rev[buf] ~= nil then
				print(" +- " .. buf)
			else
				print(" -- " .. buf)
			end
		end
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
			buffers.attach(p, { buffer = buffer })
		end
		if path == nil then
			local filetree = CODEMP.workspace:filetree(nil, false)
			return vim.ui.select(filetree, { prompt = "Select buffer to attach to:" }, function (choice)
				if choice == nil then return end -- action canceled by user
				doit(filetree[choice])
			end)
		else
			doit(path)
		end
	end,

	detach = function(path)
		if path == nil then
			local bufid = vim.api.nvim_get_current_buf()
			path = buffers.map[bufid]
			if path == nil then	error("missing buffer name") end
		end
		buffers.detach(path)
		require('codemp.window').update() -- TODO would be nice to do automatically inside
	end,

	leave = function()
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

		if CODEMP.client ~= nil and connected_actions[action] ~= nil then
			fn = connected_actions[action]
		end

		if CODEMP.workspace ~= nil and joined_actions[action] ~= nil then
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
				if CODEMP.client ~= nil then
					for sugg, _ in pairs(connected_actions) do
						n = n + 1
						suggestions[n] = sugg
					end
				end
				if CODEMP.workspace ~= nil then
					for sugg, _ in pairs(joined_actions) do
						n = n + 1
						suggestions[n] = sugg
					end
				end
				return filter(lead, suggestions)
			elseif stage == 3 then
				local last_arg = args[#args-1]
				if last_arg == 'attach' or last_arg == 'detach' then
					if CODEMP.client ~= nil and CODEMP.workspace ~= nil then
						local choices
						if last_arg == "attach" then
							choices = CODEMP.workspace:filetree()
						elseif last_arg == "detach" then
							choices = CODEMP.workspace.active_buffers
						end
						return filter(lead, choices)
					end
				elseif args[#args-1] == 'join' then
					return filter(lead, CODEMP.available, function(ws) return ws.name end)
				end

				return {}
			end
		end,
	}
)
