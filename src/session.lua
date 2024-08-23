---@type Workspace
local workspace

---@type Client
local client

---@class WorkspaceReference
---@field name string
---@field owned boolean

---@type WorkspaceReference[]
local available_workspaces = {}

return {
	workspace = workspace,
	client = client,
	available = available_workspaces,
}
