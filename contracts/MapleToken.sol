// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;

import "./token/IFundsDistributionToken.sol";
import "./token/FundsDistributionToken.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract MapleToken is IFundsDistributionToken, FundsDistributionToken {

	using SafeMathInt    for int256;
	using SignedSafeMath for int256;

	IERC20  public fundsToken;  // Token in which the funds can be sent to the FundsDistributionToken
	uint256 public fundsTokenBalance;  // Balance of fundsToken that the FundsDistributionToken currently holds

	modifier onlyFundsToken () {
		require(msg.sender == address(fundsToken), "FDT_ERC20Extension.onlyFundsToken: UNAUTHORIZED_SENDER");
		_;
	}

	constructor (
		string memory name, 
		string memory symbol,
		IERC20 _fundsToken
	)  
		FundsDistributionToken(name, symbol)
		public 
	{
		require(address(_fundsToken) != address(0), "FDT_ERC20Extension: INVALID_FUNDS_TOKEN_ADDRESS");
        _mint(msg.sender, 10000000 * (10 ** uint256(decimals())));
		fundsToken = _fundsToken;
	}

	/**
	 * @notice Withdraws all available funds for a token holder
	 */
	function withdrawFunds() external override {
		uint256 withdrawableFunds = _prepareWithdraw();
		
		require(fundsToken.transfer(msg.sender, withdrawableFunds), "FDT_ERC20Extension.withdrawFunds: TRANSFER_FAILED");

		_updateFundsTokenBalance();
	}

	/**
	 * @dev Updates the current funds token balance 
	 * and returns the difference of new and previous funds token balances
	 * @return A int256 representing the difference of the new and previous funds token balance
	 */
	function _updateFundsTokenBalance() internal returns (int256) {
		uint256 prevFundsTokenBalance = fundsTokenBalance;
		
		fundsTokenBalance = fundsToken.balanceOf(address(this));

		return int256(fundsTokenBalance).sub(int256(prevFundsTokenBalance));
	}

	/**
	 * @notice Register a payment of funds in tokens. May be called directly after a deposit is made.
	 * @dev Calls _updateFundsTokenBalance(), whereby the contract computes the delta of the previous and the new 
	 * funds token balance and increments the total received funds (cumulative) by delta by calling _registerFunds()
	 */
	function updateFundsReceived() external {
		int256 newFunds = _updateFundsTokenBalance();

		if (newFunds > 0) {
			_distributeFunds(newFunds.toUint256Safe());
		}
	}
}
