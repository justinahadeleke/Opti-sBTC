
# Opti-SBTC- Decentralized P2P sBTC Options Trading Smart Contract

This smart contract implements a decentralized, peer-to-peer options trading platform using **BTC as the underlying asset**. Built with Clarity for the **Stacks blockchain**, it allows users to **create, buy, and exercise call or put options** in a trustless and transparent environment.

---

## 🚀 Features

* **BTC Internal Balance Management**: Users can deposit and withdraw BTC (internally represented via map-based balance accounting).
* **Option Types**: Supports both `CALL` and `PUT` options.
* **Option Lifecycle**:

  * Creation by seller.
  * Purchase by buyer (handled off-chain, not implemented here).
  * On-chain exercising of options before expiry.
* **Strike and Premium Enforcement**.
* **Oracle Integration**: Manually-set BTC price (via contract owner) to support pricing in `stx-transfer?`.
* **Simple Authorization Model**: Owner-controlled BTC price oracle.

---

## 📑 Contract Structure

### ✅ Constants

```clojure
CALL = u1
PUT = u2
```

### ❗ Error Codes

| Code | Error                    |
| ---- | ------------------------ |
| `u1` | Option expired           |
| `u2` | Invalid amount           |
| `u3` | Unauthorized             |
| `u4` | Option not found         |
| `u5` | Insufficient BTC balance |
| `u6` | Option already exercised |
| `u7` | Invalid strike/premium   |
| `u8` | Option not active        |

---

## 💾 Data Structures

### `BTCBalances`

Tracks BTC deposited by users.

```clojure
{ holder: principal } => { balance: uint }
```

### `Options`

Stores metadata and status of each option.

```clojure
{ option-id: uint } => {
  creator: principal,
  buyer: (optional principal),
  option-type: uint,
  strike-price: uint,
  premium: uint,
  expiry: uint,
  btc-amount: uint,
  is-active: bool,
  is-executed: bool,
  creation-height: uint
}
```

### `UserOptions`

Associates users with their created and purchased option IDs.

```clojure
{ user: principal } => {
  created: (list 20 uint),
  purchased: (list 20 uint)
}
```

---

## 🔐 BTC Balance Management

### `deposit-btc (amount uint)`

> Increases caller's BTC balance (internal accounting).

### `withdraw-btc (amount uint)`

> Decreases caller's BTC balance.

### `transfer-btc (from principal) (to principal) (amount uint)`

> Internal utility for BTC balance transfer between users.

---

## 📈 Option Lifecycle

### `create-option (option-type uint) (strike-price uint) (premium uint) (expiry uint) (btc-amount uint)`

Creates a `CALL` or `PUT` option:

* `CALL`: BTC collateral must be locked by creator.
* `PUT`: Buyer will deposit BTC when exercising, no upfront BTC locked.

Returns: `ok option-id`

---

### `exercise-option (option-id uint)`

Allows buyer to exercise the option before expiry:

* `CALL`: Buyer pays strike in STX, receives BTC.
* `PUT`: Buyer sends BTC, receives STX.

---

### 🔧 Private Execution Functions

* `exercise-call`: Transfers STX from buyer to seller, BTC to buyer.
* `exercise-put`: Transfers STX from seller to buyer, BTC to seller.

---

## 🧠 Oracle Functions

### `set-btc-price (price uint)`

> Owner-only. Sets current BTC price (in STX or some unit).

### `get-btc-price`

> Read-only. Gets the stored BTC price.

---

## 🔍 View Functions

### `get-option (option-id uint)`

> View details of a specific option.

### `get-btc-balance (holder principal)`

> Returns internal BTC balance for a user.

### `get-user-options (user principal)`

> Shows list of created and purchased options by a user.

---

## 📋 Usage Flow

1. **Deposit BTC** using `deposit-btc`.
2. **Create Option** using `create-option`, specifying:

   * Type (CALL/PUT)
   * Strike price
   * Premium
   * Expiry (block height)
   * BTC amount
3. **Off-chain sale**: Buyer and seller agree, buyer pays premium off-chain.
4. **Buyer exercises** using `exercise-option` if profitable before expiry.
5. **Withdraw BTC** at any time (if unlocked).

---
