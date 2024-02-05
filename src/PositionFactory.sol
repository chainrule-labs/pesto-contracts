// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

// Local
import { Position } from "src/Position.sol";
import { Ownable } from "src/dependencies/access/Ownable.sol";
import { SafeTransferLib, ERC20 } from "solmate/utils/SafeTransferLib.sol";
import { IERC20 } from "src/interfaces/token/IERC20.sol";

/// @title Position Factory
/// @author Chain Rule, LLC
/// @notice Creates user position contracts and stores their addresses
contract PositionFactory is Ownable {
    // Constants: no SLOAD to save gas
    address private constant CONTRACT_DEPLOYER = 0x0a5B347509621337cDDf44CBCf6B6E7C9C908CD2;

    // Factory Storage
    /// @dev Mapping from owner to cToken to dToken to bToken to position
    mapping(address => mapping(address => mapping(address => mapping(address => address)))) public positions;
    mapping(address => address[]) public positionsLookup;

    // Errors
    error Unauthorized();
    error PositionExists();

    // Events
    event PositionCreated(address indexed owner, address indexed position);

    constructor(address _owner) Ownable(_owner) {
        if (msg.sender != CONTRACT_DEPLOYER) revert Unauthorized();
    }

    /**
     * @notice Deploys a Position contract for msg.sender, given a _cToken, _dToken, and _bToken.
     * @param _cToken The address of the token to be used as collateral.
     * @param _dToken The address of the token to be borrowed.
     * @param _bToken The address of the token to swap _dToken for.
     */
    function createPosition(address _cToken, address _dToken, address _bToken)
        public
        payable
        returns (address position)
    {
        if (positions[msg.sender][_cToken][_dToken][_bToken] != address(0)) revert PositionExists();

        position = address(new Position(msg.sender, _cToken, _dToken, _bToken));

        positionsLookup[msg.sender].push(position);
        positions[msg.sender][_cToken][_dToken][_bToken] = position;

        emit PositionCreated(msg.sender, position);
    }

    /**
     * @notice Returns a list of contract addresses for the given _positionOwner.
     * @param _positionOwner The owner of the Position contracts.
     */
    function getPositions(address _positionOwner) public view returns (address[] memory) {
        return positionsLookup[_positionOwner];
    }

    /* ****************************************************************************
    **
    **  ADMIN FUNCTIONS
    **
    ******************************************************************************/
    /**
     * @notice Allows OWNER to withdraw all of this contract's native token balance.
     */
    function extractNative() public payable onlyOwner {
        payable(msg.sender).transfer(address(this).balance);
    }

    /**
     * @notice Allows OWNER to withdraw all of a specified ERC20 token's balance from this contract.
     * @param _token The address of token to remove.
     */
    function extractERC20(address _token) public payable onlyOwner {
        uint256 balance = IERC20(_token).balanceOf(address(this));

        SafeTransferLib.safeTransfer(ERC20(_token), msg.sender, balance);
    }

    /**
     * @notice Executes when native is sent to this contract through a non-existent function.
     */
    fallback() external payable { } // solhint-disable-line no-empty-blocks

    /**
     * @notice Executes when native is sent to this contract with a plain transaction.
     */
    receive() external payable { } // solhint-disable-line no-empty-blocks
}
