//SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/** IMPORTS */
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "./Reentrancy-Guard.sol";
import "./Ownable.sol";

/** INTERFACES */
interface IToken {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
}

interface ISubscription {
    function isValidSubscription(address user) external view returns (bool);
}

/**
 * @title NFT Staking Pool
 * @author Socarde Paul
 * @notice Earn passive income while you have an active subscription
 */

contract Staking_Nft is Ownable, ReentrancyGuard {

    /** VARIABLES */
    uint256 public initialized = 1;
    uint256 public totalClaimed;
    address public rewardToken;
    address public feeToken;
    address public stakeCollection; // ERC-721 Collection
    address public subscription;

    address private zeroAddress = address(0);
    address private deadAddress = 0x000000000000000000000000000000000000dEaD;

    /** POOL */
    struct Pool {
        uint256 stakedNfts;
        uint256 enterFee;
        uint256 lockPeriod;
        bool active;
    }

    /** DEPOSIT */
    struct Deposit {
        uint256 endDate;
    }

    /** THE MAIN POOL */
    Pool public mainPool;

    /** MAPPINGS */
    mapping (address => uint256) public enterStaking;
    mapping (address => Deposit) public userToDeposit;

    /** EVENTS */
    event PoolCreated(
        uint256 rewards, 
        uint256 fee, 
        uint256 lockPeriod
    );
    event RewardsAdded(
        uint256 amount
    );
    event NewDeposit(
        address indexed user
    );
    event UnstakeAndClaim(
        address indexed user
    );

    /** CONSTRUCTOR */
    constructor(
        address _subscription
    ) {
        require(
            _subscription != zeroAddress &&
            _subscription != deadAddress,
            "Invalid address!"
        );

        subscription = _subscription;
    }

    /** RECEIVE FUNCTION */
    receive() external payable {}

    /** EXTERNAL FUNCTIONS */
    /**
     @dev Function to add a new pool;
     @param _lockPeriod The lock period;
     @param _rewards The rewards available for distribution;
     @param _fee Fee to pay when a user wants to enter;
     @notice As the free NFT is not transferable, only one pool can be created;
     */
    function addPool(
        uint256 _lockPeriod,
        uint256 _rewards,
        uint256 _fee
    )
        external
        onlyOwner
    {
        require(initialized == 1, "Can't add more pools!");
        initialized = 2;

        require(
            IToken(rewardToken).transferFrom(
                msg.sender,
                address(this),
                _rewards),
                "Can't receive the rewards!"
        );

        Pool memory _pool = Pool(0, _fee, _lockPeriod, true);

        mainPool = _pool;

        emit PoolCreated(_rewards, _fee, _lockPeriod);
    }

    /**
     * @dev Function to add more rewards into the pool;
     */
    function addRewards(
        uint256 _rewardAmount
    )
    external
    onlyOwner 
    {
        require(
            IToken(rewardToken).transferFrom(
                msg.sender,
                address(this),
                _rewardAmount),
                "Can't receive the rewards!"
        );

        emit RewardsAdded(_rewardAmount);
    }

    /**
     * @dev Function to change the enterFee;
     * @param newFee The new fee to pay in order to enter the pool;
     */
    function changeFee(
        uint256 newFee
    )
    external
    onlyOwner 
    {
        mainPool.enterFee = newFee;
    }

    /**
     * @dev Function to change the lockPeriod;
     * @param newLockPeriod The new lock period;
     */
    function changeLockPeriod(
        uint256 newLockPeriod
    )
    external
    onlyOwner 
    {
        mainPool.lockPeriod = newLockPeriod;
    }

    /**
     * @dev Function to change the status of the pool;
     */
    function changeStatus() external onlyOwner 
    {
       if(mainPool.active) {
        mainPool.active = false;
       } else {
        mainPool.active = true;
       }
    }

    /**
     @dev Function to change the rewardToken;
     @param newToken The address of new token used for rewards;
     */
    function changeRewardToken(
        address newToken
    )
    external
    onlyOwner 
    {
        require(
            newToken != zeroAddress &&
            newToken != deadAddress,
            "Invalid address!"
        );

        rewardToken = newToken;
    }

    /**
     @dev Function to change the stakeCollection;
     @param newToken The address of new ERC-721 token used for staking;
     */
    function changeStakingCollection(
        address newToken
    )
    external
    onlyOwner 
    {
        require(
            newToken != zeroAddress &&
            newToken != deadAddress,
            "Invalid address!"
        );
        
        stakeCollection = newToken;
    }

    /**
     * @dev Function to enter the pool
     */
    function enterPool() external nonReentrant {
        require(
            enterStaking[msg.sender] == 0,
            "You already staked!"
        );

        enterStaking[msg.sender] = 1;

        require(
            _checkSubscription(msg.sender),
            "You don't have an active subscription NFT!"
        );

        if(mainPool.enterFee > 0) {
            require(
                IToken(feeToken).transferFrom(
                    msg.sender, 
                    address(this), 
                    mainPool.enterFee
                    ),
                    "Can't pay the fee!"
            );
        }

        uint256 _endDate = block.timestamp + (mainPool.lockPeriod * 1 days);

        Deposit memory newDeposit = Deposit(
            _endDate
        );

        userToDeposit[msg.sender] = newDeposit;

        ++mainPool.stakedNfts;

        emit NewDeposit(msg.sender);
    }

    /**
     * @dev Function to unstake and claim the rewards;
     */
    function unstakeAndClaim() external nonReentrant {
        Deposit storage _deposit = userToDeposit[msg.sender];

        require(
            _checkSubscription(msg.sender),
            "You don't have an active subscription NFT!"
        );

        require(
            enterStaking[msg.sender] == 1,
            "You are not in staking!"
        );

        enterStaking[msg.sender] = 0;

        require(
            block.timestamp >= _deposit.endDate,
            "Can't unstake now!"
        );

        uint256 _rewards = computeRewards();

        require(
            _rewards > 0,
            "Insufficient rewards!"
        );

        require(
            IToken(rewardToken).transfer(msg.sender, _rewards),
            "Can't distribute rewards!"
        );

        _deposit.endDate = 1;

        --mainPool.stakedNfts;

        unchecked {
            totalClaimed += _rewards;
        }

        emit UnstakeAndClaim(msg.sender);
    }

    /** PUBLIC FUNCTIONS */
    /** 
     * @dev Function to compute the allocated rewards / NFT;
     */
    function computeRewards() public view returns (uint256) {
        uint256 _stakedNfts = mainPool.stakedNfts;
        uint256 _availableRewards = IToken(rewardToken).balanceOf(address(this));

        return _availableRewards / _stakedNfts;
    }

    /** 
     * @dev Function to compute the available rewards;
     */
    function availableRewards() public view returns (uint256) {
        return IToken(rewardToken).balanceOf(address(this));
    }

    /** INTERNAL FUNCTIONS */
    /**
     * @dev Function to check if the user have an active subscription;
     */
    function _checkSubscription(address user) internal view returns(bool) {
        return ISubscription(subscription).isValidSubscription(user);
    }
}
