local state = require('codemp.state')
local utils = require('codemp.utils')
local buffers = require('codemp.buffers')

local prev_window = nil
local window_id = nil
local buffer_id = nil
local ns = vim.api.nvim_create_namespace("codemp-window")

local function open_buffer_under_cursor()
	if window_id == nil then return end
	if buffer_id == nil then return end
	local cursor = vim.api.nvim_win_get_cursor(window_id)
	local line = vim.api.nvim_buf_get_lines(buffer_id, cursor[1]-1, cursor[1], true)
	if not vim.startswith(line[1], " |- ") then return end
	local path = string.gsub(line[1], " |%- ", "")
	if prev_window ~= nil then
		vim.api.nvim_set_current_win(prev_window)
	end
	if buffers.map_rev[path] ~= nil then
		vim.api.nvim_set_current_buf(buffers.map_rev[path])
	else
		buffers.attach(path)
	end
end

local function init_window()
	buffer_id = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_name(buffer_id, "codemp::window")
	vim.api.nvim_set_option_value('buftype', 'nofile', { buf = buffer_id })
	utils.buffer.set_content(buffer_id, ">  codemp")
	vim.api.nvim_set_option_value('modifiable', false, { buf = buffer_id })
	vim.highlight.range(buffer_id, ns, 'InlayHint', {0,0}, {0, 1})
	vim.highlight.range(buffer_id, ns, 'Title', {0,3}, {0, 9})
	vim.keymap.set('n', '<CR>', function () open_buffer_under_cursor() end, { buffer = buffer_id })
	vim.keymap.set('n', 'a', function () buffers.create(vim.fn.input("path > ", "")) end, { buffer = buffer_id })
end

local function update_window()
	local tree = state.client:get_workspace(state.workspace).filetree
	vim.api.nvim_set_option_value('modifiable', true, { buf = buffer_id })
	utils.buffer.set_content(
		buffer_id,
		">| codemp\n |: " .. state.workspace .. "\n |\n |- "
		.. vim.fn.join(tree, "\n |- ")
	)
	vim.highlight.range(buffer_id, ns, 'InlayHint', {0,0}, {0, 2})
	vim.highlight.range(buffer_id, ns, 'Title', {0,3}, {0, 9})
	vim.highlight.range(buffer_id, ns, 'InlayHint', {1,1}, {1, 3})
	vim.highlight.range(buffer_id, ns, 'Directory', {1,4}, {1, 128})
	vim.highlight.range(buffer_id, ns, 'InlayHint', {2,1}, {2, 3})
	for n, _ in ipairs(tree) do
		vim.highlight.range(buffer_id, ns, 'InlayHint', {2+n,1}, {2+n, 3})
	end
	vim.api.nvim_set_option_value('modifiable', false, { buf = buffer_id })
end

local function open_window()
	window_id = vim.api.nvim_open_win(buffer_id, true, {
		win = 0,
		split = 'left',
		width = 20,
	})
	vim.api.nvim_set_option_value('relativenumber', false, {})
	vim.api.nvim_set_option_value('number', false, {})
	vim.api.nvim_set_option_value('cursorlineopt', 'line', {})
end

local function toggle_window()
	if window_id ~= nil then
		vim.api.nvim_win_close(window_id, true)
		window_id = nil
	else
		prev_window = vim.api.nvim_get_current_win()
		open_window()
	end
end

init_window()

return {
	init = init_window,
	open = open_window,
	update = update_window,
	toggle = toggle_window,
	buffer = buffer_id,
}
