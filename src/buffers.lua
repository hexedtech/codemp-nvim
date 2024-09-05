local utils = require('codemp.utils')
local session = require('codemp.session')

---@type table<integer, string>
local id_buffer_map = {}
---@type table<string, integer>
local buffer_id_map = {}
---@type table<string, string>
local user_buffer_name = {}
local ticks = {}

---@param name string name of buffer to attach to
---@param buffer? integer if provided, use given buffer (will clear content)
---@param content? string if provided, set this content after attaching
---@return BufferController
local function attach(name, buffer, content)
	if buffer_id_map[name] ~= nil then
		error("already attached to buffer " .. name)
	end
	if buffer == nil then
		buffer = vim.api.nvim_create_buf(true, true)
		vim.api.nvim_set_option_value('fileformat', 'unix', { buf = buffer })
		-- vim.api.nvim_buf_set_option(buffer, 'filetype', 'codemp') -- TODO get from codemp?
		vim.api.nvim_buf_set_name(buffer, "codemp::" .. name)
		vim.api.nvim_set_current_buf(buffer)
	end
	local controller = session.workspace:attach_buffer(name):await()

	-- TODO map name to uuid

	id_buffer_map[buffer] = name
	buffer_id_map[name] = buffer
	ticks[buffer] = 0

	if content ~= nil then
		local _ = controller:send(0, 0, content) -- no need to await
	end

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
			local change_content
			if new_byte_len == 0 then
				change_content = ""
			else
				change_content = table.concat(
					vim.api.nvim_buf_get_text(buf, start_row, start_col, start_row + new_end_row, start_col + new_end_col, {}),
					'\n'
				)
			end
			print(string.format("sending: %s %s %s %s -- '%s'", start_row, start_col, start_row + new_end_row, start_col + new_end_col, change_content))
			controller:send(start_offset, start_offset + old_end_byte_len, change_content):await()
		end,
	})

	local async = vim.loop.new_async(vim.schedule_wrap(function ()
		while true do
			local event = controller:try_recv():await()
			if event == nil then break end
			ticks[buffer] = vim.api.nvim_buf_get_changedtick(buffer)
			print(" ~~ applying change ~~ " .. event.first .. ".." .. event.last .. "::[" .. event.content .. "]")
			utils.buffer.set_content(buffer, event.content, event.first, event.last)
			if event.hash ~= nil then
				if utils.hash(utils.buffer.get_content(buffer)) ~= event.hash then
					-- OUT OF SYNC!
					-- TODO this may be destructive! we should probably prompt the user before doing this
					print(" /!\\ out of sync, resynching...")
					utils.buffer.set_content(buffer, controller:content():await())
					return
				end
			end
		end
	end))

	local remote_content = controller:content():await()
	ticks[buffer] = vim.api.nvim_buf_get_changedtick(buffer)
	utils.buffer.set_content(buffer, remote_content)

	controller:callback(function (_controller) async:send() end)
	vim.defer_fn(function() async:send() end, 500) -- force a try_recv after 500ms

	print(" ++ attached to buffer " .. name)
	return controller
end

---@param name string
--TODO this should happen at the level above (Workspace) but accesses tables on this level, badly designed!
local function detach(name)
	local buffer = buffer_id_map[name]
	id_buffer_map[buffer] = nil
	buffer_id_map[name] = nil
	session.workspace:detach_buffer(name)
	vim.api.nvim_buf_delete(buffer, {})

	print(" -- detached from buffer " .. name)
end

---@param buffer? integer if provided, sync given buffer id, otherwise sync current buf
local function sync(buffer)
	if buffer == nil then
		buffer = vim.api.nvim_get_current_buf()
	end
	local name = id_buffer_map[buffer]
	if name ~= nil then
		local controller = session.workspace:get_buffer(name)
		if controller ~= nil then
			ticks[buffer] = vim.api.nvim_buf_get_changedtick(buffer)
			utils.buffer.set_content(buffer, controller:content():await())
			print(" :: synched buffer " .. name)
			return
		end
	end

	print(" !! buffer not managed")
end


return {
	sync = sync,
	attach = attach,
	detach = detach,
	map = id_buffer_map,
	map_rev = buffer_id_map,
	ticks = ticks,
	users = user_buffer_name,
}
