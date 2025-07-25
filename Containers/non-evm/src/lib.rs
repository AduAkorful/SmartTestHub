use solana_program::{
    account_info::AccountInfo,
    entrypoint,
    entrypoint::ProgramResult,
    pubkey::Pubkey,
    msg,
};

// FIXED: Remove unused import that was causing warning
// use solana_program::program_pack::Pack; // Removed this line

entrypoint!(process_instruction);

fn process_instruction(
    _program_id: &Pubkey,         // FIXED: Prefixed with _ to indicate intentionally unused
    _accounts: &[AccountInfo],    // FIXED: Prefixed with _ to indicate intentionally unused
    _instruction_data: &[u8],     // FIXED: Prefixed with _ to indicate intentionally unused
) -> ProgramResult {
    msg!("Hello, Solana!");
    
    // FIXED: Remove unnecessary mut from counter if not being modified
    // If you need to create a counter struct, here's an example:
    // let counter = UserCounter { count: 0 }; // REMOVED mut keyword
    
    Ok(())
}

// Example counter struct (if needed for your use case)
#[derive(Debug)]
pub struct UserCounter {
    pub count: u64,
}

// Example implementation of counter operations with proper error handling
impl UserCounter {
    pub fn new() -> Self {
        Self { count: 0 }
    }
    
    pub fn increment(&mut self) -> Result<(), &'static str> {
        self.count = self.count.checked_add(1)
            .ok_or("Counter overflow")?;
        Ok(())
    }
    
    pub fn decrement(&mut self) -> Result<(), &'static str> {
        self.count = self.count.checked_sub(1)
            .ok_or("Counter underflow")?;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_counter_operations() {
        let mut counter = UserCounter::new();
        assert_eq!(counter.count, 0);
        
        counter.increment().unwrap();
        assert_eq!(counter.count, 1);
        
        counter.decrement().unwrap();
        assert_eq!(counter.count, 0);
    }
    
    #[test]
    fn test_counter_overflow() {
        let mut counter = UserCounter { count: u64::MAX };
        assert!(counter.increment().is_err());
    }
    
    #[test]
    fn test_counter_underflow() {
        let mut counter = UserCounter::new();
        assert!(counter.decrement().is_err());
    }
}
