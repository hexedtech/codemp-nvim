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
	client = {
		id = function()
			print("> codemp::" .. CODEMP.client:current_user().id)
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

		create = function(ws)
			if ws == nil then error("missing workspace name") end
			CODEMP.client:create_workspace(ws):and_then(function ()
				print(" <> created workspace " .. ws)
				workspace.list()
			end)
		end,

		available = function()
			CODEMP.available = {}
			for _, ws in ipairs(CODEMP.client:fetch_owned_workspaces():await()) do
				print(" ++ " .. ws)
				table.insert(CODEMP.available, ws)
			end
			for _, ws in ipairs(CODEMP.client:fetch_joined_workspaces():await()) do
				print(" -- " .. ws)
				table.insert(CODEMP.available, ws)
			end
			require('codemp.window').update()
		end,

		invite = function(user)
			local ws
			if CODEMP.workspace ~= nil then
				ws = CODEMP.workspace:id()
			else
				ws = vim.fn.input("workspace > ", "")
			end
			CODEMP.client:invite_to_workspace(ws, user):and_then(function ()
				print(" :: invited " .. user .. " to workspace " .. ws)
			end)
		end,

		disconnect = function()
			if CODEMP.workspace ~= nil then
				print(" xx leaving workspace " .. CODEMP.workspace:id())
				workspace.leave()
			end
			print(" xx disconnecting client " .. CODEMP.client:current_user().id)
			CODEMP.client = nil -- should drop and thus close everything
			collectgarbage("collect") -- make sure we drop
			require('codemp.window').update()
		end,
	},
}

-- only available if state.workspace is not nil
local joined_actions = {
	workspace = {
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
				if not bang then
					CODEMP.workspace:create_buffer(path):await()
				end
				local content = utils.buffer.get_content(buf)
				buffers.attach(path, { buffer = buf, content = content, skip_exists_check = true })
				require('codemp.window').update() -- TODO would be nice to do automatically inside
			else
				print(" !! empty path or open a file")
			end
		end,

		delete = function(path)
			if path == nil then error("missing buffer name") end
			CODEMP.workspace:delete_buffer(path):and_then(function()
				print(" xx  deleted buffer " .. path)
			end)
		end,

		buffers = function()
			for _, buf in ipairs(CODEMP.workspace:search_buffers()) do
				if buffers.map_rev[buf] ~= nil then
					print(" +- " .. buf)
				else
					print(" -- " .. buf)
				end
			end
		end,

		leave = function()
			workspace.leave()
		end,
	},
	buffer = {
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
				local filetree = CODEMP.workspace:search_buffers()
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

	}
}

local function available_actions()
	local out = {}
	for key, value in pairs(base_actions) do
		out[key] = value
	end

	if CODEMP.client ~= nil then
		for key, value in pairs(connected_actions) do
			out[key] = value
		end
	end

	if CODEMP.workspace ~= nil then
		for key, value in pairs(joined_actions) do
			out[key] = value
		end
	end

	if CODEMP.workspace ~= nil and #CODEMP.workspace:active_buffers() > 0 then
		for key, value in pairs(joined_actions) do
			out[key] = value
		end
	end
	return out
end

local function recursive_action(actions, keys, idx)
	local next = actions[keys[idx]]
	if type(next) == 'table' and #keys > idx then
		local new_next, new_idx = recursive_action(next, keys, idx + 1)
		return new_next, new_idx
	end
	return next, idx
end

vim.api.nvim_create_user_command(
	"MP",
	function (args)
		local available = available_actions()
		local fn, idx = recursive_action(available, args.fargs, 1)

		if fn == nil then
			print(" ?? invalid command")
		elseif type(fn) == 'table' then
			print(" ?? incomplete command")
		else
			local fn_args = {}
			if idx < #args.fargs then
				for i = idx + 1, #args.fargs do
					fn_args[#fn_args+1] = args.fargs[i]
				end
			end
			fn(args.bang, table.unpack(fn_args))
		end
	end,
	{
		bang = true,
		desc = "codeMP main command",
		nargs = "+",
		complete = function (lead, cmd, _pos)
			local suggestions = {}
			local args = vim.split(cmd, " ", { plain = true, trimempty = false })
			local available = available_actions()
			local filtered, idx = recursive_action(available, args, 1)
			if type(filtered) == 'table' then
				for key, _val in pairs(filtered) do
					suggestions[#suggestions+1] = key
				end
			end
			-- TODO special cases!! example: `buffer attach` should offer buffer names
			return filter(lead, suggestions)
		end,
	}
)
