use std::collections::BTreeMap;

use nvim_oxi as oxi;
use oxi::{api::{opts::{CreateCommandOpts, CreateAugroupOpts, CreateAutocmdOpts, GetTextOpts}, types::{CommandNArgs, CommandArgs}, Buffer}, libuv::AsyncHandle};

use codemp::{prelude::*, Controller, tokio::sync::mpsc, errors::IgnorableError, proto::{RowCol, CursorEvent}, buffer::factory::OperationFactory};
use codemp::instance::RUNTIME;

#[derive(Default)]
struct CursorStorage {
	storage: BTreeMap<String, u32>
}

fn multiline_hl(buf: &mut Buffer, namespace: u32, hl: &str, start: RowCol, end: RowCol) -> oxi::Result<()> {
	for i in start.row..=end.row {
		if i == start.row && i == end.row {
			buf.add_highlight(namespace, hl, i as usize, (start.col as usize)..=(end.col as usize))?;
		} else if i == start.row {
			buf.add_highlight(namespace, hl, i as usize, (start.col as usize)..)?;
		} else if i == end.row {
			buf.add_highlight(namespace, hl, i as usize, 0..=(end.col as usize))?;
		} else {
			buf.add_highlight(namespace, hl, i as usize, 0..)?;
		}
	}

	Ok(())
}

fn byte2rowcol(buf: &Buffer, index: usize) -> RowCol {
	buf.get_offset(index)
	
	oxi::api::
}

fn multiline_set_text(buf: &mut Buffer, change: CodempTextChange) -> oxi::Result<()> {
	for i in change.span


	Ok(())
}

fn cursor_position() -> oxi::Result<CodempCursorPosition> {
	let buf = oxi::api::get_current_buf().get_name()?;
	let cur = oxi::api::get_current_win().get_cursor()?;
	Ok(CodempCursorPosition {
		buffer: buf.to_str().unwrap_or("").to_string(),
		start: Some(RowCol { row: cur.0 as i32, col: cur.1 as i32 }),
		end: Some(RowCol { row: cur.0 as i32, col: cur.1 as i32 +1 }),
	})
}

fn buffer_content(buf: &Buffer) -> oxi::Result<String> {
	let mut out = String::new();
	for line in buf.get_text(0.., 0, 0, &GetTextOpts::default())? {
		out.push_str(&line.to_string_lossy());
		out.push('\n');
	}
	Ok(out)
}

impl CursorStorage {
	pub fn update(&mut self, user: &str, pos: Option<CodempCursorPosition>) -> oxi::Result<()> {
		let mut buf = oxi::api::get_current_buf();

		if let Some(prev) = self.storage.get(user) {
			buf.clear_namespace(*prev, 0..)?;
		}

		if let Some(position) = pos {
			let namespace = oxi::api::create_namespace(user);
			// TODO don't hardcode highlight color but create one for each user
			multiline_hl(&mut buf, namespace, "ErrorMsg", position.start(), position.end())?;
			self.storage.insert(user.into(), namespace);
		}

		Ok(())
	}
}

#[oxi::module]
fn api() -> oxi::Result<()> {
	oxi::api::create_user_command(
		"Connect",
		|args: CommandArgs| {
			let addr = args.args.unwrap_or("http://alemi.dev:50051".into());

			RUNTIME.block_on(CODEMP_INSTANCE.connect(&addr))
				.map_err(|e| nvim_oxi::api::Error::Other(format!("xx could not connect: {}", e)))?;

			oxi::print!("++ connected to {}", addr);
			Ok(())
		},
		&CreateCommandOpts::builder()
			.desc("connect to codemp server and start plugin")
			.nargs(CommandNArgs::ZeroOrOne)
			.build(),
	)?;

	oxi::api::create_user_command(
		"Join",
		|args: CommandArgs| {
			let workspace = args.args.expect("one arg required but not provided");

			let controller = RUNTIME.block_on(CODEMP_INSTANCE.join(&workspace))
				.map_err(|e| nvim_oxi::api::Error::Other(format!("xx could not join: {}", e)))?;

			let (tx, mut rx) = mpsc::unbounded_channel::<CursorEvent>();
			let mut container = CursorStorage::default();

			let handle = AsyncHandle::new(move || {
				while let Ok(x) = rx.try_recv() { // TODO do this inside oxi::schedule() to not block vim
					container.update(&x.user, x.position)?;
				}
				Ok::<_, oxi::Error>(())
			}).map_err(|e| oxi::api::Error::Other(format!("xx could not create handle: {}", e)))?;

			controller.clone().callback(move |x| {
				tx.send(x).unwrap_or_warn("could not enqueue callback");
				handle.send().unwrap_or_warn("could not wake async handle");
			});

			let au = oxi::api::create_augroup(&workspace, &CreateAugroupOpts::builder().clear(true).build())?;
			oxi::api::create_autocmd(
			[ "CursorMovedI", "CursorMoved", "CompleteDone", "InsertEnter", "InsertLeave" ],
				&CreateAutocmdOpts::builder()
					.group(au)
					.desc("update cursor position")
					.callback(move |_x| {
						RUNTIME.block_on(controller.send(cursor_position()?))
							.map_err(|e| oxi::api::Error::Other(format!("could not send cursor position: {}", e)))?;
						Ok::<bool, oxi::Error>(true)
					})
					.build()
			)?;

			oxi::print!("++ joined workspace session '{}'", workspace);
			Ok(())
		},
		&CreateCommandOpts::builder()
			.desc("join a codemp workspace and start processing cursors")
			.nargs(CommandNArgs::One)
			.build(),
	)?;

	oxi::api::create_user_command(
		"Attach",
		|args: CommandArgs| {
			let buffer = args.args.expect("one arg required but not provided");

			let controller = RUNTIME.block_on(CODEMP_INSTANCE.attach(&buffer))
				.map_err(|e| nvim_oxi::api::Error::Other(format!("xx could not attach: {}", e)))?;

			let buf = oxi::api::get_current_buf();
			let (tx, mut rx) = mpsc::unbounded_channel::<CodempTextChange>();
			// let mut container = CursorStorage::default();

			let handle = AsyncHandle::new(move || {
				while let Ok(x) = rx.try_recv() { // TODO do this inside oxi::schedule() to not block vim
					buf.set_text(line_range, start_col, end_col, replacement)
				}
				Ok::<_, oxi::Error>(())
			}).map_err(|e| oxi::api::Error::Other(format!("xx could not create handle: {}", e)))?;

			controller.clone().callback(move |x| {
				tx.send(x).unwrap_or_warn("could not enqueue callback");
				handle.send().unwrap_or_warn("could not wake async handle");
			});

			let au = oxi::api::create_augroup(&buffer, &CreateAugroupOpts::builder().clear(true).build())?;
			oxi::api::create_autocmd(
			[ "CursorMovedI", "CursorMoved", "CompleteDone", "InsertEnter", "InsertLeave" ],
				&CreateAutocmdOpts::builder()
					.group(au)
					.desc("update cursor position")
					.callback(move |_x| {
						if let Some(op) = controller.replace(&buffer_content(&buf)?) {
							RUNTIME.block_on(controller.send(op))
								.map_err(|e| oxi::api::Error::Other(format!("could not send cursor position: {}", e)))?;
							Ok::<bool, oxi::Error>(true)
						} else {
							Ok::<bool, oxi::Error>(false)
						}
						
					})
					.build()
			)?;

			oxi::print!("++ attached to buffer '{}'", buffer);
			Ok(())
		},
		&CreateCommandOpts::builder()
			.desc("join a codemp workspace and start processing cursors")
			.nargs(CommandNArgs::One)
			.build(),
	)?;

	Ok(())
}
