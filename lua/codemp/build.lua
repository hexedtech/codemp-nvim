local plugin_dir = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h") -- got this from https://lazy.folke.io/developers#building
local native_path = plugin_dir .. "/native.so" -- TODO get extension based on platform
local download_url = "https://codemp.dev/releases/lua/codemp_native-linux.so" -- TODO get url based on platform
print("downloading '" .. download_url .. "' into " .. native_path)
local res = vim.system({"curl", "-s", "-o", native_path, download_url }):wait() -- TODO can we run this asynchronously?
print("downloaded: " .. res)
