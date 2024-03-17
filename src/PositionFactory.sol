// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

// Local
import { Position } from "src/Position.sol";
import { Ownable } from "src/dependencies/access/Ownable.sol";
import { SafeTransferLib, ERC20 } from "solmate/utils/SafeTransferLib.sol";
import { IPositionFactory } from "src/interfaces/IPositionFactory.sol";
import { IERC20 } from "src/interfaces/token/IERC20.sol";

/// @title The position factory contract
/// @author Chain Rule, LLC
/// @notice Creates user position contracts and stores their addresses for all users
contract PositionFactory is Ownable, IPositionFactory {
    // Constants: no SLOAD to save gas
    address private constant CONTRACT_DEPLOYER = 0x0a5B347509621337cDDf44CBCf6B6E7C9C908CD2;

    // Factory Storage
    /// @inheritdoc IPositionFactory
    mapping(address => mapping(address => mapping(address => mapping(address => address)))) public positions;

    /// @notice A mapping of all positions owned by a user.
    mapping(address => address[]) public positionsLookup;

    // Errors
    error Unauthorized();
    error PositionExists();

    // Events
    /// @notice An event emitted when a position contract is created.
    /// @param owner The owner of the created Position contract.
    /// @param position The address of the created Position contract.
    event PositionCreated(address indexed owner, address indexed position);

    /// @notice This function is called when the PositionFactory is deployed.
    /// @param _owner The account address of the PositionFactory contract's owner.
    constructor(address _owner) Ownable(_owner) {
        if (msg.sender != CONTRACT_DEPLOYER) revert Unauthorized();
    }

    /// @inheritdoc IPositionFactory
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

    /// @inheritdoc IPositionFactory
    function getPositions(address _positionOwner) public view returns (address[] memory) {
        return positionsLookup[_positionOwner];
    }

    /* ****************************************************************************
    **
    **  ADMIN FUNCTIONS
    **
    ******************************************************************************/

    /// @inheritdoc IPositionFactory
    function extractNative() public payable onlyOwner {
        payable(msg.sender).transfer(address(this).balance);
    }

    /// @inheritdoc IPositionFactory
    function extractERC20(address _token) public payable onlyOwner {
        uint256 balance = IERC20(_token).balanceOf(address(this));

        SafeTransferLib.safeTransfer(ERC20(_token), msg.sender, balance);
    }

    /**
     * @notice Executes when native is sent to this contract through a non-existent function.
     */
    fallback() external payable { } // solhint-disable-line no-empty-blocks
}
