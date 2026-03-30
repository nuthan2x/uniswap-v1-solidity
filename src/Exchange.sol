// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {ERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Factory} from "./Factory.sol";

interface IFactory {
    function getExchange(address token_addr) external returns(address);
}

interface IExchange {
    function getEthToTokenOutputPrice(uint256 tokens_bought) external view returns (uint256);
    function ethToTokenTransferInput(uint256 min_tokens, uint256 deadline, address recipient) external returns (uint256);
    function ethToTokenTransferOutput(uint256 tokens_bought, uint256 deadline, address recipient) external payable returns (uint256);
}

/// @title Exchange contract : clone of https://github.com/Uniswap/v1-contracts/blob/master/contracts/uniswap_exchange.vy in solidity
/// @author https://x.com/nuthan2x || https://github.com/nuthan2x
/// @notice core exchange between an ERC20 and native ETH
/// @notice Use at your own risk && un-audited
contract Exchange is ERC20 {
    using SafeERC20 for IERC20;

    event TokenPurchase(address indexed buyer, uint256 eth_sold, uint256 tokens_bought);
    event EthPurchase(address indexed buyer, uint256 tokens_sold, uint256 eth_bought);
    event AddLiquidity(address indexed provider, uint256 eth_amount, uint256 token_amount);
    event RemoveLiquidity(address indexed provider, uint256 eth_amount, uint256 token_amount);


    address private token;
    Factory private factory;

    constructor(address token_addr) ERC20("Uniswap V1", "UNI-V1") {
        require(token_addr != address(0));

        token = token_addr;
        factory = Factory(msg.sender);
    }

    /// @notice Deposit ETH and Tokens (self.token) at current ratio to mint UNI tokens.
    /// @dev min_liquidity does nothing when total UNI supply is 0.
    /// @param min_liquidity Minimum number of UNI sender will mint if total UNI supply is greater than 0.
    /// @param max_tokens Maximum number of tokens deposited. Deposits max amount if total UNI supply is 0.
    /// @param deadline Time after which this transaction can no longer be executed.
    /// @return The amount of UNI minted.
    function addLiquidity(uint256 min_liquidity, uint256 max_tokens, uint256 deadline) public payable returns(uint256){
        require(deadline > block.timestamp && max_tokens > 0 && deadline > 0);
        uint256 total_liquidity = totalSupply();

        if (total_liquidity > 0) {
            require(min_liquidity > 0);
            uint256 eth_reserve = address(this).balance - msg.value;
            uint256 token_reserve = IERC20(token).balanceOf(address(this));

            uint256 token_amount = (msg.value * token_reserve / eth_reserve) + 1;
            uint256 liquidity_minted = msg.value * total_liquidity / eth_reserve;
            require(max_tokens >= token_amount && liquidity_minted >= min_liquidity);

            IERC20(token).safeTransferFrom(msg.sender, address(this), token_amount);
            _mint(msg.sender, liquidity_minted);

            emit AddLiquidity(msg.sender, msg.value, token_amount);
            return liquidity_minted;
        } else {
            require(msg.value >= 1e9); // 1 gwei mininmum
            // require(factory.getExchange(token) == address(this));
            uint256 token_amount = max_tokens;
            uint256 initial_liquidity = address(this).balance;

            IERC20(token).safeTransferFrom(msg.sender, address(this), token_amount);
            _mint(msg.sender, initial_liquidity);

            emit AddLiquidity(msg.sender, msg.value, token_amount);
            return initial_liquidity;
        }
    }

    /// @dev Burn UNI tokens to withdraw ETH and Tokens at current ratio.
    /// @param amount Amount of UNI burned.
    /// @param min_eth Minimum ETH withdrawn.
    /// @param min_tokens Minimum Tokens withdrawn.
    /// @param deadline Time after which this transaction can no longer be executed.
    /// @return The amount of ETH and Tokens withdrawn.
    function removeLiquidity(
        uint256 amount, 
        uint256 min_eth, 
        uint256 min_tokens, 
        uint256 deadline
    ) public returns(uint256, uint256) {
        require(amount > 0 && deadline > block.timestamp);
        require(min_eth >0 && min_tokens > 0);

        uint256 total_liquidity = totalSupply();
        require(total_liquidity > 0);

        uint256 token_reserve = IERC20(token).balanceOf(address(this));
        uint256 token_amount = amount * token_reserve / total_liquidity;
        uint256 eth_amount = amount *  address(this).balance / total_liquidity;
        require(token_amount >= min_tokens && eth_amount >= min_eth);

        _burn(msg.sender, amount);
        payable(msg.sender).transfer(eth_amount);
        IERC20(token).safeTransfer(msg.sender, token_amount);

        emit RemoveLiquidity(msg.sender, eth_amount, token_amount);
        return (eth_amount, token_amount);
    }


    /// @return Address of Token that is sold on this exchange.
    function tokenAddress() public view returns (address) {
        return token;
    }

    /// @return Address of factory that created this exchange.
    function factoryAddress() public view returns (address) {
        return address(factory);
    }
}