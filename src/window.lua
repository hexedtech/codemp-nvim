local session = require('codemp.session')
local utils = require('codemp.utils')
local buffers = require('codemp.buffers')

---@type integer?
local buffer_id = nil

---@type integer?
local prev_window = nil

---@type integer?
local window_id = nil

local ns = vim.api.nvim_create_namespace("codemp-window")

vim.api.nvim_create_autocmd({"WinLeave"}, {
	callback = function (ev)
		if ev.id ~= window_id then
			prev_window = vim.api.nvim_get_current_win()
		end
	end
})

---@type table<integer, string>
local row_to_buffer = {}

local function update_window()
	if buffer_id == nil then error("cannot update window while codemp buffer is unset") end
	row_to_buffer = {}
	local buffer_to_row = {}
	local user_to_row = {}
	local off = {}
	local tree = session.workspace:filetree()
	vim.api.nvim_set_option_value('modifiable', true, { buf = buffer_id })
	local tmp =  ">| codemp\n"
	tmp = tmp .. " |: " .. session.workspace.name .. "\n"
	tmp = tmp .. " |\n"
	local base_row = 3
	for n, path in pairs(tree) do
		tmp = tmp .. " |- " .. path .. "\n"
		base_row = 3 + n
		buffer_to_row[path] = base_row
	end
	tmp = tmp .. "\n\n\n"
	base_row = base_row + 3
	for usr, _ in pairs(buffers.users) do
		tmp = tmp .. "* + " .. usr .. "\n"
		base_row = base_row + 1
		user_to_row[usr] = base_row
	end
	utils.buffer.set_content(buffer_id, tmp)
	vim.highlight.range(buffer_id, ns, 'InlayHint', {0,0}, {0, 2})
	vim.highlight.range(buffer_id, ns, 'Title', {0,3}, {0, 9})
	vim.highlight.range(buffer_id, ns, 'InlayHint', {1,1}, {1, 3})
	vim.highlight.range(buffer_id, ns, 'Directory', {1,4}, {1, 128})
	vim.highlight.range(buffer_id, ns, 'InlayHint', {2,1}, {2, 3})
	for n, name in ipairs(tree) do
		buffer_to_row[name] = n+3
		row_to_buffer[n+3] = name
		vim.highlight.range(buffer_id, ns, 'InlayHint', {2+n,1}, {2+n, 3})
		if buffers.map_rev[name] ~= nil then
			vim.highlight.range(buffer_id, ns, 'Underlined', {2+n,4}, {2+n, 128})
		end
	end
	for user, buffer in pairs(buffers.users) do
		local row = buffer_to_row[buffer]
		if off[row] == nil then
			off[row] = 0
		end
		vim.highlight.range(buffer_id, ns, utils.color(user), {row-1,4+off[row]}, {row-1, 5+off[row]})
		off[row] = off[row] + 1
		row = user_to_row[user]
		vim.highlight.range(buffer_id, ns, 'InlayHint', {row-1, 0}, {row-1, 1})
		vim.highlight.range(buffer_id, ns, utils.color(user), {row-1, 2}, {row-1, 3})
	end
	vim.api.nvim_set_option_value('modifiable', false, { buf = buffer_id })
end

local function open_buffer_under_cursor()
	if window_id == nil then return end
	if buffer_id == nil then return end
	local cursor = vim.api.nvim_win_get_cursor(window_id)
	local path = row_to_buffer[cursor[1]]
	if path == nil then
		print(" /!\\ not a buffer")
		return
	end
	if prev_window ~= nil then
		vim.api.nvim_set_current_win(prev_window)
	end
	if buffers.map_rev[path] ~= nil then
		vim.api.nvim_set_current_buf(buffers.map_rev[path])
	else
		buffers.attach(path)
		update_window()
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
	vim.api.nvim_create_autocmd({"WinClosed"}, {
		callback = function (ev)
			if tonumber(ev.match) == window_id then
				window_id = nil
			end
		end
	})
end

local function open_window()
	if buffer_id == nil then error("no active codemp buffer, reinitialize the window") end
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
	id = window_id,
}
