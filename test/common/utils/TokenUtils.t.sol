// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

// External Imports
import { Test } from "forge-std/Test.sol";
import { VmSafe } from "forge-std/Vm.sol";

// Local Imports
import { Assets, USDC, USDC_HOLDER } from "test/common/Constants.t.sol";
import { IERC20 } from "src/interfaces/token/IERC20.sol";
import { IERC20Permit } from "src/interfaces/token/IERC20Permit.sol";

contract TokenUtils is Test {
    function _fund(address _account, address _token, uint256 _amount) internal {
        if (_token != USDC) {
            deal(_token, _account, _amount);
        } else {
            // Work around deal not working for USDC
            vm.startPrank(USDC_HOLDER);
            IERC20(USDC).transfer(_account, _amount);
            vm.stopPrank();
        }
    }

    function _getPermit(
        address _token,
        VmSafe.Wallet memory _wallet,
        address _spender,
        uint256 _value,
        uint256 _deadline
    ) internal view returns (uint8 v, bytes32 r, bytes32 s) {
        // 1. Get domain separator
        bytes32 domainSeparator = IERC20Permit(_token).DOMAIN_SEPARATOR();

        // 2. Get owner's nonce
        uint256 nonce = IERC20Permit(_token).nonces(_wallet.addr);

        // 3. Construct permit hash
        bytes32 hash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                domainSeparator,
                keccak256(
                    abi.encode(
                        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                        _wallet.addr,
                        _spender,
                        _value,
                        nonce++,
                        _deadline
                    )
                )
            )
        );
        // 4. Sign permit hash
        (v, r, s) = vm.sign(_wallet.privateKey, hash);
    }
}
