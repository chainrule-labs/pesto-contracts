// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import { DebtServiceHarness } from "test/harness/DebtServiceHarness.t.sol";
import { DAI, USDC, AAVE_ORACLE, AAVE_POOL, WITHDRAW_BUFFER } from "test/common/Constants.t.sol";
import { IPool } from "src/interfaces/aave/IPool.sol";
import { IAaveOracle } from "src/interfaces/aave/IAaveOracle.sol";
import { IERC20 } from "src/interfaces/token/IERC20.sol";

import "forge-std/console.sol";

contract DebtUtils {
    function _getDAmt(
        uint256 _cPrice,
        uint256 _dPrice,
        uint256 _C_DEC_CONVERSION,
        uint256 _D_DEC_CONVERSION,
        uint256 _cAmt,
        uint256 _ltv
    ) internal pure returns (uint256) {
        return (_cAmt * _cPrice * uint256(_C_DEC_CONVERSION) * _ltv) / (100 * _dPrice * uint256(_D_DEC_CONVERSION));
    }

    function _getATokenBalance(address _debtService, address _cToken) internal view returns (uint256) {
        address aToken = IPool(AAVE_POOL).getReserveData(_cToken).aTokenAddress;
        return IERC20(aToken).balanceOf(_debtService);
    }

    function _getVariableDebtTokenBalance(address _debtService, address _dToken) internal view returns (uint256) {
        address vDToken = IPool(AAVE_POOL).getReserveData(_dToken).variableDebtTokenAddress;
        return IERC20(vDToken).balanceOf(_debtService);
    }

    /// @dev returns a list of 4 debt services; one for each supported dToken.
    //  Psuedocode example: [c=USDC, d=DAI], [c=USDC, d=WBTC], [c=USDC, d=WETH], and [c=DAI, d=USDC]
    function _getFilteredDebtServicesByDToken(DebtServiceHarness[] memory _debtServices)
        internal
        view
        returns (DebtServiceHarness[4] memory)
    {
        DebtServiceHarness[4] memory filteredDebtServices;

        // filter list for debt services, so each debt token can be tested
        uint256 insertIndex = 0;
        for (uint256 i; i < _debtServices.length; i++) {
            bool colUSDC = _debtServices[i].C_TOKEN() == USDC;
            bool colDAIdebtUSDC = _debtServices[i].C_TOKEN() == DAI && _debtServices[i].D_TOKEN() == USDC;
            if (colUSDC || colDAIdebtUSDC) {
                filteredDebtServices[insertIndex] = _debtServices[i];
                insertIndex++;
            }
        }
        return filteredDebtServices;
    }

    /// @dev returns a list of 4 debt services; one for each supported cToken.
    //  Psuedocode example: [c=USDC, d=DAI], [c=DAI, d=USDC], [c=WBTC, d=USDC], and [c=WETH, d=USDC]
    function _getFilteredDebtServicesByCToken(DebtServiceHarness[] memory _debtServices)
        internal
        view
        returns (DebtServiceHarness[4] memory)
    {
        DebtServiceHarness[4] memory filteredDebtServices;

        // filter list for debt services, so each debt token can be tested
        uint256 insertIndex = 0;
        for (uint256 i; i < _debtServices.length; i++) {
            bool debtUSDC = _debtServices[i].D_TOKEN() == USDC;
            bool debtDAIColUSDC = _debtServices[i].D_TOKEN() == DAI && _debtServices[i].C_TOKEN() == USDC;
            if (debtUSDC || debtDAIColUSDC) {
                filteredDebtServices[insertIndex] = _debtServices[i];
                insertIndex++;
            }
        }
        return filteredDebtServices;
    }

    /**
     * @notice Calculates the maximum amount of collateral that can be withdrawn now.
     * uint256 cNeededUSD = (dTotalUSD * 1e4) / liqThreshold;
     * uint256 maxWithdrawUSD = cTotalUSD - cNeededUSD - _withdrawBuffer; (units: 8 decimals)
     * maxWithdrawAmt = (maxWithdrawUSD * 10 ** (C_DECIMALS)) / cPriceUSD; (units: C_DECIMALS)
     * Docs: https://docs.aave.com/developers/guides/liquidations#how-is-health-factor-calculated
     */
    function _getMaxWithdrawAmt(address _debtService, address _cToken, uint8 _cDecimals)
        internal
        view
        returns (uint256 maxWithdrawAmt)
    {
        (uint256 cTotalUSD, uint256 dTotalUSD,, uint256 liqThreshold,,) =
            IPool(AAVE_POOL).getUserAccountData(_debtService);
        uint256 cPriceUSD = IAaveOracle(AAVE_ORACLE).getAssetPrice(_cToken);

        if (dTotalUSD == 0) {
            maxWithdrawAmt = type(uint256).max;
        } else {
            maxWithdrawAmt =
                ((cTotalUSD - ((dTotalUSD * 1e4) / liqThreshold) - WITHDRAW_BUFFER) * 10 ** (_cDecimals)) / cPriceUSD;
        }
    }

    function _getMaxBorrow(address _debtService, address _dToken, uint8 _dDecimals)
        internal
        view
        returns (uint256 maxBorrow)
    {
        (uint256 cTotalUSD, uint256 dTotalUSD,,, uint256 ltv,) = IPool(AAVE_POOL).getUserAccountData(_debtService);
        uint256 dPriceUSD = IAaveOracle(AAVE_ORACLE).getAssetPrice(_dToken);

        uint256 dMaxUSD = (cTotalUSD * ltv) / 1e4;
        // uint256 borrowBuffer = 10e8;
        uint256 maxBorrowUSD = dMaxUSD - dTotalUSD;

        maxBorrow = (maxBorrowUSD * 10 ** (_dDecimals)) / dPriceUSD;
    }
}
