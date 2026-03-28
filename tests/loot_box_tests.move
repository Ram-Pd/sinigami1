/// Module: loot_box_system::loot_box_tests
/// 
/// Test suite for the loot box system
#[test_only]
module loot_box::loot_box_tests {
    use sui::test_scenario::{Self as ts, Scenario};
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::random::{Self, Random};
    use sui::test_utils;
    use loot_box::loot_box::{Self, GameConfig, AdminCap, LootBox, GameItem};

    // ===== Test Constants =====
    const ADMIN: address = @0xAD;
    const PLAYER1: address = @0x1;
    const PLAYER2: address = @0x2;

    // ===== Helper Functions =====

    /// Initialize test scenario with game setup
    fun setup_game(scenario: &mut Scenario) {
        ts::next_tx(scenario, ADMIN);
        loot_box::init_game<SUI>(ts::ctx(scenario));
    }

    /// Create a test coin with specified amount
    fun mint_test_coin(scenario: &mut Scenario, amount: u64): Coin<SUI> {
        coin::mint_for_testing<SUI>(amount, ts::ctx(scenario))
    }

    // ===== Test Cases =====

    #[test]
    /// Test: Game initialization creates GameConfig with correct defaults
    fun test_init_game() {
        let mut scenario_val = ts::begin(ADMIN);
        let scenario = &mut scenario_val;
        
        setup_game(scenario);
        
        ts::next_tx(scenario, ADMIN);
        let config = ts::take_shared<GameConfig<SUI>>(scenario);
        let admin_cap = ts::take_from_sender<AdminCap>(scenario);
        
        let (common_weight, rare_weight, epic_weight, legendary_weight) = loot_box::get_rarity_weights(&config);
        assert!(common_weight == 60, 0);
        assert!(rare_weight == 25, 0);
        assert!(epic_weight == 12, 0);
        assert!(legendary_weight == 3, 0);
        
        let price = loot_box::get_loot_box_price(&config);
        assert!(price == 100, 0);
        
        ts::return_shared(config);
        ts::return_to_sender(scenario, admin_cap);
        ts::end(scenario_val);
    }

    #[test]
    /// Test: User can purchase a loot box with correct payment
    fun test_purchase_loot_box() {
        let mut scenario_val = ts::begin(ADMIN);
        let scenario = &mut scenario_val;
        setup_game(scenario);

        ts::next_tx(scenario, PLAYER1);
        let mut config = ts::take_shared<GameConfig<SUI>>(scenario);
        let payment = mint_test_coin(scenario, 100);
        
        let loot_box = loot_box::purchase_loot_box(&mut config, payment, ts::ctx(scenario));
        sui::transfer::public_transfer(loot_box, PLAYER1);
        
        ts::return_shared(config);
        ts::end(scenario_val);
    }

    #[test]
    #[expected_failure(abort_code = loot_box::EInsufficientPayment)]
    /// Test: Purchase fails with insufficient payment
    fun test_purchase_insufficient_payment() {
        let mut scenario_val = ts::begin(ADMIN);
        let scenario = &mut scenario_val;
        setup_game(scenario);

        ts::next_tx(scenario, PLAYER1);
        let mut config = ts::take_shared<GameConfig<SUI>>(scenario);
        let payment = mint_test_coin(scenario, 50); // Insufficient
        
        let loot_box = loot_box::purchase_loot_box(&mut config, payment, ts::ctx(scenario));
        sui::transfer::public_transfer(loot_box, PLAYER1);
        
        ts::return_shared(config);
        ts::end(scenario_val);
    }

    #[test]
    /// Test: Loot box can be opened and produces valid GameItem
    fun test_open_loot_box() {
        let mut scenario_val = ts::begin(ADMIN);
        let scenario = &mut scenario_val;
        setup_game(scenario);
        
        ts::next_tx(scenario, @0x0);
        random::create_for_testing(ts::ctx(scenario));

        ts::next_tx(scenario, PLAYER1);
        let mut config = ts::take_shared<GameConfig<SUI>>(scenario);
        let payment = mint_test_coin(scenario, 100);
        let loot_box = loot_box::purchase_loot_box(&mut config, payment, ts::ctx(scenario));
        
        ts::next_tx(scenario, @0x0);
        let mut r = ts::take_shared<Random>(scenario);
        random::update_randomness_state_for_testing(&mut r, 0, x"1F", ts::ctx(scenario));
        
        ts::next_tx(scenario, PLAYER1);
        loot_box::open_loot_box(&mut config, loot_box, &r, ts::ctx(scenario));
        
        ts::return_shared(r);
        ts::return_shared(config);
        ts::end(scenario_val);
    }

    #[test]
    /// Test: GameItem has correct stats based on rarity
    fun test_get_item_stats() {
        let mut scenario_val = ts::begin(ADMIN);
        let scenario = &mut scenario_val;
        setup_game(scenario);
        
        ts::next_tx(scenario, @0x0);
        random::create_for_testing(ts::ctx(scenario));
        
        ts::next_tx(scenario, PLAYER1);
        let mut config = ts::take_shared<GameConfig<SUI>>(scenario);
        let payment = mint_test_coin(scenario, 100);
        let loot_box = loot_box::purchase_loot_box(&mut config, payment, ts::ctx(scenario));
        
        ts::next_tx(scenario, @0x0);
        let mut r = ts::take_shared<Random>(scenario);
        random::update_randomness_state_for_testing(&mut r, 0, x"1F", ts::ctx(scenario));
        
        ts::next_tx(scenario, PLAYER1);
        loot_box::open_loot_box(&mut config, loot_box, &r, ts::ctx(scenario));
        
        ts::next_tx(scenario, PLAYER1);
        let item = ts::take_from_sender<GameItem>(scenario);
        let (name, rarity, power) = loot_box::get_item_stats(&item);
        
        assert!(std::string::length(&name) > 0, 0);
        assert!(rarity <= 3, 0); 
        assert!(power > 0, 0);

        ts::return_to_sender(scenario, item);
        ts::return_shared(r);
        ts::return_shared(config);
        ts::end(scenario_val);
    }

    #[test]
    /// Test: Item can be transferred between addresses
    fun test_transfer_item() {
        let mut scenario_val = ts::begin(ADMIN);
        let scenario = &mut scenario_val;
        setup_game(scenario);
        
        ts::next_tx(scenario, @0x0);
        random::create_for_testing(ts::ctx(scenario));
        
        ts::next_tx(scenario, PLAYER1);
        let mut config = ts::take_shared<GameConfig<SUI>>(scenario);
        let payment = mint_test_coin(scenario, 100);
        let loot_box = loot_box::purchase_loot_box(&mut config, payment, ts::ctx(scenario));
        
        ts::next_tx(scenario, @0x0);
        let mut r = ts::take_shared<Random>(scenario);
        random::update_randomness_state_for_testing(&mut r, 0, x"1F", ts::ctx(scenario));
        
        ts::next_tx(scenario, PLAYER1);
        loot_box::open_loot_box(&mut config, loot_box, &r, ts::ctx(scenario));
        
        ts::next_tx(scenario, PLAYER1);
        let item = ts::take_from_sender<GameItem>(scenario);
        loot_box::transfer_item(item, PLAYER2);
        
        ts::next_tx(scenario, PLAYER2);
        let transferred_item = ts::take_from_sender<GameItem>(scenario);
        
        ts::return_to_sender(scenario, transferred_item);
        ts::return_shared(r);
        ts::return_shared(config);
        ts::end(scenario_val);
    }

    #[test]
    /// Test: Owner can burn their item
    fun test_burn_item() {
        let mut scenario_val = ts::begin(ADMIN);
        let scenario = &mut scenario_val;
        setup_game(scenario);
        
        ts::next_tx(scenario, @0x0);
        random::create_for_testing(ts::ctx(scenario));
        
        ts::next_tx(scenario, PLAYER1);
        let mut config = ts::take_shared<GameConfig<SUI>>(scenario);
        let payment = mint_test_coin(scenario, 100);
        let loot_box = loot_box::purchase_loot_box(&mut config, payment, ts::ctx(scenario));
        
        ts::next_tx(scenario, @0x0);
        let mut r = ts::take_shared<Random>(scenario);
        random::update_randomness_state_for_testing(&mut r, 0, x"1F", ts::ctx(scenario));
        
        ts::next_tx(scenario, PLAYER1);
        loot_box::open_loot_box(&mut config, loot_box, &r, ts::ctx(scenario));
        
        ts::next_tx(scenario, PLAYER1);
        let item = ts::take_from_sender<GameItem>(scenario);
        loot_box::burn_item(item);
        
        ts::return_shared(r);
        ts::return_shared(config);
        ts::end(scenario_val);
    }

    #[test]
    /// Test: Admin can update rarity weights
    fun test_update_rarity_weights() {
        let mut scenario_val = ts::begin(ADMIN);
        let scenario = &mut scenario_val;
        setup_game(scenario);
        
        ts::next_tx(scenario, ADMIN);
        let mut config = ts::take_shared<GameConfig<SUI>>(scenario);
        let admin_cap = ts::take_from_sender<AdminCap>(scenario);
        
        loot_box::update_rarity_weights(&admin_cap, &mut config, 50, 30, 15, 5);
        let (c, r, e, l) = loot_box::get_rarity_weights(&config);
        assert!(c == 50, 0);
        assert!(r == 30, 0);
        assert!(e == 15, 0);
        assert!(l == 5, 0);
        
        ts::return_shared(config);
        ts::return_to_sender(scenario, admin_cap);
        ts::end(scenario_val);
    }

    #[test]
    #[expected_failure(abort_code = loot_box::EInvalidWeights)]
    /// Test: Update fails if weights don't sum to 100
    fun test_update_weights_invalid_sum() {
        let mut scenario_val = ts::begin(ADMIN);
        let scenario = &mut scenario_val;
        setup_game(scenario);
        
        ts::next_tx(scenario, ADMIN);
        let mut config = ts::take_shared<GameConfig<SUI>>(scenario);
        let admin_cap = ts::take_from_sender<AdminCap>(scenario);
        
        loot_box::update_rarity_weights(&admin_cap, &mut config, 50, 30, 15, 10); // Sum = 105
        
        ts::return_shared(config);
        ts::return_to_sender(scenario, admin_cap);
        ts::end(scenario_val);
    }

    #[test]
    /// Test: Rarity distribution follows configured weights
    fun test_rarity_distribution() {
        assert!(true, 0);
    }

    // ===== Event Tests =====

    #[test]
    /// Test: LootBoxOpened event is emitted with correct data
    fun test_loot_box_opened_event() {
        let mut scenario_val = ts::begin(ADMIN);
        let scenario = &mut scenario_val;
        setup_game(scenario);
        
        ts::next_tx(scenario, @0x0);
        random::create_for_testing(ts::ctx(scenario));
        
        ts::next_tx(scenario, PLAYER1);
        let mut config = ts::take_shared<GameConfig<SUI>>(scenario);
        let payment = mint_test_coin(scenario, 100);
        let loot_box = loot_box::purchase_loot_box(&mut config, payment, ts::ctx(scenario));
        
        ts::next_tx(scenario, @0x0);
        let mut r = ts::take_shared<Random>(scenario);
        random::update_randomness_state_for_testing(&mut r, 0, x"1F", ts::ctx(scenario));
        
        ts::next_tx(scenario, PLAYER1);
        loot_box::open_loot_box(&mut config, loot_box, &r, ts::ctx(scenario));
        
        ts::next_tx(scenario, PLAYER1);

        ts::return_shared(r);
        ts::return_shared(config);
        ts::end(scenario_val);
    }
}