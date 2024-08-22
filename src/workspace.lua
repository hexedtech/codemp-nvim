local utils = require('codemp.utils')
local buffers = require('codemp.buffers')
local state = require('codemp.state')
local window = require('codemp.window')

local user_hl = {}

---@param controller CursorController
local function register_cursor_callback(controller)
	vim.api.nvim_create_autocmd({"CursorMoved", "CursorMovedI", "ModeChanged"}, {
		group = vim.api.nvim_create_augroup("codemp-workspace-" .. state.workspace, { clear = true }),
		callback = function (_)
			local cur = utils.cursor.position()
			local buf = vim.api.nvim_get_current_buf()
			if buffers.map[buf] ~= nil then
				local _ = controller:send(buffers.map[buf], cur[1][1], cur[1][2], cur[2][1], cur[2][2]) -- no need to await here
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
			if user_hl[event.user] == nil then
				user_hl[event.user] = {
					ns = vim.api.nvim_create_namespace("codemp-cursor-" .. event.user),
					hi = utils.color(event.user),
				}
			end
			local old_buffer = buffers.users[event.user]
			if old_buffer ~= nil then
				local old_buffer_id = buffers.map_rev[old_buffer]
				if old_buffer_id ~= nil then
					vim.api.nvim_buf_clear_namespace(old_buffer_id, user_hl[event.user].ns, 0, -1)
				end
			end
			buffers.users[event.user] = event.buffer
			local buffer_id = buffers.map_rev[event.buffer]
			if buffer_id ~= nil then
				utils.multiline_highlight(
					buffer_id,
					user_hl[event.user].ns,
					user_hl[event.user].hi,
					event.start,
					event.finish
				)
			end
			if old_buffer ~= event.buffer then
				window.update() -- redraw user positions
			end
		end
	end))
	controller:callback(function (_controller) async:send() end)
end

---@param workspace string workspace name to join
---@return Workspace
---join a workspace and register event handlers
local function join(workspace)
	local ws = state.client:join_workspace(workspace):await()
	register_cursor_callback(ws.cursor)
	register_cursor_handler(ws.cursor)

	-- TODO this is temporary and ad-hoc
	ws:callback(function (event)
		if event.type == "leave" then
			if buffers.users[event.value] ~= nil then
				vim.schedule(function ()
					vim.api.nvim_buf_clear_namespace(buffers.users[event.value], user_hl[event.value].ns, 0, -1)
					buffers.users[event.value] = nil
					user_hl[event.value] = nil
				end)
			end
		end
		vim.schedule(function() window.update() end)
	end)
	window.update()

	return ws
end

local function leave()
	state.client:leave_workspace(state.workspace.name)
	print(" -- left workspace")
end

return {
	join = join,
	leave = leave,
	map = user_hl,
}
