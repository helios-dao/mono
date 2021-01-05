// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;
pragma experimental ABIEncoderV2;

import "./TestUtil.sol";

import "../mocks/value.sol";
import "../mocks/token.sol";

import "../AmortizationRepaymentCalculator.sol";
import "../BulletRepaymentCalculator.sol";
import "../LateFeeNullCalculator.sol";
import "../PremiumFlatCalculator.sol";

import "../MapleToken.sol";
import "../MapleGlobals.sol";
import "../FundingLockerFactory.sol";
import "../CollateralLockerFactory.sol";
import "../LoanVaultFactory.sol";

contract Borrower {
    function try_drawdown(address loanVault, uint256 amt) external returns (bool ok) {
        string memory sig = "drawdown(uint256)";
        (ok,) = address(loanVault).call(abi.encodeWithSignature(sig, amt));
    }

    function try_makePayment(address loanVault) external returns (bool ok) {
        string memory sig = "makePayment()";
        (ok,) = address(loanVault).call(abi.encodeWithSignature(sig));
    }

    function approve(address token, address who, uint256 amt) external {
        IERC20(token).approve(who, amt);
    }

    function createLoanVault(
        LoanVaultFactory loanVaultFactory,
        address requestedAsset, 
        address collateralAsset, 
        uint256[6] memory specs_vault,
        address[3] memory calcs_vault
    ) 
        external returns (LoanVault loanVault) 
    {
        loanVault = LoanVault(
            loanVaultFactory.createLoanVault(requestedAsset, collateralAsset, specs_vault, calcs_vault)
        );
    }
}

contract Lender {
    function fundLoan(LoanVault loanVault, uint256 amt, address who) external {
        loanVault.fundLoan(amt, who);
    }

    function approve(address token, address who, uint256 amt) external {
        IERC20(token).approve(who, amt);
    }

    // To assert failures
    function try_drawdown(address loanVault, uint256 amt) external returns (bool ok) {
        string memory sig = "drawdown(uint256)";
        (ok,) = address(loanVault).call(abi.encodeWithSignature(sig, amt));
    }
}

contract Treasury { }

contract LoanVaultTest is TestUtil {

    ERC20                           fundsToken;
    MapleToken                      mapleToken;
    MapleGlobals                    globals;
    FundingLockerFactory            fundingLockerFactory;
    CollateralLockerFactory         collateralLockerFactory;
    DSValue                         ethOracle;
    DSValue                         daiOracle;
    AmortizationRepaymentCalculator amortiCalc;
    BulletRepaymentCalculator       bulletCalc;
    LateFeeNullCalculator           lateFeeCalc;
    PremiumFlatCalculator           premiumCalc;
    LoanVaultFactory                loanVaultFactory;
    Borrower                        ali;
    Lender                          bob;
    Treasury                        trs;

    function setUp() public {

        fundsToken              = new ERC20("FundsToken", "FT");
        mapleToken              = new MapleToken("MapleToken", "MAPL", IERC20(fundsToken));
        globals                 = new MapleGlobals(address(this), address(mapleToken));
        fundingLockerFactory    = new FundingLockerFactory();
        collateralLockerFactory = new CollateralLockerFactory();
        ethOracle               = new DSValue();
        daiOracle               = new DSValue();
        bulletCalc              = new BulletRepaymentCalculator();
        amortiCalc              = new AmortizationRepaymentCalculator();
        lateFeeCalc             = new LateFeeNullCalculator();
        premiumCalc             = new PremiumFlatCalculator(500); // Flat 5% premium
        loanVaultFactory        = new LoanVaultFactory(
            address(globals), 
            address(fundingLockerFactory), 
            address(collateralLockerFactory)
        );

        ethOracle.poke(500 ether);  // Set ETH price to $600
        daiOracle.poke(1 ether);    // Set DAI price to $1

        globals.setCalculator(address(amortiCalc),  true);
        globals.setCalculator(address(bulletCalc),  true);
        globals.setCalculator(address(lateFeeCalc), true);
        globals.setCalculator(address(premiumCalc), true);
        globals.setCollateralToken(WETH, true);
        globals.setBorrowToken(DAI, true);
        globals.assignPriceFeed(WETH, address(ethOracle));
        globals.assignPriceFeed(DAI, address(daiOracle));

        ali = new Borrower();
        bob = new Lender();
        trs = new Treasury();
        globals.setMapleTreasury(address(trs));

        mint("WETH", address(ali), 10 ether);
        mint("DAI",  address(bob), 5000 ether);
        mint("DAI",  address(ali), 500 ether);
    }

    function test_createLoanVault() public {
        uint256[6] memory specs_vault = [500, 180, 30, uint256(1000 ether), 2000, 7];
        address[3] memory calcs_vault = [address(bulletCalc), address(lateFeeCalc), address(premiumCalc)];

        LoanVault loanVault = ali.createLoanVault(loanVaultFactory, DAI, WETH, specs_vault, calcs_vault);
    
        assertEq(loanVault.assetRequested(),               DAI);
        assertEq(loanVault.assetCollateral(),              WETH);
        assertEq(loanVault.fundingLockerFactory(),         address(fundingLockerFactory));
        assertEq(loanVault.collateralLockerFactory(),      address(collateralLockerFactory));
        assertEq(loanVault.borrower(),                     address(ali));
        assertEq(loanVault.loanCreatedTimestamp(),         block.timestamp);
        assertEq(loanVault.aprBips(),                      specs_vault[0]);
        assertEq(loanVault.termDays(),                     specs_vault[1]);
        assertEq(loanVault.numberOfPayments(),             specs_vault[1] / specs_vault[2]);
        assertEq(loanVault.paymentIntervalSeconds(),       specs_vault[2] * 1 days);
        assertEq(loanVault.minRaise(),                     specs_vault[3]);
        assertEq(loanVault.collateralBipsRatio(),          specs_vault[4]);
        assertEq(loanVault.fundingPeriodSeconds(),         specs_vault[5] * 1 days);
        assertEq(address(loanVault.repaymentCalculator()), address(bulletCalc));
        assertEq(address(loanVault.lateFeeCalculator()),   address(lateFeeCalc));
        assertEq(address(loanVault.premiumCalculator()),   address(premiumCalc));
        assertEq(loanVault.nextPaymentDue(),               block.timestamp + loanVault.paymentIntervalSeconds());
    }

    function test_fundLoan() public {
        uint256[6] memory specs_vault = [500, 90, 30, uint256(1000 ether), 2000, 7];
        address[3] memory calcs_vault = [address(bulletCalc), address(lateFeeCalc), address(premiumCalc)];

        LoanVault loanVault = ali.createLoanVault(loanVaultFactory, DAI, WETH, specs_vault, calcs_vault);
        address fundingLocker = loanVault.fundingLocker();

        bob.approve(DAI, address(loanVault), 5000 ether);
    
        assertEq(IERC20(loanVault).balanceOf(address(ali)),              0);
        assertEq(IERC20(DAI).balanceOf(address(fundingLocker)),          0);
        assertEq(IERC20(DAI).balanceOf(address(bob)),           5000 ether);

        bob.fundLoan(loanVault, 5000 ether, address(ali));

        assertEq(IERC20(loanVault).balanceOf(address(ali)),     5000 ether);
        assertEq(IERC20(DAI).balanceOf(address(fundingLocker)), 5000 ether);
        assertEq(IERC20(DAI).balanceOf(address(bob)),                    0);
    }

    function createAndFundLoan(address _interestStructure) internal returns (LoanVault loanVault) {
        uint256[6] memory specs_vault = [500, 90, 30, uint256(1000 ether), 2000, 7];
        address[3] memory calcs_vault = [_interestStructure, address(lateFeeCalc), address(premiumCalc)];

        loanVault = ali.createLoanVault(loanVaultFactory, DAI, WETH, specs_vault, calcs_vault);

        bob.approve(DAI, address(loanVault), 5000 ether);
    
        bob.fundLoan(loanVault, 5000 ether, address(ali));
    }

    function test_collateralRequiredForDrawdown() public {
        LoanVault loanVault = createAndFundLoan(address(bulletCalc));

        uint256 reqCollateral = loanVault.collateralRequiredForDrawdown(1000 ether);
        assertEq(reqCollateral, 0.4 ether);
    }

    function test_drawdown() public {
        LoanVault loanVault = createAndFundLoan(address(bulletCalc));

        assertTrue(!bob.try_drawdown(address(loanVault), 1000 ether));  // Non-borrower can't drawdown
        assertTrue(!ali.try_drawdown(address(loanVault), 1000 ether));  // Can't drawdown without approving collateral

        ali.approve(WETH, address(loanVault), 0.4 ether);

        assertTrue(!ali.try_drawdown(address(loanVault), 1000 ether - 1));  // Can't drawdown less than minRaise
        assertTrue(!ali.try_drawdown(address(loanVault), 5000 ether + 1));  // Can't drawdown more than fundingLocker balance

        address fundingLocker = loanVault.fundingLocker();
        uint pre = IERC20(DAI).balanceOf(address(ali));

        assertEq(IERC20(WETH).balanceOf(address(ali)),        10 ether);  // Borrower collateral balance
        assertEq(IERC20(loanVault).balanceOf(address(ali)), 5000 ether);  // Borrower loanVault token balance
        assertEq(IERC20(DAI).balanceOf(fundingLocker),      5000 ether);  // Funding locker reqAssset balance
        assertEq(IERC20(DAI).balanceOf(address(loanVault)),          0);  // Loan vault reqAsset balance
        assertEq(loanVault.drawdownAmount(),                         0);  // Drawdown amount
        assertEq(loanVault.principalOwed(),                          0);  // Principal owed
        assertEq(uint256(loanVault.loanState()),                     0);  // Loan state: Live

        // Fee related variables pre-check.
        assertEq(loanVault.feePaid(),                 0);  // feePaid amount
        assertEq(loanVault.excessReturned(),          0);  // excessReturned amount
        assertEq(IERC20(DAI).balanceOf(address(trs)), 0);  // Treasury reqAsset balance

        assertTrue(ali.try_drawdown(address(loanVault), 1000 ether));     // Borrow draws down 1000 DAI

        address collateralLocker = loanVault.collateralLocker();

        assertEq(IERC20(WETH).balanceOf(address(ali)),            9.6 ether);  // Borrower collateral balance
        assertEq(IERC20(WETH).balanceOf(collateralLocker),        0.4 ether);  // Collateral locker collateral balance
        assertEq(IERC20(loanVault).balanceOf(address(ali)),      5000 ether);  // Borrower loanVault token balance
        assertEq(IERC20(DAI).balanceOf(fundingLocker),                    0);  // Funding locker reqAssset balance
        assertEq(IERC20(DAI).balanceOf(address(loanVault)),      4005 ether);  // Loan vault reqAsset balance
        assertEq(IERC20(DAI).balanceOf(address(ali)),       990 ether + pre);  // Lender reqAsset balance
        assertEq(loanVault.drawdownAmount(),                     1000 ether);  // Drawdown amount
        assertEq(loanVault.principalOwed(),                      1000 ether);  // Principal owed
        assertEq(uint256(loanVault.loanState()),                          1);  // Loan state: Active

        
        // Fee related variables post-check.
        assertEq(loanVault.feePaid(),                    5 ether);  // Drawdown amount
        assertEq(loanVault.excessReturned(),          4000 ether);  // Principal owed
        assertEq(IERC20(DAI).balanceOf(address(trs)),    5 ether);  // Treasury reqAsset balance

    }

    function test_makePaymentBullet() public {

        LoanVault loanVault = createAndFundLoan(address(bulletCalc));

        assertEq(uint256(loanVault.loanState()), 0);  // Loan state: Live

        assertTrue(!ali.try_makePayment(address(loanVault)));  // Can't makePayment when State != Active

        // Approve collatearl and drawdown loan.
        ali.approve(WETH, address(loanVault), 0.4 ether);
        assertTrue(ali.try_drawdown(address(loanVault), 1000 ether));  // Borrow draws down 1000 DAI

        address collateralLocker = loanVault.collateralLocker();
        address fundingLocker    = loanVault.fundingLocker();

        // Warp to *300 seconds* before next payment is due
        assertEq(loanVault.nextPaymentDue(), block.timestamp + loanVault.paymentIntervalSeconds());
        hevm.warp(loanVault.nextPaymentDue() - 300);
        assertEq(block.timestamp, loanVault.nextPaymentDue() - 300);

        assertTrue(!ali.try_makePayment(address(loanVault)));  // Can't makePayment with lack of approval

        // Approve 1st of 3 payments.
        (uint _amt, uint _pri, uint _int, uint _due) = loanVault.getNextPayment();
        ali.approve(DAI, address(loanVault), _amt);

        // Before state
        assertEq(uint256(loanVault.loanState()),          1);  // Loan state is Active, accepting payments
        assertEq(loanVault.principalOwed(),      1000 ether);  // Initial drawdown amount.
        assertEq(loanVault.principalPaid(),               0);
        assertEq(loanVault.interestPaid(),                0);
        assertEq(loanVault.numberOfPayments(),            3);
        assertEq(loanVault.nextPaymentDue(),           _due);

        // Make payment.
        assertTrue(ali.try_makePayment(address(loanVault)));

        uint _nextPaymentDue = _due + loanVault.paymentIntervalSeconds();

        // After state
        assertEq(uint256(loanVault.loanState()),               1);  // Loan state is Active (unless final payment, then 2)
        assertEq(loanVault.principalOwed(),           1000 ether);  // Initial drawdown amount.
        assertEq(loanVault.principalPaid(),                 _pri);
        assertEq(loanVault.interestPaid(),                  _int);
        assertEq(loanVault.numberOfPayments(),                 2);
        assertEq(loanVault.nextPaymentDue(),     _nextPaymentDue);

        // Approve 2nd of 3 payments.
        (_amt, _pri, _int, _due) = loanVault.getNextPayment();
        ali.approve(DAI, address(loanVault), _amt);
        
        // Make payment.
        assertTrue(ali.try_makePayment(address(loanVault)));

        _nextPaymentDue = _due + loanVault.paymentIntervalSeconds();
        
        // After state
        assertEq(uint256(loanVault.loanState()),               1);  // Loan state is Active (unless final payment, then 2)
        assertEq(loanVault.principalOwed(),           1000 ether);  // Initial drawdown amount.
        assertEq(loanVault.principalPaid(),                 _pri);
        assertEq(loanVault.interestPaid(),              _int * 2);
        assertEq(loanVault.numberOfPayments(),                 1);
        assertEq(loanVault.nextPaymentDue(),     _nextPaymentDue);

        // Approve 3nd of 3 payments.
        (_amt, _pri, _int, _due) = loanVault.getNextPayment();
        ali.approve(DAI, address(loanVault), _amt);
        
        // Check collateral locker balance.
        uint256 reqCollateral = loanVault.collateralRequiredForDrawdown(1000 ether);
        address collateralAsset = loanVault.assetCollateral();
        uint _delta = IERC20(collateralAsset).balanceOf(address(ali));
        assertEq(IERC20(collateralAsset).balanceOf(collateralLocker), reqCollateral);
        
        // Make payment.
        assertTrue(ali.try_makePayment(address(loanVault)));

        _nextPaymentDue = _due + loanVault.paymentIntervalSeconds();
        
        // After state, state variables.
        assertEq(uint256(loanVault.loanState()),               2);  // Loan state is Matured (final payment)
        assertEq(loanVault.principalOwed(),                    0);  // Final payment, all principal paid for Bullet
        assertEq(loanVault.principalPaid(),                 _pri);
        assertEq(loanVault.interestPaid(),              _int * 3);
        assertEq(loanVault.numberOfPayments(),                 0);
        assertEq(loanVault.nextPaymentDue(),     _nextPaymentDue);

        // Collateral locker after state.
        assertEq(IERC20(collateralAsset).balanceOf(collateralLocker),                      0);
        assertEq(IERC20(collateralAsset).balanceOf(address(ali)),     _delta + reqCollateral);

    }

    function test_makePaymentAmortization() public {
        LoanVault loanVault = createAndFundLoan(address(amortiCalc));

        assertEq(uint256(loanVault.loanState()), 0);  // Loan state: Live

        assertTrue(!ali.try_makePayment(address(loanVault)));  // Can't makePayment when State != Active

        // Approve collatearl and drawdown loan.
        ali.approve(WETH, address(loanVault), 0.4 ether);
        assertTrue(ali.try_drawdown(address(loanVault), 1000 ether));     // Borrow draws down 1000 DAI

        address collateralLocker = loanVault.collateralLocker();
        address fundingLocker    = loanVault.fundingLocker();

        // Warp to *300 seconds* before next payment is due
        assertEq(loanVault.nextPaymentDue(), block.timestamp + loanVault.paymentIntervalSeconds());
        hevm.warp(loanVault.nextPaymentDue() - 300);
        assertEq(block.timestamp, loanVault.nextPaymentDue() - 300);

        assertTrue(!ali.try_makePayment(address(loanVault)));  // Can't makePayment with lack of approval

        // Approve 1st of 3 payments.
        (uint _amt, uint _pri, uint _int, uint _due) = loanVault.getNextPayment();
        ali.approve(DAI, address(loanVault), _amt);

        // Before state
        assertEq(uint256(loanVault.loanState()),             1);    // Loan state is Active, accepting payments
        assertEq(loanVault.principalOwed(),         1000 ether);    // Initial drawdown amount.
        assertEq(loanVault.principalPaid(),                  0);
        assertEq(loanVault.interestPaid(),                   0);
        assertEq(loanVault.numberOfPayments(),               3);
        assertEq(loanVault.nextPaymentDue(),              _due);

        // Make payment.
        assertTrue(ali.try_makePayment(address(loanVault)));

        uint _nextPaymentDue = _due + loanVault.paymentIntervalSeconds();

        // After state
        assertEq(uint256(loanVault.loanState()),                  1);    // Loan state is Active (unless final payment, then 2)
        assertEq(loanVault.principalOwed(),       1000 ether - _pri);    
        assertEq(loanVault.principalPaid(),                    _pri);
        assertEq(loanVault.interestPaid(),                     _int);
        assertEq(loanVault.numberOfPayments(),                    2);
        assertEq(loanVault.nextPaymentDue(),        _nextPaymentDue);

        // Approve 2nd of 3 payments.
        uint _intTwo;
        (_amt, _pri, _intTwo, _due) = loanVault.getNextPayment();
        ali.approve(DAI, address(loanVault), _amt);
        
        // Make payment.
        assertTrue(ali.try_makePayment(address(loanVault)));

        _nextPaymentDue = _due + loanVault.paymentIntervalSeconds();
        
        // After state
        assertEq(uint256(loanVault.loanState()),                        1);    // Loan state is Active (unless final payment, then 2)
        assertEq(loanVault.principalOwed(),         1000 ether - _pri * 2);    // Initial drawdown amount.
        assertEq(loanVault.principalPaid(),         1000 ether - _pri - 1);
        assertEq(loanVault.interestPaid(),                 _int + _intTwo);
        assertEq(loanVault.numberOfPayments(),                          1);
        assertEq(loanVault.nextPaymentDue(),              _nextPaymentDue);

        // Approve 3nd of 3 payments.
        uint _intThree;
        (_amt, _pri, _intThree, _due) = loanVault.getNextPayment();
        ali.approve(DAI, address(loanVault), _amt);
        
        // Check collateral locker balance.
        uint256 reqCollateral = loanVault.collateralRequiredForDrawdown(1000 ether);
        address collateralAsset = loanVault.assetCollateral();
        uint _delta = IERC20(collateralAsset).balanceOf(address(ali));
        assertEq(IERC20(collateralAsset).balanceOf(collateralLocker), reqCollateral);
        
        // Make payment.
        assertTrue(ali.try_makePayment(address(loanVault)));

        _nextPaymentDue = _due + loanVault.paymentIntervalSeconds();
        
        // After state, state variables.
        assertEq(uint256(loanVault.loanState()),                          2);  // Loan state is Matured (final payment)
        assertEq(loanVault.principalOwed(),                               0);  // Final payment, all principal paid for Bullet
        assertEq(loanVault.principalPaid(),                      1000 ether);
        assertEq(loanVault.interestPaid(),       _int + _intTwo + _intThree);
        assertEq(loanVault.numberOfPayments(),                            0);
        assertEq(loanVault.nextPaymentDue(),                _nextPaymentDue);

        // Collateral locker after state.
        assertEq(IERC20(collateralAsset).balanceOf(collateralLocker),                       0);
        assertEq(IERC20(collateralAsset).balanceOf(address(ali)),      _delta + reqCollateral);
    }

    function test_makePaymentLateAmortization() public {
        LoanVault loanVault = createAndFundLoan(address(amortiCalc));

        assertEq(uint256(loanVault.loanState()), 0);  // Loan state: Live

        assertTrue(!ali.try_makePayment(address(loanVault)));  // Can't makePayment when State != Active

        // Approve collatearl and drawdown loan.
        ali.approve(WETH, address(loanVault), 0.4 ether);
        assertTrue(ali.try_drawdown(address(loanVault), 1000 ether));  // Borrow draws down 1000 DAI

        address collateralLocker = loanVault.collateralLocker();
        address fundingLocker    = loanVault.fundingLocker();

        // Warp to end of grace period.
        assertEq(loanVault.nextPaymentDue(), block.timestamp + loanVault.paymentIntervalSeconds());
        hevm.warp(loanVault.nextPaymentDue() + globals.gracePeriod());
        assertEq(block.timestamp, loanVault.nextPaymentDue() + globals.gracePeriod());

        assertTrue(!ali.try_makePayment(address(loanVault)));  // Can't makePayment with lack of approval

        // Approve 1st of 3 payments.
        (uint _amt, uint _pri, uint _int, uint _due) = loanVault.getNextPayment();
        ali.approve(DAI, address(loanVault), _amt);

        // Before state
        assertEq(uint256(loanVault.loanState()),          1);  // Loan state is Active, accepting payments
        assertEq(loanVault.principalOwed(),      1000 ether);  // Initial drawdown amount.
        assertEq(loanVault.principalPaid(),               0);
        assertEq(loanVault.interestPaid(),                0);
        assertEq(loanVault.numberOfPayments(),            3);
        assertEq(loanVault.nextPaymentDue(),           _due);

        // Warp to *300 seconds* after next payment is due
        hevm.warp(loanVault.nextPaymentDue() + globals.gracePeriod());
        assertEq(block.timestamp, loanVault.nextPaymentDue() + globals.gracePeriod());

        // Make payment.
        assertTrue(ali.try_makePayment(address(loanVault)));

        uint _nextPaymentDue = _due + loanVault.paymentIntervalSeconds();

        // After state
        assertEq(uint256(loanVault.loanState()),                 1);  // Loan state is Active (unless final payment, then 2)
        assertEq(loanVault.principalOwed(),      1000 ether - _pri);    
        assertEq(loanVault.principalPaid(),                   _pri);
        assertEq(loanVault.interestPaid(),                    _int);
        assertEq(loanVault.numberOfPayments(),                   2);
        assertEq(loanVault.nextPaymentDue(),       _nextPaymentDue);

        // Approve 2nd of 3 payments.
        uint _intTwo;
        (_amt, _pri, _intTwo, _due) = loanVault.getNextPayment();
        ali.approve(DAI, address(loanVault), _amt);

        // Warp to *300 seconds* after next payment is due
        hevm.warp(loanVault.nextPaymentDue() + globals.gracePeriod());
        assertEq(block.timestamp, loanVault.nextPaymentDue() + globals.gracePeriod());
        
        // Make payment.
        assertTrue(ali.try_makePayment(address(loanVault)));

        _nextPaymentDue = _due + loanVault.paymentIntervalSeconds();
        
        // After state
        assertEq(uint256(loanVault.loanState()),                     1);  // Loan state is Active (unless final payment, then 2)
        assertEq(loanVault.principalOwed(),      1000 ether - _pri * 2);  // Initial drawdown amount.
        assertEq(loanVault.principalPaid(),      1000 ether - _pri - 1);
        assertEq(loanVault.interestPaid(),              _int + _intTwo);
        assertEq(loanVault.numberOfPayments(),                       1);
        assertEq(loanVault.nextPaymentDue(),           _nextPaymentDue);

        // Approve 3nd of 3 payments.
        uint _intThree;
        (_amt, _pri, _intThree, _due) = loanVault.getNextPayment();
        ali.approve(DAI, address(loanVault), _amt);
        
        // Check collateral locker balance.
        uint256 reqCollateral = loanVault.collateralRequiredForDrawdown(1000 ether);
        address collateralAsset = loanVault.assetCollateral();
        uint _delta = IERC20(collateralAsset).balanceOf(address(ali));
        assertEq(IERC20(collateralAsset).balanceOf(collateralLocker), reqCollateral);

        // Warp to *300 seconds* after next payment is due
        hevm.warp(loanVault.nextPaymentDue() + 300);
        assertEq(block.timestamp, loanVault.nextPaymentDue() + 300);
        
        // Make payment.
        assertTrue(ali.try_makePayment(address(loanVault)));

        _nextPaymentDue = _due + loanVault.paymentIntervalSeconds();
        
        // After state, state variables.
        assertEq(uint256(loanVault.loanState()),                          2);  // Loan state is Matured (final payment)
        assertEq(loanVault.principalOwed(),                               0);  // Final payment, all principal paid for Bullet
        assertEq(loanVault.principalPaid(),                      1000 ether);
        assertEq(loanVault.interestPaid(),       _int + _intTwo + _intThree);
        assertEq(loanVault.numberOfPayments(),                            0);
        assertEq(loanVault.nextPaymentDue(),                _nextPaymentDue);

        // Collateral locker after state.
        assertEq(IERC20(collateralAsset).balanceOf(collateralLocker),                      0);
        assertEq(IERC20(collateralAsset).balanceOf(address(ali)),     _delta + reqCollateral);
    }

    function test_makePaymentLateBullet() public {
        LoanVault loanVault = createAndFundLoan(address(bulletCalc));

        assertEq(uint256(loanVault.loanState()), 0);  // Loan state: Live

        assertTrue(!ali.try_makePayment(address(loanVault)));  // Can't makePayment when State != Active

        // Approve collatearl and drawdown loan.
        ali.approve(WETH, address(loanVault), 0.4 ether);
        assertTrue(ali.try_drawdown(address(loanVault), 1000 ether));  // Borrow draws down 1000 DAI

        address collateralLocker = loanVault.collateralLocker();
        address fundingLocker    = loanVault.fundingLocker();

        // Warp to *300 seconds* before next payment is due
        assertEq(loanVault.nextPaymentDue(), block.timestamp + loanVault.paymentIntervalSeconds());
        hevm.warp(loanVault.nextPaymentDue() - 300);
        assertEq(block.timestamp, loanVault.nextPaymentDue() - 300);

        assertTrue(!ali.try_makePayment(address(loanVault)));  // Can't makePayment with lack of approval

        // Approve 1st of 3 payments.
        (uint _amt, uint _pri, uint _int, uint _due) = loanVault.getNextPayment();
        ali.approve(DAI, address(loanVault), _amt);

        // Before state
        assertEq(uint256(loanVault.loanState()),          1);  // Loan state is Active, accepting payments
        assertEq(loanVault.principalOwed(),      1000 ether);  // Initial drawdown amount.
        assertEq(loanVault.principalPaid(),               0);
        assertEq(loanVault.interestPaid(),                0);
        assertEq(loanVault.numberOfPayments(),            3);
        assertEq(loanVault.nextPaymentDue(),           _due);

        // Warp to *300 seconds* after next payment is due
        hevm.warp(loanVault.nextPaymentDue() + globals.gracePeriod());
        assertEq(block.timestamp, loanVault.nextPaymentDue() + globals.gracePeriod());

        // Make payment.
        assertTrue(ali.try_makePayment(address(loanVault)));

        uint _nextPaymentDue = _due + loanVault.paymentIntervalSeconds();

        // After state
        assertEq(uint256(loanVault.loanState()),               1);  // Loan state is Active (unless final payment, then 2)
        assertEq(loanVault.principalOwed(),           1000 ether);  // Initial drawdown amount.
        assertEq(loanVault.principalPaid(),                 _pri);
        assertEq(loanVault.interestPaid(),                  _int);
        assertEq(loanVault.numberOfPayments(),                 2);
        assertEq(loanVault.nextPaymentDue(),     _nextPaymentDue);

        // Approve 2nd of 3 payments.
        (_amt, _pri, _int, _due) = loanVault.getNextPayment();
        ali.approve(DAI, address(loanVault), _amt);

        // Warp to *300 seconds* after next payment is due
        hevm.warp(loanVault.nextPaymentDue() + globals.gracePeriod());
        assertEq(block.timestamp, loanVault.nextPaymentDue() + globals.gracePeriod());
        
        // Make payment.
        assertTrue(ali.try_makePayment(address(loanVault)));

        _nextPaymentDue = _due + loanVault.paymentIntervalSeconds();
        
        // After state
        assertEq(uint256(loanVault.loanState()),               1);  // Loan state is Active (unless final payment, then 2)
        assertEq(loanVault.principalOwed(),           1000 ether);  // Initial drawdown amount.
        assertEq(loanVault.principalPaid(),                 _pri);
        assertEq(loanVault.interestPaid(),              _int * 2);
        assertEq(loanVault.numberOfPayments(),                 1);
        assertEq(loanVault.nextPaymentDue(),     _nextPaymentDue);

        // Approve 3nd of 3 payments.
        (_amt, _pri, _int, _due) = loanVault.getNextPayment();
        ali.approve(DAI, address(loanVault), _amt);
        
        // Check collateral locker balance.
        uint256 reqCollateral = loanVault.collateralRequiredForDrawdown(1000 ether);
        address collateralAsset = loanVault.assetCollateral();
        uint _delta = IERC20(collateralAsset).balanceOf(address(ali));
        assertEq(IERC20(collateralAsset).balanceOf(collateralLocker), reqCollateral);

        // Warp to *300 seconds* after next payment is due
        hevm.warp(loanVault.nextPaymentDue() + globals.gracePeriod());
        assertEq(block.timestamp, loanVault.nextPaymentDue() + globals.gracePeriod());
        
        // Make payment.
        assertTrue(ali.try_makePayment(address(loanVault)));

        _nextPaymentDue = _due + loanVault.paymentIntervalSeconds();
        
        // After state, state variables.
        assertEq(uint256(loanVault.loanState()),               2);  // Loan state is Matured (final payment)
        assertEq(loanVault.principalOwed(),                    0);  // Final payment, all principal paid for Bullet
        assertEq(loanVault.principalPaid(),                 _pri);
        assertEq(loanVault.interestPaid(),              _int * 3);
        assertEq(loanVault.numberOfPayments(),                 0);
        assertEq(loanVault.nextPaymentDue(),     _nextPaymentDue);

        // Collateral locker after state.
        assertEq(IERC20(collateralAsset).balanceOf(collateralLocker),                      0);
        assertEq(IERC20(collateralAsset).balanceOf(address(ali)),     _delta + reqCollateral);
    }

}