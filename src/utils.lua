local native = require('codemp.loader').load()

local available_colors = { -- TODO these are definitely not portable!
	"ErrorMsg",
	"WarningMsg",
	"MatchParen",
	"SpecialMode",
	"CmpItemKindFunction",
	"CmpItemKindValue",
	"CmpItemKindInterface",
}

local function color(x)
	return available_colors[ math.fmod(math.abs(native.hash(x)), #available_colors) + 1 ]
end

local function order_tuples(x) -- TODO send help...
	if x[1][1] < x[2][1] then
		return { { x[1][1], x[1][2] }, { x[2][1], x[2][2] } }
	elseif x[1][1] > x[2][1] then
		return { { x[2][1], x[2][2] }, { x[1][1], x[1][2] } }
	elseif x[1][2] < x[2][2] then
		return { { x[1][1], x[1][2] }, { x[2][1], x[2][2] } }
	else
		return { { x[2][1], x[2][2] }, { x[1][1], x[1][2] } }
	end
end

local function cursor_position()
	local mode = vim.api.nvim_get_mode().mode
	if mode == "v" then
		local _, ls, cs = unpack(vim.fn.getpos('v'))
		local _, le, ce = unpack(vim.fn.getpos('.'))
		return order_tuples({ { ls-1, cs-1 }, { le-1, ce } })
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
		return order_tuples({ { cur[1]-1, cur[2] }, { cur[1]-1, cur[2]+1 } })
	end
end

local function buffer_get_content(buf)
	if buf == nil then
		buf = vim.api.nvim_get_current_buf()
	end
	local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
	return table.concat(lines, '\n')
end

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
local function buffer_set_content(buf, content, first, last)
	if first == nil and last == nil then
		local lines = vim.split(content, "\n", {trimempty=false})
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	else
		local first_row, first_col, last_row, last_col
		vim.api.nvim_buf_call(buf, function()
			first_row = vim.fn.byte2line(first + 1) - 1
			if first_row == -2 then
				-- print("?? clamping start_row to start")
				first_row = vim.fn.line('$') - 1
			end
			local first_col_byte = vim.fn.line2byte(first_row + 1) - 1
			if first_col_byte == -2 then
				-- print("?? clamping start_col to 0")
				first_col = 0
			else
				first_col = first - first_col_byte
			end
			if first == last then
				last_row = first_row
				last_col = first_col
			else
				last_row = vim.fn.byte2line(last + 1) - 1
				if last_row == -2 then
					print("?? clamping end_row to end")
					last_row = vim.fn.line('$') - 1
					last_col = last - vim.fn.line2byte(last_row + 1)
				else
					last_col = last - (vim.fn.line2byte(last_row + 1) - 1)
				end
			end
		end)
		local content_array
		if content == "" then
			content_array = {}
		else
			content_array = vim.split(content, "\n", {trimempty=false})
		end
		-- print(string.format("set [%s..%s::'%s'] -> start(row:%s col:%s) end(row:%s, col:%s)", first, last, content, first_row, first_col, last_row, last_col))
		vim.api.nvim_buf_set_text(buf, first_row, first_col, last_row, last_col, content_array)
	end
end

local function buffer_replace_content(buffer, first, last, content)
	-- TODO send help it works but why is lost knowledge
	local start_row = vim.fn.byte2line(first + 1) - 1
	if start_row < 0 then start_row = 0 end
	local start_row_byte = vim.fn.line2byte(start_row + 1) - 1
	if start_row_byte < 0 then start_row_byte = 0 end
	local end_row = vim.fn.byte2line(last + 1) - 1
	if end_row < 0 then end_row = 0 end
	local end_row_byte = vim.fn.line2byte(end_row + 1) - 1
	if end_row_byte < 0 then end_row_byte = 0 end
	vim.api.nvim_buf_set_text(
		buffer,
		start_row,
		first - start_row_byte,
		end_row,
		last - end_row_byte,
		vim.fn.split(content, '\n', true)
	)
end

local function multiline_highlight(buf, ns, group, start, fini)
	for i=start.row,fini.row do
		if i == start.row and i == fini.row then
			local fini_col = fini.col
			if start.col == fini.col then fini_col = fini_col + 1 end
			vim.api.nvim_buf_add_highlight(buf, ns, group, i, start.col, fini_col)
		elseif i == start.row then
			vim.api.nvim_buf_add_highlight(buf, ns, group, i, start.col, -1)
		elseif i == fini.row then
			vim.api.nvim_buf_add_highlight(buf, ns, group, i, 0, fini.col)
		else
			vim.api.nvim_buf_add_highlight(buf, ns, group, i, 0, -1)
		end
	end
end


return {
	order_tuples = order_tuples,
	multiline_highlight = multiline_highlight,
	cursor = {
		position = cursor_position,
	},
	buffer = {
		get_content = buffer_get_content,
		set_content = buffer_set_content,
		replace_content = buffer_replace_content,
	},
	hash = native.hash,
	available_colors = available_colors,
	color = color,
}
