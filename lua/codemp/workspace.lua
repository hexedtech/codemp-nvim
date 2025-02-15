local utils = require('codemp.utils')
local buffers = require('codemp.buffers')

---@class UserHighlight
---@field ns integer namespace to use for this user
---@field hi HighlightPair color for user to use
---@field mark integer | nil extmark id
---@field pos [integer, integer] cursor start position of this user

---@type table<string, UserHighlight>
local user_hl = {}

local function fetch_workspaces_list()
	local new_list = {}
	CODEMP.client:fetch_owned_workspaces():and_then(function (owned)
		for _, ws in pairs(owned) do
			table.insert(new_list, {
				name = ws,
				owned = true,
			})
		end
		CODEMP.client:fetch_joined_workspaces():and_then(function (invited)
			for _, ws in pairs(invited) do
				table.insert(new_list, {
					name = ws,
					owned = false,
				})
			end
			CODEMP.available = new_list
			require('codemp.window').update()
		end)
	end)
end

local last_jump = { 0, 0 }
local workspace_callback_group = nil

---@param controller CursorController
---@param name string
local function register_cursor_callback(controller, name)
	local once = true
	workspace_callback_group = vim.api.nvim_create_augroup("codemp-workspace-" .. name, { clear = true })
	vim.api.nvim_create_autocmd({"CursorMoved", "CursorMovedI", "ModeChanged"}, {
		group = workspace_callback_group,
		callback = function (_ev)
			if CODEMP.ignore_following_action then
				CODEMP.ignore_following_action = false
				return
			elseif CODEMP.following ~= nil then
				print(" / / unfollowing " .. CODEMP.following)
				CODEMP.following = nil
				require('codemp.window').update()
			end
			local cur = utils.cursor.position()
			local buf = vim.api.nvim_get_current_buf()
			local bufname
			if buffers.map[buf] ~= nil then
				bufname = buffers.map[buf]
				once = true
				local _ = controller:send({
					buffer = bufname,
					start_row = cur[1][1],
					start_col = cur[1][2],
					end_row = cur[2][1],
					end_col = cur[2][2],
				})
			else -- set ourselves "away" only once
				bufname = ""
				if once then
					controller:send({
						buffer = bufname,
						start_row = 0,
						start_col = 0,
						end_row = 1,
						end_col = 0,
					})
				end
				once = false
			end
			local oldbuf = buffers.users[CODEMP.client:current_user().name]
			buffers.users[CODEMP.client:current_user().name] = bufname
			if oldbuf ~= bufname then
				require('codemp.window').update()
			end
		end
	})
end

---@param controller CursorController
local function register_cursor_handler(controller)
	local async = vim.loop.new_async(vim.schedule_wrap(function ()
		while true do
			local event = controller:try_recv():await()
			if event == nil then break end
			local user = event.user -- do it on separate line so language server understands that it wont be nil
			if user ~= nil then
				if user_hl[user] == nil then
					user_hl[user] = {
						ns = vim.api.nvim_create_namespace("codemp-cursor-" .. event.user),
						hi = utils.color(event.user),
						mark = nil,
						pos = { 0, 0 },
					}
				end
				user_hl[user].pos = { event.sel.start_row, event.sel.start_col }
				local old_buffer = buffers.users[event.user]
				if old_buffer ~= nil then
					local old_buffer_id = buffers.map_rev[old_buffer]
					if old_buffer_id ~= nil then
						vim.api.nvim_buf_clear_namespace(old_buffer_id, user_hl[event.user].ns, 0, -1)
					end
				end
				buffers.users[event.user] = event.sel.buffer
				local buffer_id = buffers.map_rev[event.sel.buffer]
				buffers.cursors[event.user] = event
				if buffer_id ~= nil then
					local hl = user_hl[event.user]
					user_hl[event.user].mark = utils.cursor.draw(event, buffer_id, hl.ns, hl.mark, hl.hi)
				end
				if old_buffer ~= event.sel.buffer then
					require('codemp.window').update() -- redraw user positions
				end
				if CODEMP.following ~= nil and CODEMP.following == event.user then
					local buf_id = buffers.map_rev[event.sel.buffer]
					if buf_id ~= nil then
						local win = vim.api.nvim_get_current_win()
						local curr_buf = vim.api.nvim_get_current_buf()
						CODEMP.ignore_following_action = true
						if curr_buf ~= buf_id then
							vim.api.nvim_win_set_buf(win, buf_id)
						end
						-- keep centered the cursor end that is currently being moved, but prefer start
						if event.sel.start_row == last_jump[1] and event.sel.start_col == last_jump[2] then
							vim.api.nvim_win_set_cursor(win, { event.sel.end_row + 1, event.sel.end_col })
						else
							vim.api.nvim_win_set_cursor(win, { event.sel.start_row + 1, event.sel.start_col })
						end
						last_jump = { event.sel.start_row, event.sel.start_col }
					end
				end
			end
		end
	end))
	controller:callback(function (_controller) async:send() end)
end

local events_poller = nil

---@param workspace string workspace name to join
---join a workspace and register event handlers
local function join(workspace)
	print(" <> joining workspace " .. workspace .. " ...")
	CODEMP.client:attach_workspace(workspace):and_then(function (ws)
		print(" >< joined workspace " .. ws:id())
		register_cursor_callback(ws:cursor(), ws:id())
		register_cursor_handler(ws:cursor())
		CODEMP.workspace = ws
		vim.schedule(function ()
			for _, user in pairs(CODEMP.workspace:user_list()) do
				buffers.users[user.name] = ""
				user_hl[user.name] = {
					ns = vim.api.nvim_create_namespace("codemp-cursor-" .. user.name),
					hi = utils.color(user.name),
					pos = { 0, 0 },
					mark = nil,
				}
			end
			require('codemp.window').update()
		end)
		local async = vim.uv.new_async(function ()
			while true do
				local event = ws:try_recv():await()
				if event == nil then break end
				if event.type == "UserLeave" then
					if buffers.users[event.name] ~= nil then
						vim.schedule(function()
							local buf_name = buffers.users[event.name]
							local buf_id = buffers.map_rev[buf_name]
							if buf_id ~= nil then
								vim.api.nvim_buf_clear_namespace(buf_id, user_hl[event.name].ns, 0, -1)
							end
							buffers.users[event.name] = nil
							user_hl[event.name] = nil
						end)
					end
				elseif event.type == "UserJoin" then
					vim.schedule(function()
						buffers.users[event.name] = ""
						user_hl[event.name] = {
							ns = vim.api.nvim_create_namespace("codemp-cursor-" .. event.name),
							hi = utils.color(event.name),
							pos = { 0, 0 },
							mark = nil,
						}
					end)
				end
			end
			vim.schedule(function () require('codemp.window').update() end)
		end)
		ws:callback(function(_) async:send() end)
	end)
end

local function leave()
	local ws_name = CODEMP.workspace:id()
	CODEMP.workspace:cursor():clear_callback()
	vim.api.nvim_clear_autocmds({ group = workspace_callback_group })
	for id, name in pairs(buffers.map) do
		CODEMP.workspace:get_buffer(name):clear_callback()
		buffers.map[id] = nil
		buffers.map_rev[name] = nil
	end
	for user, _buf in pairs(buffers.users) do
		buffers.users[user] = nil
	end
	CODEMP.workspace = nil
	if events_poller ~= nil then
		events_poller:stop()
		events_poller = nil
	end
	if not CODEMP.client:leave_workspace(ws_name) then
		collectgarbage("collect")
		-- TODO codemp disconnects when all references to its objects are dropped. since it
		-- hands out Arc<> of things, all references still not garbage collected in Lua will
		-- prevent it from disconnecting. while running a full cycle may be a bit slow, this
		-- only happens when manually requested, and it's not like the extra garbage collection
		-- is an effort for nothing... still it would be more elegant to not need this!!
	end
	print(" -- left workspace " .. ws_name)
	require('codemp.window').update()
end

return {
	join = join,
	leave = leave,
	map = user_hl,
	list = fetch_workspaces_list,
}
