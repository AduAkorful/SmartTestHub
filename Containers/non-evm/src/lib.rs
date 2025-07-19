use solana_program::{
    account_info::AccountInfo,
    entrypoint,
    entrypoint::ProgramResult,
    pubkey::Pubkey,
    msg,
};

entrypoint!(process_instruction);

fn process_instruction(
    _program_id: &Pubkey,         // unused, prefixed with _
    _accounts: &[AccountInfo],    // unused, prefixed with _
    _instruction_data: &[u8],     // unused, prefixed with _
) -> ProgramResult {
    msg!("Hello, Solana!");
    Ok(())
}
