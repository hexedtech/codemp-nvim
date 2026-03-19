local utils = require('codemp.utils')
local buffers = require('codemp.buffers')
local enums = require("codemp.enums")

---@class UserHighlight
---@field ns integer namespace to use for this user
---@field hi HighlightPair color for user to use
---@field mark integer[] extmark id
---@field pos [integer, integer] cursor start position of this user

---@type table<string, UserHighlight>
local user_hl = {}

local function fetch_workspaces_list()
	local new_list = {}
	CODEMP.client:fetch_owned_workspaces():and_then(function (owned)
		for _, ws in pairs(owned) do
			table.insert(new_list, ws)
		end
		CODEMP.client:fetch_joined_workspaces():and_then(function (invited)
			for _, ws in pairs(invited) do
				table.insert(new_list, ws)
			end
			CODEMP.available = new_list
			require('codemp.window').update()
		end)
	end)
end

---@type CursorPosition
local last_jump = { start = { row = 0, col = 0 }, finish = { row = 0, col = 0 } }
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
					cursors = {
						{
							start = {
								row = cur[1][1],
								col = cur[1][2],
							},
							finish = {
								row = cur[2][1],
								col = cur[2][2],
							},
						},
					},
				}) -- no need to await here
			else -- set ourselves "away" only once
				bufname = ""
				if once then
					local _ = controller:send({
						buffer = bufname,
						cursors = {
							{
								start = {
									row = 0,
									col = 0,
								},
								finish = {
									row = 0,
									col = 0,
								},
							},
						}
					}) -- no need to await here
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
						mark = { },
						pos = { 0, 0 },
					}
				end
				if #event.position.cursors >= 1 then
					user_hl[user].pos = { event.position.cursors[1].start.row, event.position.cursors[1].start.col }
				end
				local old_buffer = buffers.users[event.user]
				if old_buffer ~= nil then
					local old_buffer_id = buffers.map_rev[old_buffer]
					if old_buffer_id ~= nil then
						vim.api.nvim_buf_clear_namespace(old_buffer_id, user_hl[event.user].ns, 0, -1)
					end
				end
				buffers.users[event.user] = event.position.buffer
				local buffer_id = buffers.map_rev[event.position.buffer]
				if buffer_id ~= nil then
					for _mark_idx, extmark in ipairs(user_hl[event.user].mark) do
						vim.api.nvim_buf_del_extmark(buffer_id, user_hl[event.user].ns, extmark)
					end
					for sel_idx, sel in ipairs(event.position.cursors) do
						local hi = user_hl[event.user].hi
						local sel_end_col_2 = sel.finish.col -- TODO can't set the tuple field? need to copy out
						if sel.start.row == sel.finish.row and sel.start.col == sel.finish.col then
							-- vim can't draw 0-width cursors, so we always expand them to at least 1 width
							sel_end_col_2 = sel.finish.col + 1
						end
						table.insert(
							user_hl[event.user].mark,
							vim.api.nvim_buf_set_extmark(
								buffer_id,
								user_hl[event.user].ns,
								sel.start.row,
								sel.start.col,
								{
									id = nil, -- create new one
									end_row = sel.finish.row,
									end_col = sel_end_col_2,
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
						)
					end
				end
				if old_buffer ~= event.position.buffer then
					require('codemp.window').update() -- redraw user positions
				end
				if CODEMP.following ~= nil and CODEMP.following == event.user then
					local buf_id = buffers.map_rev[event.position.buffer]
					if buf_id ~= nil then
						local win = vim.api.nvim_get_current_win()
						local curr_buf = vim.api.nvim_get_current_buf()
						CODEMP.ignore_following_action = true
						if curr_buf ~= buf_id then
							vim.api.nvim_win_set_buf(win, buf_id)
						end
						if #event.position.cursors > 1 then
							-- keep centered the cursor end that is currently being moved, but prefer start
							if event.position.cursors[1].start.row == last_jump.start.row and event.position.cursors[1].start.col == last_jump.start.col then
								vim.api.nvim_win_set_cursor(win, { event.position.cursors[1].finish.row + 1, event.position.cursors[1].finish.col })
							else
								vim.api.nvim_win_set_cursor(win, { event.position.cursors[1].start.row + 1, event.position.cursors[1].start.col })
							end
							last_jump = event.position.cursors[1]
						end
					end
				end
			end
		end
	end))
	controller:callback(function (_controller) async:send() end)
end

local events_poller = nil

---@param user string user owning this workspace
---@param workspace string workspace name to join
---join a workspace and register event handlers
local function join(user, workspace)
	print(" <> joining workspace " .. user .. '/' .. workspace .. " ...")
	CODEMP.client:attach_workspace(user, workspace):and_then(function (ws)
		print(" >< joined workspace " .. utils.wsid(ws:id()))
		register_cursor_callback(ws:cursor(), utils.wsid(ws:id()))
		register_cursor_handler(ws:cursor())
		CODEMP.workspace = ws
		for _, u in pairs(CODEMP.workspace:user_list()) do
			buffers.users[u.name] = ""
			user_hl[u.name] = {
				ns = vim.api.nvim_create_namespace("codemp-cursor-" .. u.name),
				hi = utils.color(u.name),
				pos = { 0, 0 },
				mark = { },
			}
		end
		require('codemp.window').update()
		local ws_id = ws:id()
		events_poller = utils.poller(
			function()
				if CODEMP.client == nil then return nil end
				-- TODO can we just pass workspace in?
				local wspace = CODEMP.client:get_workspace(ws_id.user, ws_id.workspace)
				if wspace == nil then return nil end
				return wspace:recv()
			end,
			---@param event WorkspaceEvent
			function(event)
				if event.kind == enums.WorkspaceEventKind.UserLeaveWorkspace then
					if buffers.users[event.user] ~= nil then
						local buf_name = buffers.map[event.user]
						local buf_id = buffers.map_rev[buf_name]
						if buf_id ~= nil then
							vim.api.nvim_buf_clear_namespace(buf_id, user_hl[event.user].ns, 0, -1)
						end
						buffers.users[event.user] = nil
						user_hl[event.user] = nil
					end
				elseif event.kind == enums.WorkspaceEventKind.UserJoinWorkspace then
					buffers.users[event.user] = ""
					user_hl[event.user] = {
						ns = vim.api.nvim_create_namespace("codemp-cursor-" .. event.user),
						hi = utils.color(event.user),
						pos = { 0, 0 },
						mark = { },
					}
				elseif event.kind == enums.WorkspaceEventKind.BufferDelete then
					if buffers.map_rev[event.path] ~= nil then
						buffers.detach(event.path)
					end
				end
				require('codemp.window').update()
			end
		)
	end)
end

local function leave()
	local ws_id = CODEMP.workspace:id()
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

	-- TODO codemp disconnects when all references to its objects are dropped. since it
	-- hands out Arc<> of things, all references still not garbage collected in Lua will
	-- prevent it from disconnecting. while running a full cycle may be a bit slow, this
	-- only happens when manually requested, and it's not like the extra garbage collection
	-- is an effort for nothing... still it would be more elegant to not need this!!
	collectgarbage("collect")
	if not CODEMP.client:leave_workspace(ws_id.user, ws_id.workspace) then
		print(" -! left workspace " .. ws_id.workspace .. " but there are leftover references")
	else
		print(" -- left workspace " .. ws_id.workspace)
	end

	require('codemp.window').update()
end

return {
	join = join,
	leave = leave,
	map = user_hl,
	list = fetch_workspaces_list,
}
