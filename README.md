# 🎮 Loot Box System with On-Chain Randomness
**Alkimi Hackathon - Problem Statement #2: Gaming**  
*Developed by: Ashish*

This repository contains a production-grade Web3 loot box system built with Sui Move. It allows players to purchase mystery containers and securely roll for randomized, NFT-based in-game assets using Sui's native randomness beacon.

## 🌐 Live Deployment (Sui Testnet)
The smart contract is fully deployed and initialized on the Sui Testnet. Judges can interact with the live game using the following Object IDs:

- **Package ID:** `0x884d34b722276cbe0532ac4a361de2a4a40b611fcc75feebe8173643427a67e0`
- **GameConfig (Shared Object):** `0x5dbac9e5223b2aae620c22a25d434aa103359438f34b86e70423e7234efb7e58`
- **AdminCap (Owned Object):** `0xdc09a51e558534ba4ce67083b4c1f4f8b63cae062f0ac2467fb3677627348869`
- **Sample Minted NFT (Common):** `0x8175c8ee8db1bbbf02978b52d1bec63637a64770eaa2e895c8b6c9a74d0015ad`

## ✨ Core Features & Architecture

### 1. Cryptographically Secure On-Chain Randomness (CRITICAL)
The core of the system relies on `sui::random`. To ensure absolute fairness and prevent exploiters from predicting or manipulating outcomes:
- The `open_loot_box` function is strictly marked as a public `entry fun`. This prevents malicious smart contracts from calling the function, peeking at the random result, and triggering a Programmable Transaction Block (PTB) revert if they don't roll a high-tier item.
- The `RandomGenerator` is instantiated locally inside the consuming function (`random::new_generator`) and is never passed outwardly as an argument.

### 2. Dynamic Rarity Distribution
Drop rates are governed by a shared `GameConfig` object, which administrators can dynamically update. The default distribution maps a 0-99 roll to:
- **Common:** 60% (Power Range: 1 - 10)
- **Rare:** 25% (Power Range: 11 - 25)
- **Epic:** 12% (Power Range: 26 - 40)
- **Legendary:** 3% (Power Range: 41 - 50)

### 3. Advanced Pity System (Bonus Challenge)
To protect players from extreme bad luck, the contract features a built-in pity system utilizing `sui::dynamic_field`.
- The system silently tracks consecutive non-Legendary rolls mapped directly to the user's address.
- If a player opens 30 consecutive boxes without hitting a Legendary item, the randomness engine is bypassed, and their 31st box is guaranteed to yield a Tier 3 Legendary Weapon.
- The internal counter transparently resets to 0 upon any Legendary drop.

## 🛠️ Testing Verification
The module includes a comprehensive test suite (`tests/loot_box_tests.move`) that mocks the on-chain network state (using `@0x0`) to safely test the `sui::random` generators locally.
All 11 edge-case tests pass locally, verifying:
- Correct initialization and treasury management.
- Rejection of insufficient payments.
- Secure object lifecycle management (Mint -> Transfer -> Burn).
- Complete functionality of the Dynamic Field Pity System.

## 🕹️ How to Play (Testnet CLI Instructions)
Judges can play the game directly from their terminal using Testnet SUI.

### Step 1: Purchase a Loot Box
Requires 100 SUI. Replace `<YOUR_SUI_COIN_ID>` with an active coin from your wallet, and `<YOUR_ADDRESS>` with your wallet address.

```bash
sui client ptb \
  --move-call 0x884d34b722276cbe0532ac4a361de2a4a40b611fcc75feebe8173643427a67e0::loot_box::purchase_loot_box "<0x2::sui::SUI>" "@0x5dbac9e5223b2aae620c22a25d434aa103359438f34b86e70423e7234efb7e58" "@<YOUR_SUI_COIN_ID>" \
  --assign box \
  --transfer-objects "[box]" "@<YOUR_ADDRESS>" \
  --gas-budget 50000000
```

### Step 2: Open the Loot Box & Mint NFT
Replace `<YOUR_NEW_LOOT_BOX_ID>` with the ID generated from Step 1.

```bash
sui client call \
  --package 0x884d34b722276cbe0532ac4a361de2a4a40b611fcc75feebe8173643427a67e0 \
  --module loot_box \
  --function open_loot_box \
  --type-args 0x2::sui::SUI \
  --args 0x5dbac9e5223b2aae620c22a25d434aa103359438f34b86e70423e7234efb7e58 <YOUR_NEW_LOOT_BOX_ID> 0x8 \
  --gas-budget 50000000
```

Check the `LootBoxOpened` event in the transaction output to see your new GameItem stats!
