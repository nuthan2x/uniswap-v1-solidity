### Disclaimer

**Use at your own risk.** This is an unaudited implementation for educational and testing purposes only. Do not use in production without thorough security review.

## Uniswap V1: Vyper to Solidity Port 

Also added **flash loan functionality** compliant with [ERC-3156: Flash Loans](https://eips.ethereum.org/EIPS/eip-3156).

This repository contains a **Solidity port** of the original Uniswap V1 contracts written in Vyper. The original Vyper contracts are preserved in the https://github.com/Uniswap/v1-contracts or [`vyper-original/`](vyper-original/) directory for reference.
  

### Conversion Details

The conversion from Vyper to Solidity involved several key changes:

- **Safe Token Transfers**: Uses OpenZeppelin's `SafeERC20` for secure token operations
- **Error Handling**: Converted `assert` statements to Solidity's `require`

### Key Differences

| Aspect | Vyper Original | Solidity Port |
|--------|---------------|---------------|
| **Token Standard** | Custom ERC20 | OpenZeppelin ERC20 |
| **Initialization** | `setup(token_addr)` function | Constructor `constructor(address token_addr)` |
| **Token Transfers** | Direct `transfer()` calls | `safeTransfer()` and `safeTransferFrom()` |
| **Flash Loans** | Not supported | EIP-3156 compliant flash lending |

### Files

- [`src/Factory.sol`](src/Factory.sol) - Factory contract for creating exchanges
- [`src/Exchange.sol`](src/Exchange.sol) - Exchange contract for token/ETH swaps
- [`src/IFlashloanEIP3156.sol`](src/IFlashloanEIP3156.sol) - EIP-3156 flash loan interfaces
- [`vyper-original/uniswap_factory.vy`](vyper-original/uniswap_factory.vy) - Original Vyper factory
- [`vyper-original/uniswap_exchange.vy`](vyper-original/uniswap_exchange.vy) - Original Vyper exchange

---

## Flash Loans (EIP-3156)

This Solidity port adds **flash loan functionality** compliant with [ERC-3156: Flash Loans](https://eips.ethereum.org/EIPS/eip-3156). Flash loans allow borrowing the exchange's token reserves for 0.3% fee (within the same transaction) as long as the borrowed amount plus the fee is repaid before the transaction ends.

### How It Works

1. A borrower calls `flashLoan()` specifying the token amount and a callback receiver contract
2. The exchange transfers tokens to the receiver contract
3. The receiver's `onFlashLoan()` callback is executed (borrower can arbitrage, liquidate, etc.)
4. The receiver must approve the exchange to pull back `amount + fee`
5. If not repaid, the entire transaction reverts

### Fee Structure

Flash loans charge a **0.3% fee** (+ 1 wei minimum): `(amount * 3 / 1000) + 1`

| Function | Description |
|----------|-------------|
| `maxFlashLoan(token)` | Returns the maximum borrowable amount for a token |
| `flashFee(token, amount)` | Returns the fee for a given loan amount |
| `flashLoan(receiver, token, amount, data)` | Executes the flash loan |

### Example Usage

check [EIP3156](https://github.com/Jiuhong-casperlabs/flash/blob/696aca54218947eceaf5e0b01b7b46cf225a7223/EIP-3156.md?plain=1#L171-L207) for a sample flash loan receiver implementation and usage example.

---

## Security Considerations & Risks

> **⚠️ WARNING: This is an unaudited implementation. Use at your own risk.**

### Recommendations
- **Do not use in production** without a professional security audit
- Monitor for unusual flash loan activity if operating a protocol that integrates with this exchange


## Documentation

https://book.getfoundry.sh/

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```
