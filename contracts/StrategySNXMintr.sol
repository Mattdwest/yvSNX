// SPDX-License-Identifier: MIT

pragma experimental ABIEncoderV2;
pragma solidity 0.6.12;

import "@openzeppelinV3/contracts/token/ERC20/IERC20.sol";
import "@openzeppelinV3/contracts/math/SafeMath.sol";
import "@openzeppelinV3/contracts/math/Math.sol";
import "@openzeppelinV3/contracts/utils/Address.sol";
import "@openzeppelinV3/contracts/token/ERC20/SafeERC20.sol";
import {BaseStrategy, StrategyParams} from "@yearnvaults/contracts/BaseStrategy.sol";

import "../../interfaces/uniswap/Uni.sol";

import "../../interfaces/synthetix/IFees.sol";
import "../../interfaces/synthetix/IMintr.sol";

// below are the interfaces unique to the strategy - depositing on curve and staking for returns
//import "../../interfaces/curve/ICurve.sol";
//import "../../interfaces/curve/VoterProxy.sol";


contract StrategySNXMintrBtc is BaseStrategy {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    address public snx;
    address public mintr;
    address public fees;
    address public exchanger;
    address public unirouter;
    address public susd;
    address public sbtc;
    address public ibtc;
    address public mkr;
    address public weth;
    //address public susdCrv;
    //address public susdCrvPool;
    string public constant override name = "StrategySNXMintrBtc";

    // synthetix uses text string converted to hex for their token exchange router
    // 64 units long, each letter paired to two. So standard 4 letter is 64-(4*2) == 56 zeroes
    // aka 8 numbers times e56
    // notably for many pairs this means the first two letters are the only that change, eg iBTC/sBTC. Note capitalization matters.
    uint256 public constant sbtcHex = 73425443e56
    uint256 public constant ibtcHex = 69425443e56

    constructor(
        address _vault,
        address _snx,
        address _mintr,
        address _fees,
        address _exchanger,
        address _susd,
        address _sbtc,
        address _ibtc,
        address _mkr,
        address _weth
    ) public BaseStrategy(_vault) {
        snx = _snx;
        mintr = _mintr;
        fees = _fees;
        exchanger = _exchanger;
        susd = _susd;
        sbtc = _sbtc;
        ibtc = _ibtc;
        mkr = _mkr;
        weth = _weth;

        // for staking snx and generating susd
        IERC20(snx).safeApprove(mintr, uint256(-1));
        //for burning susd
        IERC20(susd).safeApprove(mintr, uint256(-1));
        //todo: verify this. I'm not sure if it's through the snx token but it kinda seems so.
        IERC20(susd).safeApprove(snx, uint256(-1));
        IERC20(sbtc).safeApprove(snx, uint256(-1));
        IERC20(ibtc).safeApprove(snx, uint256(-1));
        //todo: verify. for staking ibtc in the rewards contract
        IERC20(ibtc).safeApprove(mintr, uint256(-1));

    }

    function protectedTokens() internal override view returns (address[] memory) {
        address[] memory protected = new address[](3);
        // snx (aka want) is already protected by default
        protected[0] = susd;
        protected[1] = sbtc;
        protected[2] = ibtc;
        return protected;
    }

    // returns sum of snx. sUSD is a debt, and the value of sBTC+iBTC should be constant.
    // by counting the sUSD / other derivatives as well we would be overcounting the value of the strategy.
    function estimatedTotalAssets() public override view returns (uint256) {
        return balanceOfWant();
    }

    function prepareReturn(uint256 _debtOutstanding) internal override returns (uint256 _profit, uint256 _loss, uint256 _debtPayment) {
       // We might need to return want to the vault
        if (_debtOutstanding > 0) {
           uint256 _amountFreed = liquidatePosition(_debtOutstanding);
           _debtPayment = Math.min(_amountFreed, _debtOutstanding);
        }

        uint256 balanceOfWantBefore = balanceOfWant();

        // Final profit is want generated in the swap if ethProfit > 0
        _profit = balanceOfWant().sub(balanceOfWantBefore);
    }

    function adjustPosition(uint256 _debtOutstanding) internal override {
       //emergency exit is dealt with in prepareReturn
        if (emergencyExit) {
          return;
       }

       // Invest the rest of the want
       uint256 _wantAvailable = balanceOfWant().sub(_debtOutstanding);
        if (_wantAvailable > 0) {
            uint256 _availableFunds = IERC20(dai).balanceOf(address(this));
            ICurve(threePool).add_liquidity([_availableFunds,0,0], 0);
            Vault(y3Pool).depositAll();
        }
    }

    // withdraws everything that is currently in the strategy, regardless of values.
    function exitPosition(uint256 _debtOutstanding)
        internal
        override
        returns (
          uint256 _profit,
          uint256 _loss,
          uint256 _debtPayment
        )
        {
        //uint256 y3PoolBalance = IERC20(y3Pool).balanceOf(address(this));
        Vault(y3Pool).withdrawAll();
        uint256 threePoolBalance = IERC20(crv3).balanceOf(address(this));
        ICurve(threePool).remove_liquidity_one_coin(threePoolBalance, 0, 0);
        }

    //this math only deals with want, which is dai.
    // todo: this
    function liquidatePosition(uint256 _amountNeeded) internal override returns (uint256 _amountFreed) {
        if (balanceOfWant() < _amountNeeded) {
            // We need to sell stakes to get back more want
            _withdrawSome(_amountNeeded.sub(balanceOfWant()));
        }

        // Since we might free more than needed, let's send back the min
        _amountFreed = Math.min(balanceOfWant(), _amountNeeded);
    }


    // withdraw some snx from the vaults
    // todo: this
    function _withdrawSome(uint256 _amount) internal returns (uint256) {
        uint256 _free = transferableSynthetix(address(this));
        uint256 _susdBalance = IERC20(susd).balanceOf(address(this));
        uint256 _susdValue = synthValue(_susdBalance);



        uint256 _3PoolAmount = (_amount).mul(1e18).div(ICurve(crv3).get_virtual_price());
        uint256 y3PoolAmount = (_3PoolAmount).mul(1e18).div(Vault(y3Pool).getPricePerFullShare());
        Vault(y3Pool).withdraw(y3PoolAmount);
        uint256 threePoolBalance = IERC20(crv3).balanceOf(address(this));
        ICurve(threePool).remove_liquidity_one_coin(threePoolBalance, 0, 0);
    }


    // since this is a debt-based strategy that is not tokenized, this will need to be an exitPosition and transfer.
    function prepareMigration(address _newStrategy) internal override {
        uint256 _balance = balanceOfWant();
        exitPosition(_balance);
        want.transfer(_newStrategy, balanceOfWant());
    }

    //todo: this.  Will need a tending function for this strat.
    //function tend();

    // returns value of total snx reserved by mintr
    function balanceOfStake() internal view returns (uint256) {
        uint256 _balance = balanceOfWant();
        uint256 _free = transferableSynthetix(address(this));
        uint256 _stake = _balance.sub(_free);
        return _stake;
    }

    // returns balance of snx - unstaked and staked.
    function balanceOfWant() public view returns (uint256) {
        return IERC20(want).balanceOf(address(this));
    }

    function synthValue(uint256 _amount) returns (uint256) {

        address[] memory path = new address[](4);
        path[0] = address(susd);
        path[1] = address(mkr);
        path[2] = address(weth);
        path[3] = address(want);
        uint256[] memory amounts = Uni(unirouter).getAmountsOut(_amount, path);

        return amounts[amounts.length - 1];

}

}

