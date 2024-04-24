module pull::pull_payments{
    use aptos_framework::event::{EventHandle, emit, emit_event};
    use std::signer;
    use aptos_framework::account;
    use std::string::{Self, String};
    use std::error;
    use std::vector;
    use aptos_framework::timestamp;
    use aptos_framework::coin::{Self, BurnCapability, FreezeCapability, MintCapability};
    use aptos_framework::managed_coin;
    use aptos_std::type_info;
    use aptos_framework::guid;
    use aptos_framework::transaction_context;

     const BASE_APTOS_PRICE:u64=100000000;
     const ETIME_EXPIRED: u64 = 1;


    use aptos_std::simple_map::{Self,SimpleMap};
    struct DeployResources has key, store{
        deployer_address: address,
        resource_address: address,
        signer_cap: account::SignerCapability,
    }
    struct Payment has copy,key,store,drop
    {
        uid:address,
        creator:address,
        receiver:address,
        start_time:u64,
        amount:u64,
        max_days:u64,
    }
    struct PaymentList has copy,key,store
    {
        payments:vector<Payment>,
    }
    struct LiquidityPoolCap has key{
        liquidity_pool_cap: account::SignerCapability,
    }
     public entry fun deploy_module<CoinType>(account:&signer, seeds: vector<u8>) 
    {
        let module_owner_address = signer::address_of(account);
        let (stake_vault, signer_cap) = account::create_resource_account(account, seeds); //resource account  
        let resource_addr = signer::address_of(&stake_vault);
        let deploy_resources = DeployResources{
            deployer_address:module_owner_address,
            resource_address:resource_addr,
            signer_cap:signer_cap,
        };
        move_to<DeployResources>(account, deploy_resources);
        coin::register<CoinType>(&stake_vault);
    } 
    public entry fun create_payment<CoinType>(account:&signer,receiver_address:address,amount:u64,max_days:u64, deployer_address:address) acquires PaymentList, DeployResources
    {
        let updatedAmount=amount*BASE_APTOS_PRICE;
        //resource account address
        let resource_addr = borrow_global<DeployResources>(deployer_address).resource_address;

        let account_addr = signer::address_of(account);
        let start_time = timestamp::now_seconds();
        let auid = transaction_context::generate_auid();
        let unique_address = transaction_context::auid_address(&auid);
        
        let payment = Payment{
            uid:unique_address,
            creator:account_addr,
            receiver:receiver_address,
            start_time:start_time,
            amount:amount,
            max_days:max_days,
        };
        if(!exists<PaymentList>(account_addr))
        {
            let payments = vector[];
            vector::push_back(&mut payments, payment);
            move_to<PaymentList>(account, PaymentList{payments});
        } else {
            let payments = borrow_global_mut<PaymentList>(account_addr);
            vector::push_back(&mut payments.payments, payment);
        };
        coin::transfer<CoinType>(account, resource_addr, updatedAmount); 
    }
    //claim payment in which when user comes to claim first take the timestamp if the timestamp is greater than the max_days then the user cannot claim the payment and deployer can claim the payment
    public entry fun claim_payment<CoinType>(account:&signer, sender_address:address, deployer_address:address) acquires PaymentList, DeployResources
    {
        let account_addr = signer::address_of(account);
        let payments = borrow_global_mut<PaymentList>(sender_address);
        // borrow the signer capability of the resource account
        let payment=borrow_global_mut<DeployResources>(deployer_address);
        let payment_signer_cap = account::create_signer_with_capability(&payment.signer_cap);

        let resource_addr = borrow_global<DeployResources>(deployer_address).resource_address;
        let index = 0;
        let found = false;
        let lens = vector::length(&payments.payments);
        while (index < lens) {
            let payment = vector::borrow_mut(&mut payments.payments, index);
            if (payment.receiver == account_addr) {
                found = true;
                let current_time = timestamp::now_seconds();
                if(current_time < payment.start_time + payment.max_days * 86400) {
                    let amount=payment.amount*BASE_APTOS_PRICE;
                    coin::transfer<CoinType>(&payment_signer_cap, account_addr, amount);
                } else {
                    assert!(false, error::not_found(ETIME_EXPIRED),);  
                    // coin::transfer<CoinType>(account, resource_addr, payment.amount);
                };
                break
            };
            index = index + 1;
        };
    }
}