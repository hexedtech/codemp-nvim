use std::io::Write;
use std::sync::{mpsc, Arc, Mutex};

use codemp::prelude::*;
use codemp::woot::crdt::Op;
use mlua::prelude::*;
use tokio::runtime::Runtime;
use tokio::sync::RwLock;

lazy_static::lazy_static!{
	// TODO use a runtime::Builder::new_current_thread() runtime to not behave like malware
	static ref RT : Runtime = Runtime::new().expect("could not instantiate tokio runtime");
	static ref CODEMP : RwLock<CodempClient> = RwLock::new(RT.block_on(CodempClient::new(
		&std::env::var("CODEMP_BASE_HOST").unwrap_or("http://codemp.alemi.dev:50051".to_string())
	)).expect("could not connect to codemp servers"));
}


#[derive(Debug, thiserror::Error, derive_more::From, derive_more::Display)]
struct LuaCodempError(CodempError);

impl From::<LuaCodempError> for LuaError {
	fn from(value: LuaCodempError) -> Self {
		LuaError::external(value)
	}
}

// TODO put friendlier constructor directly in lib?
fn make_cursor(buffer: String, start_row: i32, start_col: i32, end_row: i32, end_col: i32) -> CodempCursorPosition {
	CodempCursorPosition {
		buffer, start: CodempRowCol { row: start_row, col: start_col}, end: CodempRowCol { row: end_row, col: end_col },
	}
}

fn id(_: &Lua, (): ()) -> LuaResult<String> {
	Ok(CODEMP.blocking_read().user_id().to_string())
}


/// join a remote workspace and start processing cursor events
fn join_workspace(_: &Lua, (session,): (String,)) -> LuaResult<LuaCursorController> {
	let ws = RT.block_on(async { CODEMP.write().await.join_workspace(&session).await })
		.map_err(LuaCodempError::from)?;
	let cursor = ws.blocking_read().cursor().clone();
	Ok(LuaCursorController(cursor))
}

fn get_workspace(_: &Lua, (session,): (String,)) -> LuaResult<Option<LuaWorkspace>> {
	Ok(CODEMP.blocking_read().workspaces.get(&session).cloned().map(LuaWorkspace))
}

#[derive(Debug, derive_more::From)]
struct LuaOp(Op);
impl LuaUserData for LuaOp { }

#[derive(derive_more::From)]
struct LuaWorkspace(Arc<RwLock<CodempWorkspace>>);
impl LuaUserData for LuaWorkspace {
	fn add_methods<'lua, M: LuaUserDataMethods<'lua, Self>>(methods: &mut M) {
		methods.add_method("create_buffer", |_, this, (name,):(String,)| {
			Ok(RT.block_on(async { this.0.write().await.create(&name).await }).map_err(LuaCodempError::from)?)
		});

		methods.add_method("attach_buffer", |_, this, (name,):(String,)| {
			Ok(LuaBufferController(RT.block_on(async { this.0.write().await.attach(&name).await }).map_err(LuaCodempError::from)?))
		});

		// TODO disconnect_buffer
		// TODO leave_workspace:w

		methods.add_method("get_buffer", |_, this, (name,):(String,)| Ok(RT.block_on(async { this.0.read().await.buffer_by_name(&name) }).map(|x| LuaBufferController(x))));
	}

	fn add_fields<'lua, F: LuaUserDataFields<'lua, Self>>(fields: &mut F) {
		fields.add_field_method_get("cursor", |_, this| Ok(LuaCursorController(RT.block_on(async { this.0.read().await.cursor() }))));
		fields.add_field_method_get("filetree", |_, this| Ok(RT.block_on(async { this.0.read().await.filetree() })));
		// methods.add_method("users", |_, this| Ok(this.0.users())); // TODO
	}
}



#[derive(Debug, derive_more::From)]
struct LuaCursorController(Arc<CodempCursorController>);
impl LuaUserData for LuaCursorController {
	fn add_methods<'lua, M: LuaUserDataMethods<'lua, Self>>(methods: &mut M) {
		methods.add_meta_method(LuaMetaMethod::ToString, |_, this, ()| Ok(format!("{:?}", this.0)));
		methods.add_method("send", |_, this, (usr, sr, sc, er, ec):(String, i32, i32, i32, i32)| {
			Ok(this.0.send(make_cursor(usr, sr, sc, er, ec)).map_err(LuaCodempError::from)?)
		});
		methods.add_method("try_recv", |_, this, ()| {
			match this.0.try_recv() .map_err(LuaCodempError::from)? {
				Some(x) => Ok(Some(LuaCursorEvent(x))),
				None => Ok(None),
			}
		});
		methods.add_method("poll", |_, this, ()| {
			RT.block_on(this.0.poll())
					.map_err(LuaCodempError::from)?;
			Ok(())
		});
	}
}

#[derive(Debug, derive_more::From)]
struct LuaCursorEvent(CodempCursorEvent);
impl LuaUserData for LuaCursorEvent {
	fn add_fields<'lua, F: LuaUserDataFields<'lua, Self>>(fields: &mut F) {
		fields.add_field_method_get("user", |_, this| Ok(this.0.user.id.clone()));
		fields.add_field_method_get("position", |_, this|
			Ok(LuaCursorPosition(this.0.position.clone()))
		);
	}
}

#[derive(Debug, derive_more::From)]
struct LuaCursorPosition(CodempCursorPosition);
impl LuaUserData for LuaCursorPosition {
	fn add_fields<'lua, F: LuaUserDataFields<'lua, Self>>(fields: &mut F) {
		fields.add_field_method_get("buffer", |_, this| Ok(this.0.buffer.clone()));
		fields.add_field_method_get("start",  |_, this| Ok(LuaRowCol(this.0.start.clone())));
		fields.add_field_method_get("finish", |_, this| Ok(LuaRowCol(this.0.end.clone())));
	}
}


#[derive(Debug, derive_more::From)]
struct LuaBufferController(Arc<CodempBufferController>);
impl LuaUserData for LuaBufferController {
	fn add_methods<'lua, M: LuaUserDataMethods<'lua, Self>>(methods: &mut M) {
		methods.add_meta_method(LuaMetaMethod::ToString, |_, this, ()| Ok(format!("{:?}", this.0)));
		methods.add_method("send", |_, this, (start, end, text): (usize, usize, String)| {
			Ok(
				this.0.send(
					CodempTextChange {
						span: start..end,
						content: text,
					}
				)
					.map_err(LuaCodempError::from)?
			)
		});
		methods.add_method("try_recv", |_, this, ()| {
			match this.0.try_recv().map_err(LuaCodempError::from)? {
				Some(x) => Ok(Some(LuaTextChange(x))),
				None => Ok(None),
			}
		});
		methods.add_method("poll", |_, this, ()| {
			RT.block_on(this.0.poll())
					.map_err(LuaCodempError::from)?;
			Ok(())
		});
	}

	fn add_fields<'lua, F: LuaUserDataFields<'lua, Self>>(fields: &mut F) {
		fields.add_field_method_get("content", |_, this| Ok(this.0.content()));
	}
}

#[derive(Debug, derive_more::From)]
struct LuaTextChange(CodempTextChange);
impl LuaUserData for LuaTextChange {
	fn add_fields<'lua, F: LuaUserDataFields<'lua, Self>>(fields: &mut F) {
		fields.add_field_method_get("content", |_, this| Ok(this.0.content.clone()));
		fields.add_field_method_get("first",   |_, this| Ok(this.0.span.start));
		fields.add_field_method_get("last",  |_, this| Ok(this.0.span.end));
	}

	fn add_methods<'lua, M: LuaUserDataMethods<'lua, Self>>(methods: &mut M) {
		methods.add_meta_function(LuaMetaMethod::Call, |_, (start, end, txt): (usize, usize, String)| {
			Ok(LuaTextChange(CodempTextChange {
				span: start..end,
				content: txt,
			}))
		});
		methods.add_meta_method(LuaMetaMethod::ToString, |_, this, ()| Ok(format!("{:?}", this.0)));
		methods.add_method("apply", |_, this, (txt,):(String,)| Ok(this.0.apply(&txt)));
	}
}

#[derive(Debug, derive_more::From)]
struct LuaRowCol(CodempRowCol);
impl LuaUserData for LuaRowCol {
	fn add_fields<'lua, F: LuaUserDataFields<'lua, Self>>(fields: &mut F) {
		fields.add_field_method_get("row", |_, this| Ok(this.0.row));
		fields.add_field_method_get("col", |_, this| Ok(this.0.col));
	}
}



// setup library logging to file
#[derive(Debug, derive_more::From)]
struct LuaLogger(Arc<Mutex<mpsc::Receiver<String>>>);
impl LuaUserData for LuaLogger {
	fn add_methods<'lua, M: LuaUserDataMethods<'lua, Self>>(methods: &mut M) {
		methods.add_method("recv", |_, this, ()| {
			Ok(
				this.0
					.lock()
					.expect("logger mutex poisoned")
					.recv()
					.expect("logger channel closed")
			)
		});
	}
}

#[derive(Debug, Clone)]
struct LuaLoggerProducer(mpsc::Sender<String>);
impl Write for LuaLoggerProducer {
	fn write(&mut self, buf: &[u8]) -> std::io::Result<usize> {
		self.0.send(String::from_utf8_lossy(buf).to_string())
			.expect("could not write on logger channel");
		Ok(buf.len())
	}

	fn flush(&mut self) -> std::io::Result<()> { Ok(()) }
}

fn setup_tracing(_: &Lua, (debug,): (Option<bool>,)) -> LuaResult<LuaLogger> {
	let (tx, rx) = mpsc::channel();
	let level = if debug.unwrap_or(false) { tracing::Level::DEBUG } else {tracing::Level::INFO };
	let format = tracing_subscriber::fmt::format()
		.with_level(true)
		.with_target(true)
		.with_thread_ids(false)
		.with_thread_names(false)
		.with_ansi(false)
		.with_file(false)
		.with_line_number(false)
		.with_source_location(false)
		.compact();
	tracing_subscriber::fmt()
		.event_format(format)
		.with_max_level(level)
		.with_writer(Mutex::new(LuaLoggerProducer(tx)))
		.init();
	Ok(LuaLogger(Arc::new(Mutex::new(rx))))
}

// define module and exports
#[mlua::lua_module]
fn libcodemp_nvim(lua: &Lua) -> LuaResult<LuaTable> {
	let exports = lua.create_table()?;

	// core proto functions
	exports.set("join_workspace", lua.create_function(join_workspace)?)?;
	// state helpers
	exports.set("get_workspace", lua.create_function(get_workspace)?)?;
	// debug
	exports.set("id", lua.create_function(id)?)?;
	exports.set("setup_tracing", lua.create_function(setup_tracing)?)?;

	Ok(exports)
}
