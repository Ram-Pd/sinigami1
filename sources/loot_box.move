/// Module: loot_box_system::loot_box
/// 
/// A loot box system where players can purchase loot boxes using fungible tokens
/// and receive randomly generated in-game items (NFTs) with varying rarity levels.
/// 
/// The randomness is verifiable and tamper-proof using Sui's native on-chain randomness.
module loot_box::loot_box {
    // ===== Imports =====
    use sui::coin::{Self, Coin};
    use sui::event;
    use sui::random::{Self, Random};
    use sui::object::{Self, UID, ID};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use sui::dynamic_field;

    // ===== Error Codes =====
    /// Error when payment amount is insufficient
    const EInsufficientPayment: u64 = 0;
    /// Error when caller is not the admin
    const ENotAdmin: u64 = 1;
    /// Error when rarity weights don't sum to 100
    const EInvalidWeights: u64 = 2;

    // ===== Constants =====
    /// Default price for a loot box (in token base units)
    const DEFAULT_LOOT_BOX_PRICE: u64 = 100;

    // Rarity tier constants
    const RARITY_COMMON: u8 = 0;
    const RARITY_RARE: u8 = 1;
    const RARITY_EPIC: u8 = 2;
    const RARITY_LEGENDARY: u8 = 3;

    // Default rarity weights (must sum to 100)
    const DEFAULT_COMMON_WEIGHT: u8 = 60;
    const DEFAULT_RARE_WEIGHT: u8 = 25;
    const DEFAULT_EPIC_WEIGHT: u8 = 12;
    const DEFAULT_LEGENDARY_WEIGHT: u8 = 3;

    // ===== Structs =====

    /// Shared object storing game configuration
    /// Contains rarity weights, loot box price, and treasury
    public struct GameConfig<phantom T> has key {
        id: UID,
        /// Weight for Common rarity (0-100)
        common_weight: u8,
        /// Weight for Rare rarity (0-100)
        rare_weight: u8,
        /// Weight for Epic rarity (0-100)
        epic_weight: u8,
        /// Weight for Legendary rarity (0-100)
        legendary_weight: u8,
        /// Price to purchase one loot box
        loot_box_price: u64,
        /// Treasury collecting payments
        treasury: Coin<T>,
    }

    /// Capability granting admin privileges
    /// Holder can update game configuration
    public struct AdminCap has key, store {
        id: UID,
    }

    /// Owned object representing an unopened loot box
    /// Must be opened to receive a GameItem
    public struct LootBox has key, store {
        id: UID,
    }

    /// NFT representing an in-game item
    /// Has rarity tier and power level determined by randomness
    public struct GameItem has key, store {
        id: UID,
        /// Name of the item
        name: std::string::String,
        /// Rarity tier (0=Common, 1=Rare, 2=Epic, 3=Legendary)
        rarity: u8,
        /// Power level within the rarity's range
        power: u8,
    }

    // ===== Events =====

    /// Emitted when a loot box is opened
    public struct LootBoxOpened has copy, drop {
        /// ID of the minted GameItem
        item_id: ID,
        /// Rarity tier of the item
        rarity: u8,
        /// Power level of the item
        power: u8,
        /// Address of the player who opened the box
        owner: address,
    }

    // ===== Public Functions =====

    /// Initialize the game with default configuration
    /// Creates a shared GameConfig and transfers AdminCap to the caller
    /// 
    /// # Type Parameters
    /// * `T` - The fungible token type used for payments
    /// 
    /// # Arguments
    /// * `ctx` - Transaction context
    public fun init_game<T>(ctx: &mut TxContext) {
        let config = GameConfig<T> {
            id: object::new(ctx),
            common_weight: DEFAULT_COMMON_WEIGHT,
            rare_weight: DEFAULT_RARE_WEIGHT,
            epic_weight: DEFAULT_EPIC_WEIGHT,
            legendary_weight: DEFAULT_LEGENDARY_WEIGHT,
            loot_box_price: DEFAULT_LOOT_BOX_PRICE,
            treasury: coin::zero<T>(ctx),
        };
        transfer::share_object(config);
        
        let admin_cap = AdminCap {
            id: object::new(ctx),
        };
        transfer::public_transfer(admin_cap, tx_context::sender(ctx));
    }

    /// Purchase a loot box by paying the required token amount
    /// 
    /// # Type Parameters
    /// * `T` - The fungible token type used for payments
    /// 
    /// # Arguments
    /// * `config` - Shared GameConfig object
    /// * `payment` - Coin used for payment (must be >= loot_box_price)
    /// * `ctx` - Transaction context
    /// 
    /// # Returns
    /// * `LootBox` - An unopened loot box object
    public fun purchase_loot_box<T>(
        config: &mut GameConfig<T>,
        payment: Coin<T>,
        ctx: &mut TxContext
    ): LootBox {
        assert!(coin::value(&payment) >= config.loot_box_price, EInsufficientPayment);
        coin::join(&mut config.treasury, payment);
        LootBox {
            id: object::new(ctx),
        }
    }

    /// Open a loot box and receive a random GameItem
    /// 
    /// IMPORTANT: This function MUST be marked as `entry` (not `public`) 
    /// to securely use on-chain randomness. This prevents the random value
    /// from being inspected by other functions before commitment.
    /// 
    /// # Type Parameters
    /// * `T` - The fungible token type used for payments
    /// 
    /// # Arguments
    /// * `config` - Shared GameConfig to read rarity weights
    /// * `loot_box` - The loot box to open (will be destroyed)
    /// * `r` - The Random object from address 0x8
    /// * `ctx` - Transaction context
    entry fun open_loot_box<T>(
        config: &mut GameConfig<T>,
        loot_box: LootBox,
        r: &Random,
        ctx: &mut TxContext
    ) {
        let LootBox { id: box_id } = loot_box;
        object::delete(box_id);

        let sender = tx_context::sender(ctx);

        let mut pity_counter = 0u64;
        if (dynamic_field::exists_(&config.id, sender)) {
            pity_counter = *dynamic_field::borrow(&config.id, sender);
        };

        let mut gen = random::new_generator(r, ctx);
        let mut rarity;

        if (pity_counter >= 30) {
            rarity = RARITY_LEGENDARY;
            if (dynamic_field::exists_(&config.id, sender)) {
                let counter_mut_ref: &mut u64 = dynamic_field::borrow_mut(&mut config.id, sender);
                *counter_mut_ref = 0;
            } else {
                dynamic_field::add(&mut config.id, sender, 0u64);
            };
        } else {
            let roll = random::generate_u8_in_range(&mut gen, 0, 99);
            rarity = determine_rarity(roll, config.common_weight, config.rare_weight, config.epic_weight);
            if (dynamic_field::exists_(&config.id, sender)) {
                let counter_mut_ref: &mut u64 = dynamic_field::borrow_mut(&mut config.id, sender);
                if (rarity == RARITY_LEGENDARY) {
                    *counter_mut_ref = 0;
                } else {
                    *counter_mut_ref = *counter_mut_ref + 1;
                };
            } else {
                if (rarity == RARITY_LEGENDARY) {
                    dynamic_field::add(&mut config.id, sender, 0u64);
                } else {
                    dynamic_field::add(&mut config.id, sender, 1u64);
                };
            };
        };

        let (min_power, max_power) = get_power_range(rarity);
        let power = random::generate_u8_in_range(&mut gen, min_power, max_power);
        let item_name = generate_item_name(rarity);

        let item = GameItem {
            id: object::new(ctx),
            name: item_name,
            rarity,
            power,
        };

        let item_id = object::id(&item);

        event::emit(LootBoxOpened {
            item_id,
            rarity,
            power,
            owner: sender,
        });

        transfer::public_transfer(item, sender);
    }

    /// Get the stats of a GameItem
    /// 
    /// # Arguments
    /// * `item` - Reference to the GameItem
    /// 
    /// # Returns
    /// * `(String, u8, u8)` - Tuple of (name, rarity, power)
    public fun get_item_stats(item: &GameItem): (std::string::String, u8, u8) {
        (item.name, item.rarity, item.power)
    }

    /// Transfer a GameItem to another address
    /// 
    /// # Arguments
    /// * `item` - The GameItem to transfer
    /// * `recipient` - Address to receive the item
    public fun transfer_item(item: GameItem, recipient: address) {
        transfer::public_transfer(item, recipient);
    }

    /// Burn (destroy) an unwanted GameItem
    /// 
    /// # Arguments
    /// * `item` - The GameItem to destroy
    public fun burn_item(item: GameItem) {
        let GameItem { id, name: _, rarity: _, power: _ } = item;
        object::delete(id);
    }

    /// Update the rarity weights (admin only)
    /// 
    /// # Type Parameters
    /// * `T` - The fungible token type
    /// 
    /// # Arguments
    /// * `_admin` - AdminCap proving admin privileges
    /// * `config` - Mutable reference to GameConfig
    /// * `common` - New weight for Common rarity
    /// * `rare` - New weight for Rare rarity
    /// * `epic` - New weight for Epic rarity
    /// * `legendary` - New weight for Legendary rarity
    public fun update_rarity_weights<T>(
        _admin: &AdminCap,
        config: &mut GameConfig<T>,
        common: u8,
        rare: u8,
        epic: u8,
        legendary: u8
    ) {
        assert!((common as u64) + (rare as u64) + (epic as u64) + (legendary as u64) == 100, EInvalidWeights);
        config.common_weight = common;
        config.rare_weight = rare;
        config.epic_weight = epic;
        config.legendary_weight = legendary;
    }

    // ===== Helper Functions =====

    /// Determine rarity tier based on random roll and weights
    /// 
    /// # Arguments
    /// * `roll` - Random number 0-99
    /// * `common_weight` - Weight for Common
    /// * `rare_weight` - Weight for Rare
    /// * `epic_weight` - Weight for Epic
    /// 
    /// # Returns
    /// * `u8` - Rarity tier constant
    fun determine_rarity(roll: u8, common_weight: u8, rare_weight: u8, epic_weight: u8): u8 {
        if (roll < common_weight) {
            RARITY_COMMON
        } else if (roll < common_weight + rare_weight) {
            RARITY_RARE
        } else if (roll < common_weight + rare_weight + epic_weight) {
            RARITY_EPIC
        } else {
            RARITY_LEGENDARY
        }
    }

    /// Generate item name based on rarity
    /// 
    /// # Arguments
    /// * `rarity` - The rarity tier
    /// 
    /// # Returns
    /// * `String` - Generated item name
    fun generate_item_name(rarity: u8): std::string::String {
        if (rarity == RARITY_COMMON) {
            std::string::utf8(b"Common Sword")
        } else if (rarity == RARITY_RARE) {
            std::string::utf8(b"Rare Blade")
        } else if (rarity == RARITY_EPIC) {
            std::string::utf8(b"Epic Weapon")
        } else {
            std::string::utf8(b"Legendary Artifact")
        }
    }

    /// Calculate power range based on rarity
    /// 
    /// # Arguments
    /// * `rarity` - The rarity tier
    /// 
    /// # Returns
    /// * `(u8, u8)` - Tuple of (min_power, max_power)
    fun get_power_range(rarity: u8): (u8, u8) {
        if (rarity == RARITY_COMMON) {
            (1, 10)
        } else if (rarity == RARITY_RARE) {
            (11, 25)
        } else if (rarity == RARITY_EPIC) {
            (26, 40)
        } else {
            (41, 50)
        }
    }

    // ===== Getter Functions =====

    /// Get the current loot box price
    public fun get_loot_box_price<T>(config: &GameConfig<T>): u64 {
        config.loot_box_price
    }

    /// Get all rarity weights
    public fun get_rarity_weights<T>(config: &GameConfig<T>): (u8, u8, u8, u8) {
        (config.common_weight, config.rare_weight, config.epic_weight, config.legendary_weight)
    }
}