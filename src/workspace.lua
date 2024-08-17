local native = require('codemp.loader').load()

local utils = require('codemp.utils')
local buffers = require('codemp.buffers')
local state = require('codemp.state')
local window = require('codemp.window')

local user_hl = {}
local tree_buf = nil

local function register_cursor_callback(controller)
	vim.api.nvim_create_autocmd({"CursorMoved", "CursorMovedI", "ModeChanged"}, {
		group = vim.api.nvim_create_augroup("codemp-workspace-" .. state.workspace, { clear = true }),
		callback = function (_)
			local cur = utils.cursor.position()
			local buf = vim.api.nvim_get_current_buf()
			if buffers.map[buf] ~= nil then
				controller:send(buffers.map[buf], cur[1][1], cur[1][2], cur[2][1], cur[2][2])
			end
		end
	})
end

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

local function join(workspace)
	local ws = state.client:join_workspace(workspace):await()
	register_cursor_callback(ws.cursor)
	register_cursor_handler(ws.cursor)

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
end

local function leave()
	native.leave_workspace()
	print(" -- left workspace")
end

local function open_buffer_tree()
	local tree = state.client:get_workspace(state.workspace).filetree
	if tree_buf == nil then
		tree_buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_name(tree_buf, "codemp::" .. state.workspace)
		vim.api.nvim_set_option_value('buftype', 'nofile', { buf = tree_buf })
	end
	vim.api.nvim_set_option_value('modifiable', true, { buf = tree_buf })
	utils.buffer.set_content(tree_buf, "codemp::" .. state.workspace .. "\n\n- " .. vim.fn.join(tree, "\n- "))
	vim.api.nvim_set_option_value('modifiable', false, { buf = tree_buf })
	vim.api.nvim_open_win(tree_buf, true, {
		win = 0,
		split = 'left',
		width = 20,
	})
	vim.api.nvim_set_option_value('relativenumber', false, {})
	vim.api.nvim_set_option_value('number', false, {})
	vim.api.nvim_set_option_value('cursorlineopt', 'line', {})
end

return {
	join = join,
	leave = leave,
	map = user_hl,
	positions = user_buffer,
	open_buffer_tree = open_buffer_tree,
	buffer_tree = tree_buf,
}
