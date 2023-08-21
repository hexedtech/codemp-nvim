use std::sync::Arc;

use codemp::prelude::*;
use mlua::prelude::*;


#[derive(Debug, thiserror::Error, derive_more::From, derive_more::Display)]
struct LuaCodempError(CodempError);

impl From::<LuaCodempError> for LuaError {
	fn from(value: LuaCodempError) -> Self {
		LuaError::external(value)
	}
}

fn cursor_to_table(lua: &Lua, cur: CodempCursorEvent) -> LuaResult<LuaTable> {
	let pos = cur.position.unwrap_or_default();
	let start = lua.create_table()?;
	start.set(1, pos.start().row)?;
	start.set(2, pos.start().col)?;
	let end = lua.create_table()?;
	end.set(1, pos.end().row)?;
	end.set(2, pos.end().col)?;
	let out = lua.create_table()?;
	out.set("user", cur.user)?;
	out.set("buffer", pos.buffer)?;
	out.set("start", start)?;
	out.set("finish", end)?;
	Ok(out)
}

fn make_cursor(buffer: String, start_row: i32, start_col: i32, end_row: i32, end_col: i32) -> CodempCursorPosition {
	CodempCursorPosition {
		buffer,
		start: Some(CodempRowCol {
			row: start_row, col: start_col,
		}),
		end: Some(CodempRowCol {
			row: end_row, col: end_col,
		}),
	}
}



/// connect to remote server
fn connect(_: &Lua, (host,): (Option<String>,)) -> LuaResult<()> {
	let addr = host.unwrap_or("http://127.0.0.1:50051".into());
	CODEMP_INSTANCE.connect(&addr)
		.map_err(LuaCodempError::from)?;
	Ok(())
}

fn get_cursor(_: &Lua, _args: ()) -> LuaResult<LuaCursorController> {
	Ok(
		CODEMP_INSTANCE.get_cursor()
			.map_err(LuaCodempError::from)?
			.into()
	)
}

/// join a remote workspace and start processing cursor events
fn join(_: &Lua, (session,): (String,)) -> LuaResult<LuaCursorController> {
	let controller = CODEMP_INSTANCE.join(&session)
		.map_err(LuaCodempError::from)?;
	Ok(LuaCursorController(controller))
}

#[derive(Debug, derive_more::From)]
struct LuaCursorController(Arc<CodempCursorController>);
impl LuaUserData for LuaCursorController {
	fn add_methods<'lua, M: LuaUserDataMethods<'lua, Self>>(methods: &mut M) {
		methods.add_meta_method(LuaMetaMethod::ToString, |_, this, ()| Ok(format!("{:?}", this)));
		methods.add_method("send", |_, this, (usr, sr, sc, er, ec):(String, i32, i32, i32, i32)| {
			Ok(this.0.send(make_cursor(usr, sr, sc, er, ec)).map_err(LuaCodempError::from)?)
		});
		methods.add_method("recv", |lua, this, ()| {
			match this.0.try_recv() .map_err(LuaCodempError::from)? {
				Some(x) => Ok(Some(cursor_to_table(lua, x)?)),
				None => Ok(None),
			}
		});
		methods.add_method("poll", |_, this, ()| {
			CODEMP_INSTANCE.rt().block_on(this.0.poll())
					.map_err(LuaCodempError::from)?;
			Ok(())
		});
	}
}

// #[derive(derive_more::From)]
// struct LuaCursorEvent(CodempCursorEvent);
// impl LuaUserData for LuaCursorEvent {
// 	fn add_fields<'lua, F: LuaUserDataFields<'lua, Self>>(fields: &mut F) {
// 		fields.add_field_method_get("user", |_, this| Ok(this.0.user));
// 		fields.add_field_method_set("user", |_, this, val| Ok(this.0.user = val));
// 
// 		fields.add_field_method_get("user", |_, this| Ok(this.0.user));
// 		fields.add_field_method_set("user", |_, this, val| Ok(this.0.user = val));
// 	}
// }
// 
// #[derive(derive_more::From)]
// struct LuaCursorPosition(CodempCursorPosition);
// impl LuaUserData for LuaCursorPosition {
// 	fn add_fields<'lua, F: LuaUserDataFields<'lua, Self>>(fields: &mut F) {
// 		fields.add_field_method_get("buffer", |_, this| Ok(this.0.buffer));
// 		fields.add_field_method_set("buffer", |_, this, val| Ok(this.0.buffer = val));
// 
// 		fields.add_field_method_get("start", |_, this| Ok(this.0.start.into()));
// 		fields.add_field_method_set("start", |_, this, (val,):(LuaRowCol,)| Ok(this.0.start = Some(val.0)));
// 
// 		fields.add_field_method_get("end", |_, this| Ok(this.0.end.unwrap_or_default()));
// 		fields.add_field_method_set("end", |_, this, val| Ok(this.0.end = Some(val)));
// 	}
// }
// 
// #[derive(derive_more::From)]
// struct LuaRowCol(CodempRowCol);
// impl LuaUserData for LuaRowCol {
// 	fn add_fields<'lua, F: LuaUserDataFields<'lua, Self>>(fields: &mut F) {
// 		fields.add_field_method_get("row", |_, this| Ok(this.0.col));
// 		fields.add_field_method_set("row", |_, this, val| Ok(this.0.col = val));
// 
// 		fields.add_field_method_get("col", |_, this| Ok(this.0.col));
// 		fields.add_field_method_set("col", |_, this, val| Ok(this.0.col = val));
// 	}
// }



/// create a new buffer in current workspace
fn create(_: &Lua, (path, content): (String, Option<String>)) -> LuaResult<()> {
	CODEMP_INSTANCE.create(&path, content.as_deref())
		.map_err(LuaCodempError::from)?;
	Ok(())
}



/// attach to remote buffer and start processing buffer events
fn attach(_: &Lua, (path,): (String,)) -> LuaResult<LuaBufferController> {
	let controller = CODEMP_INSTANCE.attach(&path)
		.map_err(LuaCodempError::from)?;
	Ok(LuaBufferController(controller))
}

#[derive(Debug, derive_more::From)]
struct LuaBufferController(Arc<CodempBufferController>);
impl LuaUserData for LuaBufferController {
	fn add_methods<'lua, M: LuaUserDataMethods<'lua, Self>>(methods: &mut M) {
		methods.add_meta_method(LuaMetaMethod::ToString, |_, this, ()| Ok(format!("{:?}", this)));
		methods.add_method("delta", |_, this, (start, txt, end):(usize, String, usize)| {
			match this.0.delta(start, &txt, end) {
				Some(op) => Ok(this.0.send(op).map_err(LuaCodempError::from)?),
				None => Ok(()),
			}
		});
		methods.add_method("replace", |_, this, txt:String| {
			match this.0.replace(&txt) {
				Some(op) => Ok(this.0.send(op).map_err(LuaCodempError::from)?),
				None => Ok(()),
			}
		});
		methods.add_method("insert", |_, this, (txt, pos):(String, u64)| {
			Ok(this.0.send(this.0.insert(&txt, pos)).map_err(LuaCodempError::from)?)
		});
		methods.add_method("recv", |_, this, ()| {
			let change = this.0.blocking_recv(CODEMP_INSTANCE.rt())
				.map_err(LuaCodempError::from)?;
			Ok(LuaTextChange(change))
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
		fields.add_field_method_get("start",   |_, this| Ok(this.0.span.start));
		fields.add_field_method_get("finish",  |_, this| Ok(this.0.span.end));
	}

	fn add_methods<'lua, M: LuaUserDataMethods<'lua, Self>>(methods: &mut M) {
		methods.add_meta_method(LuaMetaMethod::ToString, |_, this, ()| Ok(format!("{:?}", this)));
	}
}



#[mlua::lua_module]
fn libcodemp_nvim(lua: &Lua) -> LuaResult<LuaTable> {
	let exports = lua.create_table()?;
	exports.set("connect", lua.create_function(connect)?)?;
	exports.set("join",    lua.create_function(join)?)?;
	exports.set("create",  lua.create_function(create)?)?;
	exports.set("attach",  lua.create_function(attach)?)?;
	exports.set("get_cursor", lua.create_function(get_cursor)?)?;
	Ok(exports)
}
