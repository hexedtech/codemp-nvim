local native = require('codemp.loader').load()

local utils = require('codemp.utils')
local async = require('codemp.async')

local id_buffer_map = {}
local buffer_id_map = {}
local ticks = {}

local function create(workspace, name, content)
	native.get_workspace(workspace):create_buffer(name, content)
	print(" ++ created buffer '" .. name .. "' on " .. workspace)
end

local function attach(workspace, name, force)
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
	local controller = native.get_workspace(workspace):attach_buffer(name)

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
			-- local content = table.concat(
			-- 	vim.api.nvim_buf_get_text(buf, start_row, start_col, start_row + new_end_row, start_col + new_end_col, {}),
			-- 	'\n'
			-- )
			-- print(string.format("%s %s %s %s -- '%s'", start_row, start_col, start_row + new_end_row, start_col + new_end_col, content))
			-- controller:send(start_offset, start_offset + old_end_byte_len, content)
			controller:send_diff(utils.buffer.get_content(buf))
		end,
	})

	-- This is an ugly as hell fix: basically we receive all operations real fast at the start
	--  so the buffer changes rapidly and it messes up tracking our delta/diff state and we 
	--  get borked translated TextChanges (the underlying CRDT is fine)
	-- basically delay a bit so that it has time to sync and we can then get "normal slow" changes
	-- vim.loop.sleep(200) -- moved inside poller thread to at least not block ui

	-- hook clientbound callbacks
	async.handler(workspace, name, controller, function(event)
		ticks[buffer] = vim.api.nvim_buf_get_changedtick(buffer)
		local before = utils.buffer.get_content(buffer)
		local after = event:apply(before)
		utils.buffer.set_content(buffer, after)
		-- buffer_set_content(buffer, event.content, event.first, event.last)
		-- buffer_replace_content(buffer, event.first, event.last, event.content)
	end, 20) -- wait 20ms before polling again because it overwhelms libuv?

	print(" ++ attached to buffer " .. name)
end

local function detach(workspace, name)
	local buffer = buffer_id_map[name]
	id_buffer_map[buffer] = nil
	buffer_id_map[name] = nil
	native.get_workspace(workspace):disconnect_buffer(name)
	vim.api.nvim_buf_delete(buffer, {})

	print(" -- detached from buffer " .. name)
end

local function sync(workspace)
	local buffer = vim.api.nvim_get_current_buf()
	local name = id_buffer_map[buffer]
	if name ~= nil then
		local controller = native.get_workspace(workspace):get_buffer(name)
		ticks[buffer] = vim.api.nvim_buf_get_changedtick(buffer)
		utils.buffer.set_content(buffer, controller.content)
		print(" :: synched buffer " .. name)
	else
		print(" !! buffer not managed")
	end
end


return {
	create = create,
	sync = sync,
	attach = attach,
	detach = detach,
	map = id_buffer_map,
	map_rev = buffer_id_map,
	ticks = ticks,
}
