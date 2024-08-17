# codemp-nvim

<a href="https://codemp.dev"><img alt="codemp logo" align="center" src="https://codemp.dev/codemp-t.png" height="100" /></a>

> code multiplexer for neovim

CodeMP is a **collaborative** text editing plugin to work remotely.
It seamlessly integrates in your editor providing remote cursors and instant text synchronization,
as well as a remote virtual workspace for you and your team.

CodeMP is build with state-of-the-art CRDT technology, guaranteeing eventual consistency.
This means everyone in a workspace will always be working on the exact same file _eventually_:
even under unreliable networks or constrained resources, the underlying CRDT will always reach a 
convergent state across all users. Even with this baseline, CodeMP's proto is optimized for speed 
and low network footprint, meaning even slow connections can provide stable real-time editing.

> This is the reference codemp neovim plugin maintained by [hexedtech](https://hexed.technology)

## usage

> [!CAUTION]
> codemp-nvim is not finished nor ready for early adopters, this is a demo

to interact with this plugin use the `:MP` command

| command | description |
| --- | --- |
| `:MP toggle` |  toggles the codemp sidebar |
| `:MP connect [host] [username] [password]` |  to connect to server, user and pwd will be prompted if not given |

once connected, more commands become available:

| command | description |
| --- | --- |
| `:MP disconnect` |  disconnects from server |
| `:MP id` |  shows current client id |
| `:MP join <workspace>` |  will join requested workspace; starts processing cursors, users and filetree |

after a workspace is joined, more commands become available:

| command | description |
| --- | --- |
| `:MP leave <workspace>` |  disconnect from a joined workspace |
| `:MP attach <buffer>` |  will attach to requested buffer if it exists (opens a new local buffer and uses current window) |
| `:MP detach <buffer>` |  detach from a buffer and stop receiving changes |
| `:MP share` |  shares current file: creates a new buffer with local file's content, and attach to it |
| `:MP sync` |  forces resynchronization of current buffer |
| `:MP create <bufname>` |  will create a new empty buffer in workspace |
| `:MP delete <bufname>` |  will delete a buffer from workspace |

### quick start
 * first connect to server with `:MP connect`
 * then join a workspace with `:MP join <workspace>`
 * either attach directly to a buffer with `:MP attach <buffer>` or browse available buffers with `:MP toggle`

MP command autocompletes available options for current state, so cycle <Tab> if you forget any name

### configuration
it's possible to configure global `vim.g.codemp_username` and a `vim.g.codemp_password` which will be used when connecting

## installation

> [!IMPORTANT]
> the release zip provided is a tech demo for linux, there are no official releases yet

 * download the internal demo bundle from [here](https://github.com/hexedtech/codemp-nvim/releases/tag/v0.1)
 * place the whole `codemp` folder under your `.config/nvim/lua` directory
 * add `CODEMP = require('codemp')` at the end of your `init.lua`

### building
this plugin relies on the native codemp lua bindings: just compile the main `codemp` project with `lua` feature enabled 
and place a `lua.so` or `lua.dll` together with the plugin lua files while bundling

