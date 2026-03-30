### Disclaimer

**Use at your own risk.** This is an unaudited implementation for educational and testing purposes only. Do not use in production without thorough security review.## Uniswap V1: Vyper to Solidity Port

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

### Files

- [`src/Factory.sol`](src/Factory.sol) - Factory contract for creating exchanges
- [`src/Exchange.sol`](src/Exchange.sol) - Exchange contract for token/ETH swaps
- [`vyper-original/uniswap_factory.vy`](vyper-original/uniswap_factory.vy) - Original Vyper factory
- [`vyper-original/uniswap_exchange.vy`](vyper-original/uniswap_exchange.vy) - Original Vyper exchange



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

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy

```shell
$ forge script script/Counter.s.sol:CounterScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```
