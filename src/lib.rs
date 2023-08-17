use nvim_oxi as oxi;
use oxi::{api::{opts::CreateCommandOpts, types::{CommandNArgs, CommandArgs}}, libuv::AsyncHandle};

use codemp::{prelude::*, Controller, tokio::sync::mpsc, errors::IgnorableError};
use codemp::instance::RUNTIME;

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
			let (tx, mut rx) = mpsc::unbounded_channel();
			let handle = AsyncHandle::new(move || {
				while let Ok(x) = rx.try_recv() { // TODO do this inside oxi::schedule() to not block vim
					oxi::print!("cursor: {:?}", x);
				}
				Ok::<_, oxi::Error>(())
			}).map_err(|e| oxi::api::Error::Other(format!("xx could not create handle: {}", e)))?;
			controller.callback(move |x| {
				tx.send(x).unwrap_or_warn("could not enqueue callback");
				handle.send().unwrap_or_warn("could not wake async handle");
			});
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
