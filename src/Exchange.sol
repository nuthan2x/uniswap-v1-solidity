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
        require(deadline > block.timestamp && max_tokens > 0 && msg.value > 0);
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

    /// @dev Pricing function for converting between ETH and Tokens.
    /// @param input_amount Amount of ETH or Tokens being sold.
    /// @param input_reserve Amount of ETH or Tokens (input type) in exchange reserves.
    /// @param output_reserve Amount of ETH or Tokens (output type) in exchange reserves.
    /// @return Amount of ETH or Tokens bought.
    function getInputPrice(
        uint256 input_amount, 
        uint256 input_reserve, 
        uint256 output_reserve
    ) private pure returns(uint256) {
        require(input_reserve > 0 && output_reserve > 0);

        uint256 input_amount_with_fee = input_amount * 997;
        uint256 numerator = input_amount_with_fee * output_reserve;
        uint256 denominator = (input_reserve * 1000) + input_amount_with_fee;

        return numerator / denominator;
    }

    /// @dev Pricing function for converting between ETH and Tokens.
    /// @param output_amount Amount of ETH or Tokens being bought.
    /// @param input_reserve Amount of ETH or Tokens (input type) in exchange reserves.
    /// @param output_reserve Amount of ETH or Tokens (output type) in exchange reserves.
    /// @return Amount of ETH or Tokens sold.
    function getOutputPrice(
        uint256 output_amount, 
        uint256 input_reserve, 
        uint256 output_reserve
    ) private pure returns(uint256) {
        require(input_reserve > 0 && output_reserve > 0);

        uint256 numerator = output_amount * input_reserve * 1000;
        uint256 denominator = (output_reserve - output_amount) * 997;

        return (numerator / denominator) + 1;
    }

    /// @notice Convert ETH to Tokens.
    /// @dev User specifies exact input (msg.value).
    /// @dev User cannot specify minimum output or deadline.
    receive() external payable {
        ethToTokenInput(msg.value, 1, block.timestamp, msg.sender, msg.sender);
    }

    /// @notice Convert ETH to Tokens.
    /// @dev User specifies exact input (msg.value) and minimum output.
    /// @param min_tokens Minimum Tokens bought.
    /// @param deadline Time after which this transaction can no longer be executed.
    /// @return Amount of Tokens bought.
    function ethToTokenSwapInput(uint256 min_tokens, uint256 deadline) public payable returns(uint256) {
        return ethToTokenInput(msg.value, min_tokens, deadline, msg.sender, msg.sender);
    }

    /// @notice Convert ETH to Tokens and transfers Tokens to recipient.
    /// @dev User specifies exact input (msg.value) and minimum output
    /// @param min_tokens Minimum Tokens bought.
    /// @param deadline Time after which this transaction can no longer be executed.
    /// @param recipient The address that receives output Tokens.
    /// @return Amount of Tokens bought.
    function ethToTokenTransferInput(
        uint256 min_tokens, uint256 deadline, address recipient
    ) public payable returns(uint256) {
        require(recipient != address(this) && recipient != address(0));
        return ethToTokenInput(msg.value, min_tokens, deadline, msg.sender, recipient);
    }

    /// @notice Convert ETH to Tokens and transfers Tokens to recipient.
    /// @dev User specifies exact input (msg.value) and minimum output
    /// @param min_tokens Minimum Tokens bought.
    /// @param deadline Time after which this transaction can no longer be executed.
    /// @param recipient The address that receives output Tokens.
    /// @return Amount of Tokens bought.
    function ethToTokenInput(
        uint256 eth_sold, 
        uint256 min_tokens, 
        uint256 deadline, 
        address buyer, 
        address recipient
    ) private returns(uint256) {
        require(deadline >= block.timestamp && (eth_sold > 0 && min_tokens > 0));
        
        uint256 token_reserve = IERC20(token).balanceOf(address(this));
        uint256 eth_reserve = address(this).balance - eth_sold;
        uint256 tokens_bought = getInputPrice(eth_sold, eth_reserve, token_reserve);
        require(tokens_bought >= min_tokens);

        IERC20(token).safeTransfer(recipient, tokens_bought);

        emit TokenPurchase(buyer, eth_sold, tokens_bought);
        return tokens_bought;
    }

    /// @notice Convert ETH to Tokens.
    /// @dev User specifies maximum input (msg.value) and exact output.
    /// @param tokens_bought Amount of tokens bought.
    /// @param deadline Time after which this transaction can no longer be executed.
    /// @return Amount of ETH sold.
    function ethToTokenSwapOutput(uint256 tokens_bought, uint256 deadline) public payable returns(uint256) {
        return ethToTokenOutput(tokens_bought, msg.value, deadline, msg.sender, msg.sender);
    }

    /// @notice Convert ETH to Tokens and transfers Tokens to recipient.
    /// @dev User specifies maximum input (msg.value) and exact output.
    /// @param tokens_bought Amount of tokens bought.
    /// @param deadline Time after which this transaction can no longer be executed.
    /// @param recipient The address that receives output Tokens.
    /// @return Amount of ETH sold.
    function ethToTokenTransferOutput(
        uint256 tokens_bought, uint256 deadline, address recipient
    ) public payable returns(uint256) {
        require(recipient != address(this) && recipient != address(0));
        return ethToTokenOutput(tokens_bought, msg.value, deadline, msg.sender, recipient);
    }

    function ethToTokenOutput(
        uint256 tokens_bought, 
        uint256 max_eth, 
        uint256 deadline, 
        address buyer, 
        address recipient
    ) private returns(uint256) {
        require(deadline >= block.timestamp && (tokens_bought > 0 && max_eth > 0));
        
        uint256 token_reserve = IERC20(token).balanceOf(address(this));
        uint256 eth_reserve = address(this).balance;
        uint256 eth_sold = getOutputPrice(tokens_bought, eth_reserve, token_reserve);
        
        uint256 eth_refund = max_eth - eth_sold;
        if (eth_refund > 0) payable(buyer).transfer(eth_refund);
        
        IERC20(token).safeTransfer(recipient, tokens_bought);

        emit TokenPurchase(buyer, eth_sold, tokens_bought);
        return eth_sold;
    }

    /// @notice Convert Tokens to ETH.
    /// @dev User specifies exact input and minimum output.
    /// @param tokens_sold Amount of Tokens sold.
    /// @param min_eth Minimum ETH purchased.
    /// @param deadline Time after which this transaction can no longer be executed.
    /// @return Amount of ETH bought.
    function tokenToEthSwapInput(
        uint256 tokens_sold, uint256 min_eth, uint256 deadline
    ) public returns (uint256) {
        return tokenToEthInput(tokens_sold, min_eth, deadline, msg.sender, msg.sender);
    }

    /// @notice Convert Tokens to ETH and transfers ETH to recipient.
    /// @dev User specifies exact input and minimum output.
    /// @param tokens_sold Amount of Tokens sold.
    /// @param min_eth Minimum ETH purchased.
    /// @param deadline Time after which this transaction can no longer be executed.
    /// @param recipient The address that receives output ETH.
    /// @return Amount of ETH bought.
    function tokenToEthTransferInput(
        uint256 tokens_sold, uint256 min_eth, uint256 deadline, address recipient
    ) public returns (uint256) {
        require(recipient != address(this) && recipient != address(0));
        return tokenToEthInput(tokens_sold, min_eth, deadline, msg.sender, recipient);
    }

    function tokenToEthInput(
        uint256 tokens_sold, 
        uint256 min_eth, 
        uint256 deadline, 
        address buyer, 
        address recipient
    ) private returns(uint256) {
        require(deadline >= block.timestamp && (tokens_sold > 0 && min_eth > 0));
        
        uint256 token_reserve = IERC20(token).balanceOf(address(this));
        uint256 eth_reserve = address(this).balance;
        uint256 eth_bought = getInputPrice(tokens_sold, token_reserve, eth_reserve);
        require(eth_bought >= min_eth);

        IERC20(token).safeTransferFrom(buyer, address(this), tokens_sold);
        payable(recipient).transfer(eth_bought);

        emit EthPurchase(buyer, tokens_sold, eth_bought);
        return eth_bought;
    }

    /// @notice Convert Tokens to ETH.
    /// @dev User specifies maximum input and exact output.
    /// @param eth_bought Amount of ETH purchased.
    /// @param max_tokens Maximum Tokens sold.
    /// @param deadline Time after which this transaction can no longer be executed.
    /// @return Amount of Tokens sold.
    function tokenToEthSwapOutput(
        uint256 eth_bought, uint256 max_tokens, uint256 deadline
    ) public returns (uint256) {
        return tokenToEthOutput(eth_bought, max_tokens, deadline, msg.sender, msg.sender);
    }

    /// @notice Convert Tokens to ETH and transfers ETH to recipient.
    /// @dev User specifies maximum input and exact output.
    /// @param eth_bought Amount of ETH purchased.
    /// @param max_tokens Maximum Tokens sold.
    /// @param deadline Time after which this transaction can no longer be executed.
    /// @param recipient The address that receives output ETH.
    /// @return Amount of Tokens sold.
    function tokenToEthTransferOutput(
        uint256 eth_bought, uint256 max_tokens, uint256 deadline, address recipient
    ) public returns (uint256) {
        require(recipient != address(this) && recipient != address(0));
        return tokenToEthOutput(eth_bought, max_tokens, deadline, msg.sender, recipient);
    }

    function tokenToEthOutput(
        uint256 eth_bought, 
        uint256 max_tokens, 
        uint256 deadline, 
        address buyer, 
        address recipient
    ) private returns(uint256) {
        require(deadline >= block.timestamp && (eth_bought > 0 && max_tokens > 0));
        
        uint256 token_reserve = IERC20(token).balanceOf(address(this));
        uint256 eth_reserve = address(this).balance;
        uint256 tokens_sold = getOutputPrice(eth_bought, token_reserve, eth_reserve);
        require(tokens_sold <= max_tokens);
        
        IERC20(token).safeTransferFrom(buyer, address(this), tokens_sold);
        payable(recipient).transfer(eth_bought);

        emit EthPurchase(buyer, tokens_sold, eth_bought);
        return tokens_sold;
    }

    /// @notice Convert Tokens (self.token) to Tokens (token_addr).
    /// @dev User specifies exact input and minimum output.
    /// @param tokens_sold Amount of Tokens sold.
    /// @param min_tokens_bought Minimum Tokens (token_addr) purchased.
    /// @param min_eth_bought Minimum ETH purchased as intermediary.
    /// @param deadline Time after which this transaction can no longer be executed.
    /// @param token_addr The address of the token being purchased.
    /// @return Amount of Tokens (token_addr) bought.
    function tokenToTokenSwapInput(
        uint256 tokens_sold, 
        uint256 min_tokens_bought, 
        uint256 min_eth_bought, 
        uint256 deadline, 
        address token_addr
    ) public returns (uint256) {
        address exchange_addr = factory.getExchange(token_addr);
        return tokenToTokenInput(tokens_sold, min_tokens_bought, min_eth_bought, deadline, msg.sender, msg.sender, exchange_addr);
    }

    /// @notice Convert Tokens (self.token) to Tokens (token_addr) and transfers
    ///         Tokens (token_addr) to recipient.
    /// @dev User specifies exact input and minimum output.
    /// @param tokens_sold Amount of Tokens sold.
    /// @param min_tokens_bought Minimum Tokens (token_addr) purchased.
    /// @param min_eth_bought Minimum ETH purchased as intermediary.
    /// @param deadline Time after which this transaction can no longer be executed.
    /// @param recipient The address that receives output ETH.
    /// @param token_addr The address of the token being purchased.
    /// @return Amount of Tokens (token_addr) bought.
    function tokenToTokenTransferInput(
        uint256 tokens_sold, 
        uint256 min_tokens_bought, 
        uint256 min_eth_bought, 
        uint256 deadline, 
        address recipient, 
        address token_addr
    ) public returns (uint256) {
        address exchange_addr = factory.getExchange(token_addr);
        return tokenToTokenInput(tokens_sold, min_tokens_bought, min_eth_bought, deadline, msg.sender, recipient, exchange_addr);
    }

    function tokenToTokenInput(
        uint256 tokens_sold, 
        uint256 min_tokens_bought, 
        uint256 min_eth_bought, 
        uint256 deadline, 
        address buyer, 
        address recipient,
        address exchange_addr
    ) private returns(uint256) {
        require(deadline >= block.timestamp && tokens_sold > 0);
        require(min_tokens_bought > 0 && min_eth_bought > 0);
        require(exchange_addr != address(this) && exchange_addr != address(0));

        uint256 token_reserve = IERC20(token).balanceOf(address(this));
        uint256 eth_reserve = address(this).balance;
        uint256 eth_bought = getInputPrice(tokens_sold, token_reserve, eth_reserve);
        require(eth_bought >= min_eth_bought);

        IERC20(token).safeTransferFrom(buyer, address(this), tokens_sold);
        uint256 tokens_bought = Exchange(payable(exchange_addr)).ethToTokenTransferInput{value : eth_bought}(
            min_tokens_bought, deadline, recipient
        );

        emit EthPurchase(buyer, tokens_sold, eth_bought);
        return tokens_bought;
    }

    /// @notice Convert Tokens (self.token) to Tokens (token_addr).
    /// @dev User specifies maximum input and exact output.
    /// @param tokens_bought Amount of Tokens (token_addr) bought.
    /// @param max_tokens_sold Maximum Tokens (self.token) sold.
    /// @param max_eth_sold Maximum ETH purchased as intermediary.
    /// @param deadline Time after which this transaction can no longer be executed.
    /// @param token_addr The address of the token being purchased.
    /// @return Amount of Tokens (self.token) sold.
    function tokenToTokenSwapOutput(uint256 tokens_bought, uint256 max_tokens_sold, uint256 max_eth_sold, uint256 deadline, address token_addr) public returns (uint256) {
        address exchange_addr = factory.getExchange(token_addr);
        return tokenToTokenOutput(tokens_bought, max_tokens_sold, max_eth_sold, deadline, msg.sender, msg.sender, exchange_addr);
    }

    /// @notice Convert Tokens (self.token) to Tokens (token_addr) and transfers
    ///         Tokens (token_addr) to recipient.
    /// @dev User specifies maximum input and exact output.
    /// @param tokens_bought Amount of Tokens (token_addr) bought.
    /// @param max_tokens_sold Maximum Tokens (self.token) sold.
    /// @param max_eth_sold Maximum ETH purchased as intermediary.
    /// @param deadline Time after which this transaction can no longer be executed.
    /// @param recipient The address that receives output ETH.
    /// @param token_addr The address of the token being purchased.
    /// @return Amount of Tokens (self.token) sold.
    function tokenToTokenTransferOutput(uint256 tokens_bought, uint256 max_tokens_sold, uint256 max_eth_sold, uint256 deadline, address recipient, address token_addr) public returns (uint256) {
        address exchange_addr = factory.getExchange(token_addr);
        return tokenToTokenOutput(tokens_bought, max_tokens_sold, max_eth_sold, deadline, msg.sender, recipient, exchange_addr);
    }

    function tokenToTokenOutput(
        uint256 tokens_bought, 
        uint256 max_tokens_sold, 
        uint256 max_eth_sold, 
        uint256 deadline, 
        address buyer, 
        address recipient,
        address exchange_addr
    ) private returns(uint256) {
        require(deadline >= block.timestamp && tokens_bought > 0);
        require(max_tokens_sold > 0 && max_eth_sold > 0);
        require(exchange_addr != address(this) && exchange_addr != address(0));

        uint256 eth_toSell = Exchange(payable(exchange_addr)).getEthToTokenOutputPrice(tokens_bought);

        uint256 token_reserve = IERC20(token).balanceOf(address(this));
        uint256 eth_reserve = address(this).balance;
        uint256 tokens_sold = getOutputPrice(eth_toSell, token_reserve, eth_reserve);

        require(tokens_sold <= max_tokens_sold && eth_toSell <= max_eth_sold);

        IERC20(token).safeTransferFrom(buyer, address(this), tokens_sold);
        Exchange(payable(exchange_addr)).ethToTokenTransferOutput{value : eth_toSell}(
            tokens_bought, deadline, recipient
        );

        emit EthPurchase(buyer, tokens_sold, eth_toSell);
        return tokens_sold;
    }


    /// @notice Public price function for ETH to Token trades with an exact input.
    /// @param eth_sold Amount of ETH sold.
    /// @return Amount of Tokens that can be bought with input ETH.
    function getEthToTokenInputPrice(uint256 eth_sold) public view returns (uint256) {
        require(eth_sold > 0);
        uint256 token_reserve = IERC20(token).balanceOf(address(this));
        return getInputPrice(eth_sold, address(this).balance, token_reserve);
    }

    /// @notice Public price function for ETH to Token trades with an exact output.
    /// @param tokens_bought Amount of Tokens bought.
    /// @return Amount of ETH needed to buy output Tokens.
    function getEthToTokenOutputPrice(uint256 tokens_bought) public view returns (uint256) {
        require(tokens_bought > 0);
        uint256 token_reserve = IERC20(token).balanceOf(address(this));
        return getOutputPrice(tokens_bought, address(this).balance, token_reserve);
    }

    /// @notice Public price function for Token to ETH trades with an exact input.
    /// @param tokens_sold Amount of Tokens sold.
    /// @return Amount of ETH that can be bought with input Tokens.
    function getTokenToEthInputPrice(uint256 tokens_sold) public view returns (uint256) {
        require(tokens_sold > 0);
        uint256 token_reserve = IERC20(token).balanceOf(address(this));
        return getInputPrice(tokens_sold, token_reserve, address(this).balance);
    }

    /// @notice Public price function for Token to ETH trades with an exact output.
    /// @param eth_bought Amount of output ETH.
    /// @return Amount of Tokens needed to buy output ETH.
    function getTokenToEthOutputPrice(uint256 eth_bought) public view returns (uint256) {
        require(eth_bought > 0);
        uint256 token_reserve = IERC20(token).balanceOf(address(this));
        return getOutputPrice(eth_bought, token_reserve, address(this).balance);
    }

    /// @notice Convert Tokens (self.token) to Tokens (exchange_addr.token).
    /// @dev Allows trades through contracts that were not deployed from the same factory.
    /// @dev User specifies exact input and minimum output.
    /// @param tokens_sold Amount of Tokens sold.
    /// @param min_tokens_bought Minimum Tokens (token_addr) purchased.
    /// @param min_eth_bought Minimum ETH purchased as intermediary.
    /// @param deadline Time after which this transaction can no longer be executed.
    /// @param exchange_addr The address of the exchange for the token being purchased.
    /// @return Amount of Tokens (exchange_addr.token) bought.
    function tokenToExchangeSwapInput(uint256 tokens_sold, uint256 min_tokens_bought, uint256 min_eth_bought, uint256 deadline, address exchange_addr) public returns (uint256) {
        return tokenToTokenInput(tokens_sold, min_tokens_bought, min_eth_bought, deadline, msg.sender, msg.sender, exchange_addr);
    }

    /// @notice Convert Tokens (self.token) to Tokens (exchange_addr.token) and transfers
    ///         Tokens (exchange_addr.token) to recipient.
    /// @dev Allows trades through contracts that were not deployed from the same factory.
    /// @dev User specifies exact input and minimum output.
    /// @param tokens_sold Amount of Tokens sold.
    /// @param min_tokens_bought Minimum Tokens (token_addr) purchased.
    /// @param min_eth_bought Minimum ETH purchased as intermediary.
    /// @param deadline Time after which this transaction can no longer be executed.
    /// @param recipient The address that receives output ETH.
    /// @param exchange_addr The address of the exchange for the token being purchased.
    /// @return Amount of Tokens (exchange_addr.token) bought.
    function tokenToExchangeTransferInput(uint256 tokens_sold, uint256 min_tokens_bought, uint256 min_eth_bought, uint256 deadline, address recipient, address exchange_addr) public returns (uint256) {
        require(recipient != address(this));
        return tokenToTokenInput(tokens_sold, min_tokens_bought, min_eth_bought, deadline, msg.sender, recipient, exchange_addr);
    }

    /// @notice Convert Tokens (self.token) to Tokens (exchange_addr.token).
    /// @dev Allows trades through contracts that were not deployed from the same factory.
    /// @dev User specifies maximum input and exact output.
    /// @param tokens_bought Amount of Tokens (token_addr) bought.
    /// @param max_tokens_sold Maximum Tokens (self.token) sold.
    /// @param max_eth_sold Maximum ETH purchased as intermediary.
    /// @param deadline Time after which this transaction can no longer be executed.
    /// @param exchange_addr The address of the exchange for the token being purchased.
    /// @return Amount of Tokens (self.token) sold.
    function tokenToExchangeSwapOutput(uint256 tokens_bought, uint256 max_tokens_sold, uint256 max_eth_sold, uint256 deadline, address exchange_addr) public returns (uint256) {
        return tokenToTokenOutput(tokens_bought, max_tokens_sold, max_eth_sold, deadline, msg.sender, msg.sender, exchange_addr);
    }

    /// @notice Convert Tokens (self.token) to Tokens (exchange_addr.token) and transfers
    ///         Tokens (exchange_addr.token) to recipient.
    /// @dev Allows trades through contracts that were not deployed from the same factory.
    /// @dev User specifies maximum input and exact output.
    /// @param tokens_bought Amount of Tokens (token_addr) bought.
    /// @param max_tokens_sold Maximum Tokens (self.token) sold.
    /// @param max_eth_sold Maximum ETH purchased as intermediary.
    /// @param deadline Time after which this transaction can no longer be executed.
    /// @param recipient The address that receives output ETH.
    /// @param exchange_addr The address of the exchange for the token being purchased.
    /// @return Amount of Tokens (self.token) sold.
    function tokenToExchangeTransferOutput(uint256 tokens_bought, uint256 max_tokens_sold, uint256 max_eth_sold, uint256 deadline, address recipient, address exchange_addr) public returns (uint256) {
        require(recipient != address(this));
        return tokenToTokenOutput(tokens_bought, max_tokens_sold, max_eth_sold, deadline, msg.sender, recipient, exchange_addr);
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