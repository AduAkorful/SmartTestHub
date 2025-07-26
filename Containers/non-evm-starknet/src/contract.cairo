#[starknet::contract]
mod SampleContract {
    use starknet::ContractAddress;
    use starknet::get_caller_address;
    use starknet::get_contract_address;
    use starknet::storage_access::StorageBaseAddress;
    
    #[storage]
    struct Storage {
        owner: ContractAddress,
        counter: u256,
        balances: LegacyMap<ContractAddress, u256>,
        paused: bool,
        total_supply: u256,
    }
    
    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        CounterIncreased: CounterIncreased,
        Transfer: Transfer,
        OwnershipTransferred: OwnershipTransferred,
        Paused: Paused,
        Unpaused: Unpaused,
    }
    
    #[derive(Drop, starknet::Event)]
    struct CounterIncreased {
        #[key]
        caller: ContractAddress,
        new_value: u256,
    }
    
    #[derive(Drop, starknet::Event)]
    struct Transfer {
        #[key]
        from: ContractAddress,
        #[key]
        to: ContractAddress,
        value: u256,
    }
    
    #[derive(Drop, starknet::Event)]
    struct OwnershipTransferred {
        #[key]
        previous_owner: ContractAddress,
        #[key]
        new_owner: ContractAddress,
    }
    
    #[derive(Drop, starknet::Event)]
    struct Paused {
        account: ContractAddress,
    }
    
    #[derive(Drop, starknet::Event)]
    struct Unpaused {
        account: ContractAddress,
    }
    
    #[constructor]
    fn constructor(ref self: ContractState, initial_owner: ContractAddress, initial_supply: u256) {
        self.owner.write(initial_owner);
        self.counter.write(0);
        self.total_supply.write(initial_supply);
        self.balances.write(initial_owner, initial_supply);
        self.paused.write(false);
    }
    
    // Modifiers
    fn only_owner(self: @ContractState) {
        let caller = get_caller_address();
        assert(caller == self.owner.read(), 'Only owner can call');
    }
    
    fn when_not_paused(self: @ContractState) {
        assert(!self.paused.read(), 'Contract is paused');
    }
    
    #[external(v0)]
    impl SampleContractImpl of super::ISampleContract<ContractState> {
        // Counter functions
        fn increment_counter(ref self: ContractState) {
            self.when_not_paused();
            let current = self.counter.read();
            let new_value = current + 1;
            self.counter.write(new_value);
            
            self.emit(CounterIncreased {
                caller: get_caller_address(),
                new_value: new_value,
            });
        }
        
        fn increment_by(ref self: ContractState, amount: u256) {
            self.when_not_paused();
            assert(amount > 0, 'Amount must be positive');
            
            let current = self.counter.read();
            let new_value = current + amount;
            // Check for overflow
            assert(new_value >= current, 'Counter overflow');
            
            self.counter.write(new_value);
            
            self.emit(CounterIncreased {
                caller: get_caller_address(),
                new_value: new_value,
            });
        }
        
        fn reset_counter(ref self: ContractState) {
            self.only_owner();
            self.counter.write(0);
        }
        
        // Token-like functions
        fn transfer(ref self: ContractState, to: ContractAddress, amount: u256) {
            self.when_not_paused();
            let caller = get_caller_address();
            
            assert(to.is_non_zero(), 'Invalid recipient');
            assert(amount > 0, 'Amount must be positive');
            
            let sender_balance = self.balances.read(caller);
            assert(sender_balance >= amount, 'Insufficient balance');
            
            self.balances.write(caller, sender_balance - amount);
            let recipient_balance = self.balances.read(to);
            
            // Check for overflow
            let new_balance = recipient_balance + amount;
            assert(new_balance >= recipient_balance, 'Balance overflow');
            
            self.balances.write(to, new_balance);
            
            self.emit(Transfer {
                from: caller,
                to: to,
                value: amount,
            });
        }
        
        fn mint(ref self: ContractState, to: ContractAddress, amount: u256) {
            self.only_owner();
            self.when_not_paused();
            
            assert(to.is_non_zero(), 'Invalid recipient');
            assert(amount > 0, 'Amount must be positive');
            
            let recipient_balance = self.balances.read(to);
            let new_balance = recipient_balance + amount;
            assert(new_balance >= recipient_balance, 'Balance overflow');
            
            let current_supply = self.total_supply.read();
            let new_supply = current_supply + amount;
            assert(new_supply >= current_supply, 'Supply overflow');
            
            self.balances.write(to, new_balance);
            self.total_supply.write(new_supply);
            
            self.emit(Transfer {
                from: Zeroable::zero(),
                to: to,
                value: amount,
            });
        }
        
        // Admin functions
        fn transfer_ownership(ref self: ContractState, new_owner: ContractAddress) {
            self.only_owner();
            assert(new_owner.is_non_zero(), 'Invalid new owner');
            
            let previous_owner = self.owner.read();
            self.owner.write(new_owner);
            
            self.emit(OwnershipTransferred {
                previous_owner: previous_owner,
                new_owner: new_owner,
            });
        }
        
        fn pause(ref self: ContractState) {
            self.only_owner();
            assert(!self.paused.read(), 'Already paused');
            
            self.paused.write(true);
            
            self.emit(Paused {
                account: get_caller_address(),
            });
        }
        
        fn unpause(ref self: ContractState) {
            self.only_owner();
            assert(self.paused.read(), 'Not paused');
            
            self.paused.write(false);
            
            self.emit(Unpaused {
                account: get_caller_address(),
            });
        }
    }
    
    #[external(v0)]
    impl SampleContractViewImpl of super::ISampleContractView<ContractState> {
        fn get_counter(self: @ContractState) -> u256 {
            self.counter.read()
        }
        
        fn get_owner(self: @ContractState) -> ContractAddress {
            self.owner.read()
        }
        
        fn balance_of(self: @ContractState, account: ContractAddress) -> u256 {
            self.balances.read(account)
        }
        
        fn total_supply(self: @ContractState) -> u256 {
            self.total_supply.read()
        }
        
        fn is_paused(self: @ContractState) -> bool {
            self.paused.read()
        }
        
        fn foo(self: @ContractState) -> felt252 {
            42
        }
    }
}

#[starknet::interface]
trait ISampleContract<TContractState> {
    fn increment_counter(ref self: TContractState);
    fn increment_by(ref self: TContractState, amount: u256);
    fn reset_counter(ref self: TContractState);
    fn transfer(ref self: TContractState, to: starknet::ContractAddress, amount: u256);
    fn mint(ref self: TContractState, to: starknet::ContractAddress, amount: u256);
    fn transfer_ownership(ref self: TContractState, new_owner: starknet::ContractAddress);
    fn pause(ref self: TContractState);
    fn unpause(ref self: TContractState);
}

#[starknet::interface]
trait ISampleContractView<TContractState> {
    fn get_counter(self: @TContractState) -> u256;
    fn get_owner(self: @TContractState) -> starknet::ContractAddress;
    fn balance_of(self: @TContractState, account: starknet::ContractAddress) -> u256;
    fn total_supply(self: @TContractState) -> u256;
    fn is_paused(self: @TContractState) -> bool;
    fn foo(self: @TContractState) -> felt252;
}
