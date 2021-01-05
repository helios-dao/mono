// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;
pragma experimental ABIEncoderV2;

import "./TestUtil.sol";

import "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import "../MapleToken.sol";
import "../MapleGlobals.sol";

contract MapleGlobalsTest is TestUtil {

    ERC20        fundsToken;
    MapleToken   mapleToken;
    MapleGlobals globals;

    function setUp() public {
        fundsToken = new ERC20("FundsToken", "FT");
        mapleToken = new MapleToken("MapleToken", "MAPL", IERC20(fundsToken));
        globals    = new MapleGlobals(address(this), address(mapleToken));
    }

    function test_setters() public {
        assertEq(globals.investorFee(), 50);
        globals.setInvestorFee(45);
        assertEq(globals.investorFee(), 45);

        assertEq(globals.treasuryFee(), 50);
        globals.setTreasuryFee(30);
        assertEq(globals.treasuryFee(), 30);

        assertEq(globals.gracePeriod(), 5 days);
        globals.setGracePeriod(1 days);
        assertEq(globals.gracePeriod(), 1 days);

        assertEq(globals.stakeAmountRequired(), 100000000);
        globals.setStakeRequired(35000);
        assertEq(globals.stakeAmountRequired(), 35000);

        assertEq(globals.unstakeDelay(), 90 days);
        globals.setUnstakeDelay(30 days);
        assertEq(globals.unstakeDelay(), 30 days);

        assertEq(globals.governor(), address(this));
        globals.setGovernor(address(this));
        assertEq(globals.governor(), address(this));
    }

    function test_add_tokens() public {
        string[]  memory validBorrowTokenSymbols;
        address[] memory validBorrowTokenAddresses;
        string[]  memory validCollateralTokenSymbols;
        address[] memory validCollateralTokenAddresses;
        (
            validBorrowTokenSymbols,
            validBorrowTokenAddresses,
            validCollateralTokenSymbols,
            validCollateralTokenAddresses
        ) = globals.getValidTokens();

        assertEq(validBorrowTokenSymbols.length,       0);
        assertEq(validBorrowTokenAddresses.length,     0);
        assertEq(validCollateralTokenSymbols.length,   0);
        assertEq(validCollateralTokenAddresses.length, 0);

        globals.setCollateralToken(WETH, true);
        (
            validBorrowTokenSymbols,
            validBorrowTokenAddresses,
            validCollateralTokenSymbols,
            validCollateralTokenAddresses
        ) = globals.getValidTokens();

        assertEq(validBorrowTokenSymbols.length,            0);
        assertEq(validBorrowTokenAddresses.length,          0);
        assertEq(validCollateralTokenSymbols.length,        1);
        assertEq(validCollateralTokenAddresses.length,      1);
        assertEq(validCollateralTokenSymbols[0],       "WETH");
        assertEq(validCollateralTokenAddresses[0],      WETH);

        globals.setBorrowToken(DAI, true);
        (
            validBorrowTokenSymbols,
            validBorrowTokenAddresses,
            validCollateralTokenSymbols,
            validCollateralTokenAddresses
        ) = globals.getValidTokens();

        assertEq(validBorrowTokenSymbols.length,           1);
        assertEq(validBorrowTokenAddresses.length,         1);
        assertEq(validCollateralTokenSymbols.length,       1);
        assertEq(validCollateralTokenAddresses.length,     1);
        assertEq(validBorrowTokenSymbols[0],           "DAI");
        assertEq(validBorrowTokenAddresses[0],          DAI);
    }
}