local utils = require('codemp.utils')
local async = require('codemp.async')
local state = require('codemp.state')

local id_buffer_map = {}
local buffer_id_map = {}
local ticks = {}

local function create(name, content)
	state.client:get_workspace(state.workspace):create_buffer(name, content)
	print(" ++ created buffer '" .. name .. "' on " .. state.workspace)
end

local function delete(name)
	state.client:get_workspace(state.workspace):delete_buffer(name)
	print(" -- deleted buffer " .. name)
end

local function attach(name, force)
	local buffer = nil
	if force then
		buffer = vim.api.nvim_get_current_buf()
		utils.buffer.set_content(buffer, "")
	else
		buffer = vim.api.nvim_create_buf(true, true)
		vim.api.nvim_set_option_value('fileformat', 'unix', { buf = buffer })
		-- vim.api.nvim_buf_set_option(buffer, 'filetype', 'codemp') -- TODO get from codemp?
		vim.api.nvim_buf_set_name(buffer, "codemp::" .. name)
		vim.api.nvim_set_current_buf(buffer)
	end
	local controller = state.client:get_workspace(state.workspace):attach(name)

	-- TODO map name to uuid

	id_buffer_map[buffer] = name
	buffer_id_map[name] = buffer
	ticks[buffer] = 0

	-- hook serverbound callbacks
	-- TODO breaks when deleting whole lines at buffer end
	vim.api.nvim_buf_attach(buffer, false, {
		on_bytes = function(_, buf, tick, start_row, start_col, start_offset, old_end_row, old_end_col, old_end_byte_len, new_end_row, new_end_col, new_byte_len)
			if tick <= ticks[buf] then return end
			if id_buffer_map[buf] == nil then return true end -- unregister callback handler
			print(string.format(
				"start(row:%s, col:%s) offset:%s end(row:%s, col:%s new(row:%s, col:%s)) len(old:%s, new:%s)",
				start_row, start_col, start_offset, old_end_row, old_end_col, new_end_row, new_end_col, old_end_byte_len, new_byte_len
			))
			local content
			if new_byte_len == 0 then
				content = ""
			else
				content = table.concat(
					vim.api.nvim_buf_get_text(buf, start_row, start_col, start_row + new_end_row, start_col + new_end_col, {}),
					'\n'
				)
			end
			print(string.format("sending: %s %s %s %s -- '%s'", start_row, start_col, start_row + new_end_row, start_col + new_end_col, content))
			controller:send(start_offset, start_offset + old_end_byte_len, content)
		end,
	})

	-- hook clientbound callbacks
	async.handler(name, controller, function(event)
		ticks[buffer] = vim.api.nvim_buf_get_changedtick(buffer)
		-- print(" ~~ applying change ~~ " .. event.first .. ".." .. event.last .. "::[" .. event.content .. "]")
		utils.buffer.set_content(buffer, event.content, event.first, event.last)
		if event.hash ~= nil then
			if utils.hash(utils.buffer.get_content(buffer)) ~= event.hash then
				-- OUT OF SYNC!
				-- TODO this may be destructive! we should probably prompt the user before doing this
				print(" /!\\ out of sync, resynching...")
				utils.buffer.set_content(buffer, controller:content())
				return
			end
		end
	end, 20) -- wait 20ms before polling again because it overwhelms libuv?

	print(" ++ attached to buffer " .. name)
end

local function detach(name)
	local buffer = buffer_id_map[name]
	id_buffer_map[buffer] = nil
	buffer_id_map[name] = nil
	state.client:get_workspace(state.workspace):detach(name)
	vim.api.nvim_buf_delete(buffer, {})

	print(" -- detached from buffer " .. name)
end

local function sync()
	local buffer = vim.api.nvim_get_current_buf()
	local name = id_buffer_map[buffer]
	if name ~= nil then
		local controller = state.client:get_workspace(state.workspace):get_buffer(name)
		ticks[buffer] = vim.api.nvim_buf_get_changedtick(buffer)
		utils.buffer.set_content(buffer, controller:content())
		print(" :: synched buffer " .. name)
	else
		print(" !! buffer not managed")
	end
end


return {
	create = create,
	delete = delete,
	sync = sync,
	attach = attach,
	detach = detach,
	map = id_buffer_map,
	map_rev = buffer_id_map,
	ticks = ticks,
}
