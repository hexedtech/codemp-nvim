--
---- converters: row+col <-> byte offset
--

---convert a global byte offset (0-indexed) to a (row, column) tuple (0-indexed)
---@param offset integer global index in buffer (first byte is #0)
---@param buf? integer buffer number, defaults to current
---@return integer? row, integer? col
local function byte2rowcol(offset, buf)
	if buf == nil then
		buf = vim.api.nvim_get_current_buf()
	end
	local row
	vim.api.nvim_buf_call(buf, function ()
		row = vim.fn.byte2line(offset + 1)
	end)
	if row == -1 then
		return nil, nil
	else
		row = row - 1 -- go back to 0-indexing
	end
	local off = vim.api.nvim_buf_get_offset(buf, row)
	return row, offset - off
end

---convert a (row, column) tuple (0-indexed) to a global byte offset (0-indexed)
---@param row integer row number (first row is #0)
---@param col integer col number (first col is #0)
---@param buf? integer buffer number, defaults to current
---@return integer? offset
local function rowcol2byte(row, col, buf)
	if buf == nil then
		buf = vim.api.nvim_get_current_buf()
	end
	-- TODO naive implementation doesn't account for multi-byte characters!
	--local off = vim.api.nvim_buf_get_offset(buf, row)
	--if off == -1 then return nil end
	--return off + col
	-- TODO nvim LSP utils seem to cover this but can we rely on these?
	return vim.lsp.util.character_offset(buf, row, col, 'utf-8')
end



--
---- cursor utilities
--

---return current user cursor position, as a tuple of (row, columl) tuples (0-indexed)
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

---@param event Cursor
---@param buf integer
---@param ns integer
---@param mark integer
---@param hi HighlightPair
---@return integer extmark id
local function cursor_draw(event, buf, ns, mark, hi)
	local event_finish_2 = event.sel.end_col -- TODO can't set the tuple field? need to copy out
	if event.sel.start_row == event.sel.end_row and event.sel.start_col == event.sel.end_col then
		-- vim can't draw 0-width cursors, so we always expand them to at least 1 width
		event_finish_2 = event.sel.end_col + 1
	end
	return vim.api.nvim_buf_set_extmark(
		buf,
		ns,
		event.sel.start_row,
		event.sel.start_col,
		{
			id = mark,
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



--
---- buffer utilities
--

---return lenght for given buffer
---@param unit string either 'bytes' for byte count or 'chars' for characters count, default to 'chars'
---@return integer
local function buffer_len(buf, unit)
	local count = -1
	if unit == nil then unit = 'chars' end
	vim.api.nvim_buf_call(buf, function()
		count = vim.fn.wordcount()[unit]
	end)
	return count
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

		local first_row, first_col = byte2rowcol(first, buf)
		if first_row == nil or first_col == nil then error("invalid start offset") end
		local last_row, last_col = byte2rowcol(last, buf)
		if last_row == nil or last_col == nil then error("invalid end offset") end

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



--
---- codemp color palette and helper functions
--

local colors = {
	{ "#AC7EA8", 175 },
	{ "#81A1C1", 74  },
	{ "#EBCB8B", 222 },
	{ "#55886C", 72  },
	{ "#D1888E", 167 },
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



--
---- platform utilities
--

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
		draw = cursor_draw,
	},
	buffer = {
		len = buffer_len,
		get_content = buffer_get_content,
		set_content = buffer_set_content,
	},
	available_colors = colors,
	color = color,
	sep = separator,
	setup_colors = setup_colors,
	rowcol2byte = rowcol2byte,
	byte2rowcol = byte2rowcol,
}
