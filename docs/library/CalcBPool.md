

## Functions:
[`bdiv(uint256 a, uint256 b)`](#CalcBPool-bdiv-uint256-uint256-)
[`BPTVal(address _pool, address _pair, address _staker, address _stakeLocker)`](#CalcBPool-BPTVal-address-address-address-address-)
[`getSwapOutValue(address pool, address pair, address staker, address stakeLocker)`](#CalcBPool-getSwapOutValue-address-address-address-address-)
[`getSwapOutValueLocker(address pool, address pair, address stakeLocker)`](#CalcBPool-getSwapOutValueLocker-address-address-address-)
[`getPoolSharesRequired(address bpool, address pair, address staker, address stakeLocker, uint256 pairAmountRequired)`](#CalcBPool-getPoolSharesRequired-address-address-address-address-uint256-)


## <u>Functions</u>

### `bdiv(uint256 a, uint256 b)`
Official balancer pool bdiv() function, does synthetic float with 10^-18 precision.

### `BPTVal(address _pool, address _pair, address _staker, address _stakeLocker)`
Calculates the value of BPT in units of _liquidityAssetContract in 'wei' (decimals) for this token.

### `getSwapOutValue(address pool, address pair, address staker, address stakeLocker)`
Calculate _pair swap out value of staker BPT balance escrowed in stakeLocker.
        @param pool        Balancer pool that issues the BPTs.
        @param pair        Swap out asset (e.g. USDC) to receive when burning BPTs.
        @param staker      Address that deposited BPTs to stakeLocker.
        @param stakeLocker Escrows BPTs deposited by staker.
        @return USDC swap out value of staker BPTs.

### `getSwapOutValueLocker(address pool, address pair, address stakeLocker)`
Calculate _pair swap out value of staker BPT balance escrowed in stakeLocker.
        @param pool        Balancer pool that issues the BPTs.
        @param pair        Swap out asset (e.g. USDC) to receive when burning BPTs.
        @param stakeLocker Escrows BPTs deposited by staker.
        @return USDC swap out value of staker BPTs.

### `getPoolSharesRequired(address bpool, address pair, address staker, address stakeLocker, uint256 pairAmountRequired)`
Calculates BPTs required if burning BPTs for pair, given supplied tokenAmountOutRequired.
        @param  bpool              Balancer pool that issues the BPTs.
        @param  pair               Swap out asset (e.g. USDC) to receive when burning BPTs.
        @param  staker             Address that deposited BPTs to stakeLocker.
        @param  stakeLocker        Escrows BPTs deposited by staker.
        @param  pairAmountRequired Amount of pair tokens out required.
        @return [0] = poolAmountIn required
                [1] = poolAmountIn currently staked.

## <u>Events</u>