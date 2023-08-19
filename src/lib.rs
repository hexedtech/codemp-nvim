use std::{collections::BTreeMap, fs::File, time::{SystemTime, UNIX_EPOCH}};

use nvim_oxi as oxi;
use oxi::{api::{opts::{CreateCommandOpts, CreateAugroupOpts, CreateAutocmdOpts}, types::{CommandNArgs, CommandArgs}, Buffer}, libuv::AsyncHandle};

use codemp::{prelude::*, Controller, tokio::sync::mpsc, errors::IgnorableError, proto::{RowCol, CursorEvent}, buffer::factory::OperationFactory};

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

fn byte2rowcol(buf: &Buffer, index: usize) -> oxi::Result<RowCol> {
	// TODO lmao this impl
	let mut row = 0;
	loop {
		let offset = buf.get_offset(row+1)?;
		if offset > index { // found line
			let base = buf.get_offset(row)?;
			return Ok(RowCol { row: row as i32, col: (index - base) as i32 });
		}
		row += 1;
	}
}

fn multiline_set_text(buf: &mut Buffer, change: CodempTextChange) -> oxi::Result<()> {
	let start = byte2rowcol(buf, change.span.start)?;
	let end = byte2rowcol(buf, change.span.end)?;
	buf.set_text(
		start.row as usize ..= end.row as usize,
		start.col as usize,
		end.col as usize,
		change.content.split('\n')
	)?;
	Ok(())
}

fn err(e: impl std::error::Error, msg: &str) -> oxi::api::Error {
	oxi::api::Error::Other(format!("{} -- {}", msg, e))
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
	for line in buf.get_lines(0.., false)? {
		out.push_str(&line.to_string_lossy());
		out.push('\n');
	}
	Ok(out.trim().to_string())
}

fn buffer_set(buf: &mut Buffer, content: &str) -> Result<(), oxi::api::Error> {
	buf.set_lines(0.., false, content.split('\n'))
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
fn codemp_nvim() -> oxi::Result<()> {
	oxi::api::create_user_command(
		"Connect",
		|args: CommandArgs| {
			let addr = args.args.unwrap_or("http://127.0.0.1:50051".into());

			CODEMP_INSTANCE.connect(&addr)
				.map_err(|e| err(e, "xx could not connect: {}"))?;

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
			let workspace = args.args.unwrap_or("default".into());

			let controller = CODEMP_INSTANCE.join(&workspace)
				.map_err(|e| err(e, "xx could not join"))?;

			let (tx, mut rx) = mpsc::unbounded_channel::<CursorEvent>();
			let mut container = CursorStorage::default();

			let handle = AsyncHandle::new(move || {
				while let Ok(x) = rx.try_recv() { // TODO do this inside oxi::schedule() to not block vim
					tracing::info!("cursor move: {:?}", x);
					oxi::print!("cursor>> {:?}", x);
					container.update(&x.user, x.position)?;
				}
				Ok::<_, oxi::Error>(())
			}).map_err(|e| err(e, "xx could not create handle"))?;

			let (stop, stop_rx) = mpsc::unbounded_channel();

			controller.clone().callback(CODEMP_INSTANCE.rt(), stop_rx, move |x| {
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
						let cur = cursor_position()?;
						tracing::info!("running cursor callback: {:?}", cur);
						let _c = controller.clone();
						CODEMP_INSTANCE.rt().spawn(async move {
							_c.send(cur).await.unwrap_or_warn("could not enqueue cursor update");
						});
						Ok::<bool, oxi::Error>(true)
					})
					.build()
			)?;

			oxi::api::create_autocmd(
				[ "ExitPre" ],
				&CreateAutocmdOpts::builder()
					.group(au)
					.desc("remove cursor callbacks")
					.callback(move |_x| {
						oxi::print!("stopping cursor worker");
						stop.send(()).unwrap_or_warn("could not stop cursor callback worker");
						CODEMP_INSTANCE.leave_workspace().unwrap_or_warn("could not leave workspace");
						tracing::info!("left workspace");
						oxi::print!("stopped cursor worker and leaving workspace");
						Ok::<bool, oxi::Error>(true)
					})
					.build()
			)?;

			oxi::print!("++ joined workspace session '{}'", workspace);
			Ok(())
		},
		&CreateCommandOpts::builder()
			.desc("join a codemp workspace and start processing cursors")
			.nargs(CommandNArgs::ZeroOrOne) // TODO wtf if I put "One" I cannot require codemp_nvim ('invalid nargs')
			.build(),
	)?;

	oxi::api::create_user_command(
		"Attach",
		|args: CommandArgs| {
			let buffer = args.args.expect("one arg required but not provided");

			let controller = CODEMP_INSTANCE.attach(&buffer)
				.map_err(|e| err(e, "xx could not attach"))?;

			let buf = oxi::api::get_current_buf();
			let mut buf_m = buf.clone();

			buffer_set(&mut buf_m, &controller.content())?;

			let controller_m = controller.clone();
			let (tx, mut rx) = mpsc::unbounded_channel::<CodempTextChange>();

			let handle = AsyncHandle::new(move || {
				while let Ok(_change) = rx.try_recv() { // TODO do this inside oxi::schedule() to not block vim
					tracing::info!("buf change: {:?}", _change);
					oxi::print!("change>> {:?}", _change);
					// multiline_set_text(&mut buf_m, change)?;
					buffer_set(&mut buf_m, &controller_m.content())?;
				}
				oxi::api::exec("redraw!", false)?;
				Ok::<_, oxi::Error>(())
			}).map_err(|e| oxi::api::Error::Other(format!("xx could not create handle: {}", e)))?;

			let (stop, stop_rx) = mpsc::unbounded_channel();

			controller.clone().callback(CODEMP_INSTANCE.rt(), stop_rx, move |x| {
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
						let content = buffer_content(&buf)?;
						tracing::info!("running buffer callback -- {}", content);
						if let Some(op) = controller.replace(&content) {
							tracing::info!("it's diferent!");
							let _c = controller.clone();
							CODEMP_INSTANCE.rt().spawn(async move {
								_c.send(op).await.unwrap_or_warn("could not enqueue text change");
							});
							Ok::<bool, oxi::Error>(true)
						} else {
							Ok::<bool, oxi::Error>(false)
						}
						
					})
					.build()
			)?;

			oxi::api::create_autocmd(
				[ "ExitPre" ],
				&CreateAutocmdOpts::builder()
					.group(au)
					.desc("remove buffer callbacks")
					.callback(move |_x| {
						stop.send(()).unwrap_or_warn("could not stop cursor callback worker");
						Ok::<bool, oxi::Error>(true)
					})
					.build()
			)?;

			oxi::print!("++ attached to buffer '{}'", buffer);
			Ok(())
		},
		&CreateCommandOpts::builder()
			.desc("attach to buffer, sending and receiving changes")
			.nargs(CommandNArgs::ZeroOrOne) // TODO wtf if I put "One" I cannot require codemp_nvim ('invalid nargs')
			.build(),
	)?;

	oxi::api::create_user_command(
		"Create",
		|args: CommandArgs| {
			let path = args.args.expect("one arg required but not provided");

			CODEMP_INSTANCE.create(&path, None)
				.map_err(|e| nvim_oxi::api::Error::Other(format!("xx could not attach: {}", e)))?;

			oxi::print!("++ created buffer '{}'", path);
			Ok(())
		},
		&CreateCommandOpts::builder()
			.desc("create a new buffer")
			.nargs(CommandNArgs::ZeroOrOne) // TODO wtf if I put "One" I cannot require codemp_nvim ('invalid nargs')
			.build(),
	)?;

	Ok(())
}
