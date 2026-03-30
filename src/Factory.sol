// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import "./Exchange.sol";

/// @title Factory contract : clone of https://github.com/Uniswap/v1-contracts/blob/master/contracts/uniswap_factory.vy in solidity
/// @author https://x.com/nuthan2x || https://github.com/nuthan2x
/// @notice deploys a new exchange between a new token and ETH
/// @notice Use at your own risk && un-audited
contract Factory {

    event NewExchange(address indexed token, address indexed exchange);
    
    // storage
    uint256 public tokenCount;
    mapping(address token => address exchange)  token_to_exchange;
    mapping(address exchange => address token)  exchange_to_token;
    mapping(uint256 id => address token)  id_to_token;

    function createExchange(address token) public returns(address){
        require(token != address(0));
        require(token_to_exchange[token] == address(0));

        address exchange = address(new Exchange(token));
        token_to_exchange[token] = exchange;
        exchange_to_token[exchange] = token;
        uint256 token_id = ++tokenCount;
        id_to_token[token_id] = token;

        emit NewExchange(token, exchange);
        return exchange;
    }

    function getExchange(address token) public view returns (address) {
        return token_to_exchange[token];
    }

    function getToken(address exchange) public view returns (address) {
        return exchange_to_token[exchange];
    }

    function getTokenWithId(uint256 token_id) public view returns (address) {
        return id_to_token[token_id];
    }
}