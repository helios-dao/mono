// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;

import "./library/Util.sol";
import "./interfaces/IGlobals.sol";
import "./interfaces/IMapleToken.sol";
import "./interfaces/IERC20Details.sol";
import "./interfaces/IUniswapRouter.sol";

import "lib/openzeppelin-contracts/contracts/math/SafeMath.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract MapleTreasury {

	using SafeMath for uint256;

    address public mpl;     // MapleToken.sol contract.
    address public fundsToken;     // _fundsToken value in the MapleToken.sol contract.
    address public uniswapRouter;  // Official UniswapV2 router contract.
    address public globals;   // MapleGlobals.sol contract.

    /**
        @dev Instantiates the MapleTreasury contract.
        @param  _mpl is the MapleToken contract.
        @param  _fundsToken is the fundsToken of MapleToken contract.
        @param  _uniswapRouter is the official UniswapV2 router contract.
        @param  _globals is the MapleGlobals.sol contract.
    */
    constructor(
        address _mpl, 
        address _fundsToken, 
        address _uniswapRouter,
        address _globals
    ) public {
        mpl           = _mpl;
        fundsToken    = _fundsToken;
        uniswapRouter = _uniswapRouter;
        globals       = _globals;
    }

    /**
        @dev Fired when an ERC-20 asset is converted to fundsToken and transferred to mpl.
        @param _asset     The asset that is converted.
        @param _by        The msg.sender calling the conversion function.
        @param _amountIn  The amount of _asset converted to fundsToken.
        @param _amountOut The amount of fundsToken received for _asset conversion.
    */
    event ERC20Conversion(
        address _asset,
        address _by,
        uint256 _amountIn,
        uint256 _amountOut
    );

    /**
        @dev Fired when ETH is converted to fundsToken and transferred to mpl.
        @param _by        The msg.sender calling the conversion function.
        @param _amountIn  The amount of ETH converted to fundsToken.
        @param _amountOut The amount of fundsToken received for ETH conversion.
    */
    event ETHConversion(
        address _by,
        uint256 _amountIn,
        uint256 _amountOut
    );

    /**
        @dev Fired when fundsToken is passed through to mpl.
        @param _by        The msg.sender calling the passThrough function.
        @param _amount    The amount of fundsToken passed through.
    */
    event PassThrough(
        address _by,
        uint256 _amount
    );

    /**
        @dev Fired when fundsToken is modified for this contract.
        @param _by            The msg.sender calling the passThrough function.
        @param _newFundsToken The new fundsToken to convert to.
    */
    // TODO: Consider why this would be changed? Seems this would lead to critical erros.
    event FundsTokenModified(
        address _by,
        address _newFundsToken
    );

    modifier isGovernor() {
        require(msg.sender == IGlobals(globals).governor(), "MapleTreasury:MSG_SENDER_NOT_GOVERNOR");
        _;
    }
  
    fallback () external payable { }
    receive  () external payable { }

    /**
        @dev Adjust the token to convert assets to (and then send to MapleToken).
        @param _newFundsToken The new FundsToken with respect to MapleToken ERC-2222.
    */
    // TODO: Consider why this would be changed? Seems this would lead to critical erros.
    function setFundsToken(address _newFundsToken) isGovernor public {
        fundsToken = _newFundsToken;
    }

    /**
        @dev Update the maple globals contract
        @param  newGlobals Address of new maple globals contract
    */
    function setGlobals(address newGlobals) external isGovernor {
        globals = newGlobals;
    }

    /**
        @dev Passes through the current fundsToken to MapleToken.
    */
    function passThroughFundsToken() isGovernor public {
        IERC20 _fundsToken = IERC20(fundsToken);
        uint256 passThroughAmount = _fundsToken.balanceOf(address(this));
        require(_fundsToken.transfer(mpl, passThroughAmount), "MapleTreasury:FUNDS_RECEIVE_TRANSFER");
        IMapleToken(mpl).updateFundsReceived();
        emit PassThrough(msg.sender, passThroughAmount);
    }

    /**
        @dev Convert an ERC-20 asset through Uniswap via bilateral transaction (two asset path).
        @param asset The ERC-20 asset to convert.
    */
    function convertERC20(address asset) isGovernor public {
        require(asset != fundsToken, "MapleTreasury:ASSET_EQUALS_FUNDS_TOKEN");
        
        IGlobals _globals = IGlobals(globals);

        uint assetBalance = IERC20(asset).balanceOf(address(this));
        uint minAmount    = Util.calcMinAmount(_globals, asset, fundsToken, assetBalance);

        IERC20(asset).approve(uniswapRouter, assetBalance);
        
        // Generate path.
        address[] storage path;
        path.push(asset);
        address uniswapAssetForPath = _globals.defaultUniswapPath(asset, fundsToken);
        if (uniswapAssetForPath != asset) { path.push(uniswapAssetForPath); }
        path.push(asset);

        uint[] memory returnAmounts = IUniswapRouter(uniswapRouter).swapExactTokensForTokens(
            assetBalance,
            minAmount.sub(minAmount.mul(_globals.maxSwapSlippage()).div(10000)),
            path,
            mpl, // Transfer tokens to MPL (MapleToken contract)
            block.timestamp + 3600 // 1 hour padding. Unix timestamp after which the transaction will revert.
        );

        IMapleToken(mpl).updateFundsReceived();

        emit ERC20Conversion(
            asset,
            msg.sender,
            returnAmounts[0],
            returnAmounts[path.length - 1]
        );
    }

    /**
    TODO: Do we still need this?
    */

    /**
        @dev Convert ETH through Uniswap via bilateral transaction (two asset path).
        @param _amountOut The amount out expected.
        @param _amountIn  The amount in to convert.
    */
    function convertETH(uint256 _amountOut, uint256 _amountIn) isGovernor public {
        address[] memory path = new address[](2);
        path[0] = IUniswapRouter(uniswapRouter).WETH();
        path[1] = fundsToken;

        uint256[] memory returnAmounts = IUniswapRouter(uniswapRouter).swapETHForExactTokens{value: _amountIn}(
            _amountOut,
            path,
            mpl,
            block.timestamp + 1
        );

        IMapleToken(mpl).updateFundsReceived();
        
        emit ETHConversion(
            msg.sender,
            returnAmounts[0],
            returnAmounts[1]
        );
    }

}
