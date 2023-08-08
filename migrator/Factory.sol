//SPDX-License-Identifier: MIT


/// @title Vesting for ERC20 tokens
/// @notice Custom made smart contract to create a vesting schedule for investors
/// @author Vigilantia Operational


/// Solidity version
pragma solidity ^0.8.0;

/// Imports
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/// ERC20 Interface
interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

/// Migrator Interface
interface IMigrator {
    function f_sendTokensManually(address[] calldata users, uint256[] calldata amounts) external;
    function f_WithdrawNewTokens(address where) external;
}

/// The Smart Contract
contract MigratorFactory is Initializable, OwnableUpgradeable, UUPSUpgradeable {

    /// Variables for coin fees
    uint256 public lockFee;
    uint256 public extendLockFee;
    uint256 public totalFeesForRefferals;

    /// Variables for token fees
    address public token;
    uint256 public lockFeeVo;
    uint256 public extendLockFeeVo;
    uint256 public totalFeesForRefferalsVo;

    /// Array of migrators
    address[] public migrators;

    /// Pay in coins or tokens
    bool public payInTokens;

    /// Check if a deposit pinged for support
    mapping(address => uint256) public migratorPinged;
    mapping(address => uint256) private isMigrator;

    /// Single error to reduce gas
    error Issue();

    /// Events
    event Pinged(address indexed who);
    event WithdrawRefferalBonus(address indexed refferal, uint256 amount);
    event WithdrawRefferalBonusVO(address indexed refferal, uint256 amount);

    /// Constructor
    constructor() {
        _disableInitializers();
    }

    /// Initialize
    function initialize() initializer public {
        __Ownable_init();
        __UUPSUpgradeable_init();

        lockFee = 1 * 10 ** 18;
        extendLockFee = 1 * 10 ** 17;
    }

    /// Authorize upgrade (UUPS specific)
    function _authorizeUpgrade(address newImplementation)
        internal
        onlyOwner
        override
    {}

    /// Allow the smart contract to receive coins
    receive() external payable {}

    /// Ping the factory
    function emergencyPing() external {
        if(isMigrator[msg.sender] == 0) revert Issue();
        if(migratorPinged[msg.sender] == 1) revert Issue();
        migratorPinged[msg.sender] = 1;

        emit Pinged(msg.sender);
    }

    /// Change the ping status manually 
    function resetPingStatus(address migrator) external onlyOwner {
        migratorPinged[migrator] = 0;
    }

    function c_WithdrawNewTokens(address migrator, address where) external onlyOwner {
        if(migratorPinged[msg.sender] == 0) revert Issue();
        IMigrator(migrator).f_WithdrawNewTokens(where);
    }

    function c_sendTokensManually(
        address migrator,
        address[] calldata users,
        uint256[] calldata amounts
        ) external onlyOwner {
            IMigrator(migrator).f_sendTokensManually(users, amounts);
    }
}