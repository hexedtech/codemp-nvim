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
	CODEMP.client:list_workspaces(true, false):and_then(function (owned)
		for _, ws in pairs(owned) do
			table.insert(new_list, {
				name = ws,
				owned = true,
			})
		end
		CODEMP.client:list_workspaces(false, true):and_then(function (invited)
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
				}) -- no need to await here
			else -- set ourselves "away" only once
				bufname = ""
				if once then
					local _ = controller:send({
						buffer = bufname,
						start_row = 0,
						start_col = 0,
						end_row = 1,
						end_col = 0,
					}) -- no need to await here
				end
				once = false
			end
			local oldbuf = buffers.users[CODEMP.client.username]
			buffers.users[CODEMP.client.username] = bufname
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
				if buffer_id ~= nil then
					local hi = user_hl[event.user].hi
					local event_finish_2 = event.sel.end_col -- TODO can't set the tuple field? need to copy out
					if event.sel.start_row == event.sel.end_row and event.sel.start_col == event.sel.end_col then
						-- vim can't draw 0-width cursors, so we always expand them to at least 1 width
						event_finish_2 = event.sel.end_col + 1
					end
					user_hl[event.user].mark = vim.api.nvim_buf_set_extmark(
						buffer_id,
						user_hl[event.user].ns,
						event.sel.start_row,
						event.sel.start_col,
						{
							id = user_hl[event.user].mark,
							end_row = event.sel.end_row,
							end_col = event_finish_2,
							hl_group = hi.bg,
							virt_text_pos = "right_align",
							sign_text = string.sub(event.user, 0, 1),
							sign_hl_group = hi.bg,
							virt_text_repeat_linebreak = true,
							priority = 1000,
							strict = false,
							virt_text = {
								{ " " .. event.user .. " ", hi.fg },
								{ " ", hi.bg },
							},
						}
					)
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
	CODEMP.client:join_workspace(workspace):and_then(function (ws)
		print(" >< joined workspace " .. ws.name)
		register_cursor_callback(ws.cursor, ws.name)
		register_cursor_handler(ws.cursor)
		CODEMP.workspace = ws
		for _, user in pairs(CODEMP.workspace:user_list()) do
			buffers.users[user] = ""
			user_hl[user] = {
				ns = vim.api.nvim_create_namespace("codemp-cursor-" .. user),
				hi = utils.color(user),
				pos = { 0, 0 },
				mark = nil,
			}
		end
		require('codemp.window').update()
		local ws_name = ws.name
		events_poller = utils.poller(
			function()
				if CODEMP.client == nil then return nil end
				local wspace = CODEMP.client:get_workspace(ws_name)
				if wspace == nil then return nil end
				return wspace:recv()
			end,
			function(event)
				if event.type == "leave" then
					if buffers.users[event.value] ~= nil then
						local buf_name = buffers.users[event.value]
						local buf_id = buffers.map_rev[buf_name]
						if buf_id ~= nil then
							vim.api.nvim_buf_clear_namespace(buf_id, user_hl[event.value].ns, 0, -1)
						end
						buffers.users[event.value] = nil
						user_hl[event.value] = nil
					end
				elseif event.type == "join" then
					buffers.users[event.value] = ""
					user_hl[event.value] = {
						ns = vim.api.nvim_create_namespace("codemp-cursor-" .. event.value),
						hi = utils.color(event.value),
						pos = { 0, 0 },
						mark = nil,
					}
				end
				require('codemp.window').update()
			end
		)
	end)
end

local function leave()
	local ws_name = CODEMP.workspace.name
	CODEMP.workspace.cursor:clear_callback()
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
