local colors = {
	{ "#AC7EA8", 175 },
	{ "#81A1C1", 74  },
	{ "#EBCB8B", 222 },
	{ "#2E8757", 72  },
	{ "#BF616A", 167 },
	{ "#8F81D4", 98  },
	{ "#D69C63", 179 },
}

local function setup_colors()
	for n, color in ipairs(colors) do
		vim.api.nvim_set_hl(0, string.format("CodempUser%s", n), { fg = color[1], bg = nil, ctermfg = color[2], ctermbg = 0 })
		vim.api.nvim_set_hl(0, string.format("CodempUserInverted%s", n), { fg = "#201F29", bg = color[1], ctermfg = 234, ctermbg = color[2] })
	end
end

---@class HighlightPair
---@field fg string
---@field bg string

---@param name string
---@return HighlightPair
local function color(name)
	local index = math.fmod(math.abs(CODEMP.native.hash(name)), #colors) + 1
	return {
		fg = "CodempUser" .. index,
		bg = "CodempUserInverted" .. index,
	}
end

local function async_poller(generator, callback)
	local promise = nil
	local timer = vim.loop.new_timer()
	timer:start(500, 500, function()
		if promise == nil then promise = generator() end
		if promise.ready then
			local res = promise:await()
			vim.schedule(function() callback(res) end)
			promise = nil
		end
	end)

end

---@param first integer
---@param last integer
---@return integer, integer, integer, integer
local function offset_to_rowcol(first, last)
	local start_row, start_col, end_row, end_col

	-- TODO this seems to work but i lost my sanity over it. if you want
	--      to try and make it better be warned api is madness but i will
	--      thank you a lot because this is an ugly mess...
	--
	--  edge cases to test:
	--   - [x] add newline in buffer
	--   - [x] append newline to buffer
	--   - [x] delete multiline
	--   - [x] append at end of buffer
	--   - [x] delete at end of buffer
	--   - [x] delete line at end of buffer
	--   - [x] delete multiline at end of buffer
	--   - [x] autocomplete
	--   - [ ] delete whole buffer
	--   - [ ] enter insert in newline with `o`

	start_row = vim.fn.byte2line(first + 1) - 1
	if start_row == -2 then
		-- print("?? clamping start_row to start")
		start_row = vim.fn.line('$') - 1
	end
	local first_col_byte = vim.fn.line2byte(start_row + 1) - 1
	if first_col_byte == -2 then
		-- print("?? clamping start_col to 0")
		start_col = 0
	else
		start_col = first - first_col_byte
	end
	if first == last then
		end_row = start_row
		end_col = start_col
	else
		end_row = vim.fn.byte2line(last + 1) - 1
		if end_row == -2 then
			print("?? clamping end_row to end")
			end_row = vim.fn.line('$') - 1
			end_col = last - vim.fn.line2byte(end_row + 1)
		else
			end_col = last - (vim.fn.line2byte(end_row + 1) - 1)
		end
	end

	-- TODO this is an older approach, which covers less edge cases
	--      but i didnt bother documenting/testing it yet properly

	----send help it works but why is lost knowledge
	--start_row = vim.fn.byte2line(first + 1) - 1
	--if start_row < 0 then start_row = 0 end
	--local start_row_byte = vim.fn.line2byte(start_row + 1) - 1
	--if start_row_byte < 0 then start_row_byte = 0 end
	--start_col = first - start_row_byte
	--end_row = vim.fn.byte2line(last + 1) - 1
	--if end_row < 0 then end_row = 0 end
	--local end_row_byte = vim.fn.line2byte(end_row + 1) - 1
	--if end_row_byte < 0 then end_row_byte = 0 end
	--end_col = last - end_row_byte

	return start_row, start_col, end_row, end_col
end

---@return [ [integer, integer], [integer, integer] ]
local function cursor_position()
	local mode = vim.api.nvim_get_mode().mode
	if mode == "v" then
		local _, ls, cs = unpack(vim.fn.getpos('v'))
		local _, le, ce = unpack(vim.fn.getpos('.'))
		return { { ls-1, cs-1 }, { le-1, ce } }
	elseif mode == "V" then
		local _, ls, _ = unpack(vim.fn.getpos('v'))
		local _, le, _ = unpack(vim.fn.getpos('.'))
		if le > ls then
			local ce = vim.fn.strlen(vim.fn.getline(le))
			return { { ls-1, 0 }, { le-1, ce } }
		else
			local ce = vim.fn.strlen(vim.fn.getline(ls))
			return { { le-1, 0 }, { ls-1, ce } }
		end
	else
		local win = vim.api.nvim_get_current_win()
		local cur = vim.api.nvim_win_get_cursor(win)
		return { { cur[1]-1, cur[2] }, { cur[1]-1, cur[2]+1 } }
	end
end

---@param buf integer?
---@return string
local function buffer_get_content(buf)
	if buf == nil then
		buf = vim.api.nvim_get_current_buf()
	end
	local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
	return table.concat(lines, '\n')
end

---@param buf integer
---@param content string
---@param first integer?
---@param last integer?
---set content of a buffer using byte indexes
---if first and last are both nil, set whole buffer content
---if first is nil, it defaults to 0
---if last is nil, it will calculate and use the last byte in the buffer
local function buffer_set_content(buf, content, first, last)
	if first == nil and last == nil then
		local lines = vim.split(content, "\n", {trimempty=false})
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	else
		if first == nil then first = 0 end
		if last == nil then
			local line_count = vim.api.nvim_buf_line_count(buf)
			last = vim.api.nvim_buf_get_offset(buf, line_count + 1)
		end
		local first_row, first_col, last_row, last_col
		vim.api.nvim_buf_call(buf, function()
			first_row, first_col, last_row, last_col = offset_to_rowcol(first or 0, last or 0)
		end)
		local content_array
		if content == "" then
			content_array = {}
		else
			content_array = vim.split(content, "\n", {trimempty=false})
		end
		if CODEMP.config.debug then
			print(string.format("nvim_buf_set_text [%s..%s::'%s'] -> start(row:%s col:%s) end(row:%s, col:%s)", first, last, content, first_row, first_col, last_row, last_col))
		end
		vim.api.nvim_buf_set_text(buf, first_row, first_col, last_row, last_col, content_array)
	end
end


local function buffer_len(buf)
	local count = 0
	vim.api.nvim_buf_call(buf, function()
		count = vim.fn.wordcount().chars
	end)
	return count
end

---@return string
local function separator()
	if vim.uv.os_uname().sysname == "Windows_NT" then
		return '\\'
	else
		return '/'
	end
end

return {
	cursor = {
		position = cursor_position,
	},
	buffer = {
		len = buffer_len,
		get_content = buffer_get_content,
		set_content = buffer_set_content,
	},
	available_colors = available_colors,
	color = color,
	poller = async_poller,
	sep = separator,
	setup_colors = setup_colors,
}
