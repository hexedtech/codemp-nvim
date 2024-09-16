local plugin_dir = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h") -- got this from https://lazy.folke.io/developers#building

local os_uname = vim.loop.os_uname()

local arch = os_uname.machine

local platform = string.lower(os_uname.sysname)
if platform == "mac" then
	platform = "darwin"
elseif platform == "windows_nt" then
	platform = "windows-gnu"
else
	platform = platform .. "-gnu"
end

local ext = os_uname.sysname
if os_uname.sysname == "Windows_NT" then ext = "dll"
elseif os_uname.sysname == "Mac" then ext = "dylib"
else ext = "so"
end

-- -- TODO compare checksum before redownloading
-- if vim.fn.filereadable(path .. 'native' .. ext) == 1 then
-- 	shasum = vim.fn.system("sha256sum " .. path .. 'native' .. ext)
-- end

local sep = '/'
if os_uname.sysname == "Windows_NT" then sep = '\\' end

local native_path = plugin_dir..sep.."lua"..sep.."codemp"..sep.."new-native."..ext
local replace_native_path = plugin_dir..sep.."lua"..sep.."codemp"..sep.."native."..ext
local download_url_native = string.format("https://codemp.dev/releases/lua/codemp-lua-%s-%s.%s", arch, platform, ext)

local command = {
	Windows_NT = { "Invoke-WebRequest", download_url_native, "-OutFile", native_path },
	Linux = {"curl", "-o", native_path, download_url_native },
	Mac = {"curl", "-o", native_path, download_url_native },
}

print("downloading codemp native lua extension from '" .. download_url_native .. "' ...")
vim.system(command[os_uname.sysname]):wait() -- TODO can we run this asynchronously?
print("downloaded! exit nvim to reload library")

vim.api.nvim_create_autocmd(
	{"ExitPre"},
	{
		callback = function (_ev)
			vim.system({"mv", native_path, replace_native_path}, { detach = true })
		end
	}
)
