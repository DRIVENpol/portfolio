/**
 * @title Reward Pools
 * @notice Receive interestae rate for each reward pool that is added based on
 *         your share of main pool
 * @author Socarde Paul
*/

//SPDX-License-Identifier: MIT

/**
 * Solidity version
 */
pragma solidity ^0.8.0;

/**
 * Local imports
 */
import "./Ownable.sol";
import "./Reentrancy-Guard.sol";

/**
 * Interfaces
 */
interface IToken {
    function balanceOf(
        address account
        ) 
        external
        view 
        returns (uint256);

    function approve(
        address spender,
        uint256 amount
        ) 
        external 
        returns (bool);

    function transfer(
        address recipient,
        uint256 amount
        ) 
        external 
        returns (bool);

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
        ) 
        external 
        returns (bool);
}

interface IRouter {
    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;

    function WETH() 
        external
        pure
        returns (address);
}

interface IFactory {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

contract StakingPackages is Ownable, ReentrancyGuard {
    /** Total staked amount */
    uint256 public totalPool;

    /** Total rewards in tokens */
    uint256 public rewardPool;

    /** Fees & Fee Managements */
    uint256 public entryFee;
    uint256 public exitFee;
    uint256 public totalFees;
    uint256 public threshold;

    uint256[] public feeAllocation;
    address[] public feeReceivers;

    /** Router */
    address public router;
    address public factory;
    address public wbnb;
    address public busd;

    address private zeroAddress = address(0);
    address private deadAddress = 0x000000000000000000000000000000000000dEaD;


    /** Main pool */
    uint256 public idMainPool;
    bool public mainPoolExist;
    /**
     * We assign an id to 'idMainPool' if
     * a pool with main token is created
     */

    /** Staking token */
    IToken public stakingToken;

    /** Struct for reward pools */
    struct RewardPool {
        uint256 totalRewards;
        uint256 startDate;
        uint256 endDate;
        uint256 duration;
        address rewardToken;
        bool enable;
    }

    /** Array of reward pools */
    RewardPool[] public rewardPools;

    /** Mappings */
    mapping(address => bool) public haveLiquidity;
    mapping(uint256 => uint256) public claimedInPool;
    mapping(address => uint256) public totalStakedByUser;
    mapping(address => uint256) public usersRewardsInAllPools;
    mapping(address => mapping(uint256 => bool)) public claimedAllInPool;
    mapping(address => mapping(uint256 => uint256)) public lastClaimInPool;
    mapping(address => mapping(uint256 => uint256)) public claimedDaysInPool;


    /** Events */
    event RedistributeFees();
    event SetStatusForPool(
        uint256 id,
        bool status
    );
    event Stake(
        address indexed user,
        uint256 amount
    );
    event SetFees(
        address[] receivers,
        uint256[] fees
    );
    event Unstake(
        address indexed user,
        uint256 amount
    );
    event ClaimRewards(
        address indexed user,
        uint256 rewards,
        uint256 id
    );
    event AddPool(
        address indexed rToken,
        uint256 rAmount,
        uint256 duration
    );
    event CompoundRewards(
        address indexed user,
        uint256 rewards,
        uint256 id
    );
    event AddRewardsInPool(
        uint256 amount,
        uint256 poolId
    );
    event ProlongTimeInPool(
        uint256 timeInDays,
        uint256 poolId
    );

    /** 
     * @dev The constructor
     * @param _stakingToken The address of the token that will be staked
     * @param _router The address of PancakeSwap router
     */
    constructor(
        address _stakingToken,
        address _router
    ) {
        stakingToken = IToken(_stakingToken);
        router = _router;
    }

    /**
     * @dev Function to add a new pool
     * @notice If the rewardToken = main token
     *         we set the value of 'mainPollExist' to true
     *         and we asign the id of the pool to 'idMainPool'
     * @param rewardToken The token used for rewards
     * @param rewardAmount The amount that will be distirbuted to stakers
     * @param duration The duration of the pool
     * @param liquid If the token have liquidity on an exchange or not
     */
    function addPool(
        address rewardToken,
        uint256 rewardAmount,
        uint256 duration,
        bool liquid
    ) 
        external
        onlyOwner 
    {
        require(
            IToken(rewardToken).transferFrom(msg.sender, address(this), rewardAmount),
            "Can't add rewards!"
            );

        if (rewardToken == address(stakingToken)) {
            idMainPool = rewardPools.length;
            mainPoolExist = true;
        }

        uint256 _duration = duration * 1 days;
        uint256 _startDate = block.timestamp;
        uint256 _endDate = block.timestamp + _duration;

        if(liquid) {
            haveLiquidity[rewardToken] = true;
        }

        RewardPool memory _pool = RewardPool(
            rewardAmount,
            _startDate,
            _endDate,
            _duration,
            rewardToken,
            true
        );

        rewardPools.push(_pool);
        emit AddPool(rewardToken, rewardAmount, duration);
    }

    /**
     * @dev Function to add more rewards in a pool
     * @param amount Amount to add for rewards
     * @param poolId For which pool do we want to increase the reward amount
     */
    function addRewards(
        uint256 amount,
        uint256 poolId
    )
    external
    onlyOwner
    {
        require(
            poolId < rewardPools.length,
            "Non-existent pool!"
        );

        RewardPool storage _pool = rewardPools[poolId];

        require(
            IToken(_pool.rewardToken).transferFrom(msg.sender, address(this), amount),
            "Can't add rewards!"
            );

        unchecked {
            _pool.totalRewards += amount;
        }

        emit AddRewardsInPool(amount, poolId);
    }

    /**
     * @dev Function to extend the end date for a pool
     * @param timeInDays How many days do we want to add
     */
    function extendRewardPool(
        uint256 timeInDays,
        uint256 poolId
    )
    external
    onlyOwner
    {
        require(
            poolId < rewardPools.length,
            "Non-existent pool!"
        );

        RewardPool storage _pool = rewardPools[poolId];

        uint256 _timeInDays = timeInDays * 1 days;
        uint256 currentEndDate = _pool.endDate;

        if(block.timestamp < currentEndDate) {
            unchecked {
                _pool.endDate += _timeInDays;
            }
        } else if (block.timestamp >= currentEndDate) {
            unchecked {
                 _pool.endDate = block.timestamp + _timeInDays;
            }
        }

        emit ProlongTimeInPool(timeInDays, poolId);
    }

    /**
     * @dev Function to reduce the time of a pool
     */
    function reduceTimeOfPool(
        uint256 timeInDays,
        uint256 poolId
    )
    external 
    onlyOwner 
    {
        require(
            poolId < rewardPools.length,
            "Non-existent pool!"
        );

        RewardPool storage _pool = rewardPools[poolId];

        uint256 _timeToCut = timeInDays * 1 days;
        
        require(
            _pool.endDate - _timeToCut > block.timestamp,
            "Can't cut that much!"
        );

        _pool.endDate -= _timeToCut;
    }

    /**
     * @dev Function to reduce the rewards in a pool
     */
    function reduceRewardsOfPool(
        uint256 rewardsToCut,
        uint256 poolId
    )
    external 
    onlyOwner 
    {
        require(
            poolId < rewardPools.length,
            "Non-existent pool!"
        );

        RewardPool storage _pool = rewardPools[poolId];

        require(
            _pool.totalRewards - rewardsToCut > 0,
            "Can't cut that much!"
        );

        _pool.totalRewards -= rewardsToCut;
    }

    /**
     * @dev Function to disable/enable a pool
     * @param id Which pool to disable
     * @param status What status do we want to set
     */
    function setStatusForPool(
        uint256 id,
        bool status
    ) 
        external
        onlyOwner 
    {
        require(
            id < rewardPools.length,
            "Invalid pool!"
            );

        RewardPool storage _pool = rewardPools[id];

        require(
            _pool.enable != status,
            "Status in use!"
            );

        _pool.enable = status;

        emit SetStatusForPool(id, status);
    }

    /**
     * @dev Function to set fees & fee receivers
     */
    function setFees(
        address[] calldata _feeReceivers,
        uint256[] calldata _fees
        ) 
        external
        onlyOwner 
    {
        require(
            _feeReceivers.length == _fees.length,
            "Invalid amounths!"
            );

        uint256 _totalFees;

        for (uint256 i = 0; i < _fees.length;) {
            _totalFees += _fees[i];
            unchecked {
                ++i;
            }
        }

        require(
            _totalFees <= 100,
            "Invalid fee alocation!"
            );

        for (uint256 i = 0; i < _fees.length;) {
            feeAllocation[i] = _fees[i];
            feeReceivers[i] = _feeReceivers[i];
            unchecked {
                ++i;
            }
        }

        emit SetFees(_feeReceivers, _fees);
    }

    /**
     * @dev Function to change the address of staking token
     */
    function changeStakingToken(
        address newStakingToken
    )
    external 
    onlyOwner 
    {
        require(
            newStakingToken != zeroAddress &&
            newStakingToken != deadAddress,
            "Invalid address!"
        );
        
        stakingToken = IToken(newStakingToken);
    }

    /**
     * @dev Function to change the router address
     */
    function changeRouter(
        address newRouter
    )
    external 
    onlyOwner 
    {
        require(
            newRouter != zeroAddress &&
            newRouter != deadAddress,
            "Invalid address!"
        );

        router = newRouter;
    }

    /**
     * @dev Function to change the factory address
     */
    function changeFactory(
        address newFactory
    )
    external 
    onlyOwner 
    {
        require(
            newFactory != zeroAddress &&
            newFactory != deadAddress,
            "Invalid address!"
        );

        router = newFactory;
    }
    
    /**
     * @dev Function to stake main token
     * @param amount Amount to stake
     */
    function stake(
        uint256 amount
    ) 
        external 
        nonReentrant 
    {
        require(
            stakingToken.transferFrom(msg.sender, address(this), amount), 
            "Can't stake tokens!"
            );

        unchecked {
            totalStakedByUser[msg.sender] += amount;
            totalPool += amount;
        }

        usersRewardsInAllPools[msg.sender] = _computeShareOfThePool(msg.sender);

        uint256 _fee = amount * entryFee / 100;

        unchecked {
            totalFees += _fee;
        }

        _checkAndSendFees();

        emit Stake(msg.sender, amount);
    }

    /**
     * @dev Function to unstake tokens
     * @param amount The amount that we want to unstake
     */
    function unstake(
        uint256 amount
    ) 
        external
        nonReentrant 
    {
        require(
            amount <= totalStakedByUser[msg.sender],
            "Can't unstake that much!"
            );
        
        totalStakedByUser[msg.sender] -= amount;
        totalPool -= amount;

        // Take the fee
        uint256 _fee = amount * exitFee / 100;
        unchecked {
            totalFees += _fee;
        }

        _checkAndSendFees();

        require(
            stakingToken.transfer(msg.sender, amount - _fee),
            "Can't unstake!"
            );

         emit Unstake(msg.sender, amount);
    }

    /**
     * @dev Function to claim all rewards from each pool
     */
    function claimAll() 
    external 
    {
        for (uint256 i = 0; i < rewardPools.length;) {
            claimRewards(i);
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @dev Function to compound all rewards from each pool
     */
    function compoundAll() 
        external 
    {
        for (uint256 i = 0; i < rewardPools.length;) {
            compoundRewards(i);
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @dev Function to fetch the length of the packages array
     */
    function getNoOfPackages() 
        external 
        view 
        returns (uint256) 
    {
        return rewardPools.length;
    }
    /**
     * @dev Function to display the tokens claimed in a pool
     */
    function getClaimedInPool(
        uint256 poolId
    )
    external
    view
    returns (uint256) {
        return claimedInPool[poolId];
    }

    /**
     * @dev Function to fetch the ids of active packages
     */
    function getActivePackages() external view returns (uint256[] memory) {
        uint256[] memory ids = new uint256[](rewardPools.length);
        uint256 index;

        for (uint256 i = 0; i < rewardPools.length; i++) {
            if (rewardPools[i].enable) {
                ids[index] = i;

                unchecked {
                    ++index;
                }
            }
        }

        assembly {
            mstore(ids, index)
        }

        return ids;
    }

    /**
     * @dev Function to fetch the details of a package
     */
    function getDetailsOfPackage(
        uint256 packageId
    ) 
        external 
        view 
        returns(RewardPool memory) 
    {
        return rewardPools[packageId];
    }

    /**
     * @dev Function to claim rewards from one reward pool
     * @param rewardPoolId From which pool do we want to claim the rewards
     */
    function claimRewards(
        uint256 rewardPoolId
    ) 
        public 
        nonReentrant
    {
        require(
            rewardPoolId < rewardPools.length,
            "Invalid pool!"
            );

        uint256 _lastClaim = lastClaimInPool[msg.sender][rewardPoolId];
        
        if (
            claimedAllInPool[msg.sender][rewardPoolId] == true || 
            rewardPools[rewardPoolId].enable == false ||
            block.timestamp >= _lastClaim + 1 days
            ) 
        {
            return;
        }

        uint256 _rewards = computeRewards(msg.sender, rewardPoolId);

        if (_rewards == 0) {
            return;
        }

        require(
            stakingToken.transfer(msg.sender, _rewards),
            "Can't claim rewards!"
            );
        unchecked {
            claimedInPool[rewardPoolId] += _rewards;
        }

        emit ClaimRewards(msg.sender, _rewards, rewardPoolId);
    }

    /**
     * @dev Function to compound rewards from one reward pool
     * @param rewardPoolId From which pool do we want to claim the rewards
     */
    function compoundRewards(
        uint256 rewardPoolId
    )
        public
        nonReentrant 
    {
        require(
            rewardPoolId < rewardPools.length,
            "Invalid pool!"
            );

        uint256 _lastClaim = lastClaimInPool[msg.sender][rewardPoolId];

        require(
            block.timestamp >= _lastClaim + 1 days,
            "Wait 24h before you claim!"
            );

        if(!haveLiquidity[rewardPools[rewardPoolId].rewardToken]) {
            return;
        }

        address _liquidityToken = _checkLiquidity(rewardPools[rewardPoolId].rewardToken);

        if(_liquidityToken == address(0)) {
            return;
        }
        
        if (claimedAllInPool[msg.sender][rewardPoolId] == true || 
        rewardPools[rewardPoolId].enable == false) {
            return;
        }
        uint256 _rewards = computeRewards(msg.sender, rewardPoolId);
        // Swap the rewards for main token
        uint256 _balanceBefore = stakingToken.balanceOf(address(this));
        swapTokensForMainToken(_rewards, rewardPools[rewardPoolId].rewardToken, _liquidityToken);
        uint256 _balanceAfter = stakingToken.balanceOf(address(this));
        // Re-stake the rewards
        uint256 _toRestake = _balanceBefore - _balanceAfter;
        rewardPools[rewardPoolId].totalRewards += _toRestake;

        unchecked {
            totalStakedByUser[msg.sender] += _toRestake;
            totalPool += _toRestake;
        }

        emit CompoundRewards(msg.sender, _rewards, rewardPoolId);
    }

    /**
     * @dev Function to compute the share of the pool for user
     * @param user For which EOA do we want to compute the shares of the pool
     */
    function _computeShareOfThePool(
        address user
    ) 
        public 
        view 
        returns (uint256) 
    {
        return (totalStakedByUser[user] * 100) / totalPool;
    }

    /**
     * @dev Function to swap the rewards for main token
     */
    function swapTokensForMainToken(
        uint256 tokenAmount,
        address fromToken,
        address middleToken
        ) 
        internal 
    {

        address _liquidityForMainToken = _checkLiquidity(address(stakingToken));

        if(_liquidityForMainToken == middleToken) {
            address[] memory path = new address[](3);
            path[0] = fromToken;
            path[1] = middleToken;
            path[2] = address(stakingToken);

            IToken(fromToken).approve(router, tokenAmount);

            IRouter(router).swapExactTokensForTokensSupportingFeeOnTransferTokens(
                tokenAmount,
                0,
                path,
                address(this),
                block.timestamp
            );
        } else if(_liquidityForMainToken != middleToken) {
            address[] memory path = new address[](4);
            path[0] = fromToken;
            path[1] = middleToken;
            path[2] = _liquidityForMainToken
            path[3] = address(stakingToken);

            IToken(fromToken).approve(router, tokenAmount);

            IRouter(router).swapExactTokensForTokensSupportingFeeOnTransferTokens(
                tokenAmount,
                0,
                path,
                address(this),
                block.timestamp
            );  
        }
    }

    /**
     * @dev Function to compute the rewards
     */
    function computeRewards(
        address user,
        uint256 rewardPoolId
    ) 
        public
        returns(uint256) 
    {
       RewardPool storage _pool = rewardPools[rewardPoolId];

       uint256 _shareOfPool = _computeShareOfThePool(user);

        uint256 _toClaim = _shareOfPool * _pool.totalRewards / 100;
        uint256 _toClaimPerDay = _toClaim / _pool.duration;

        // Get claimed day by user in that pool
        uint256 _claimedDays = claimedDaysInPool[user][rewardPoolId];

        if (block.timestamp >= _pool.endDate) {
            uint256 _deltaClaimed = _pool.duration - _claimedDays;
            uint256 _rewards = _deltaClaimed * _toClaimPerDay;

            require(
                claimedDaysInPool[user][rewardPoolId] + _deltaClaimed <= _pool.duration, 
                "Can't claim anymore!"
                );

            _pool.totalRewards -= _rewards;

            unchecked {
                claimedDaysInPool[user][rewardPoolId] += _deltaClaimed;
            }

            claimedAllInPool[user][rewardPoolId] = true;

            return _rewards;
        } else {
            uint256 _timeElapsed = block.timestamp - _pool.startDate;
            uint256 _timeElapsedInDays = _timeElapsed / 86400;
            uint256 _rewards = _timeElapsedInDays * _toClaimPerDay;

            require(
                claimedDaysInPool[user][rewardPoolId] + _timeElapsedInDays <= _pool.duration, 
                "Can't claim anymore!"
                );

            require(
                stakingToken.transfer(user, _rewards),
                "Can't send rewards!"
                );

            _pool.totalRewards -= _rewards;

            unchecked {
                claimedDaysInPool[user][rewardPoolId] += _timeElapsedInDays;
            }
            if (claimedDaysInPool[user][rewardPoolId] + _timeElapsedInDays == _pool.duration) {
                claimedAllInPool[user][rewardPoolId] = true;
            }

            return _rewards;
        }
    }

    /**
     * @dev Function to check if we reached the threshold
     * @notice If yes, we distribute the rewards
     */
    function _checkAndSendFees() 
        internal 
    {
        if (totalFees >= threshold) {
            _redistributeFees();

        } else {
            return;
        }
    }

    /**
     * @dev Function to redistribute the fees
     * @return true After execution
     */
    function _redistributeFees() 
        internal 
        returns (bool)
    {
       if(feeReceivers.length == 0) {
        return false;
       }

       for (uint256 i = 0; i < feeReceivers.length;) {
        uint256 _fee = feeAllocation[i];
        uint256 _feeAmount = totalFees * _fee / 100;

        if (feeReceivers[i] == address(this)) {
            require(
                _increaseRewardPool(_feeAmount),
                "Can't increase the reward pool!"
                );

        } else {
            require(
                stakingToken.transfer(feeReceivers[i], _feeAmount),
                "Can't send fees!"
                );

        }
        unchecked {
            ++i;
        }
       }

       uint256 _delta = totalFees - threshold;
       if (_delta > 0) {
        totalFees = _delta;
       } else {
        totalFees = 0;
       }

    emit RedistributeFees();

    return true;
    }

    /**
     * @dev Function to increase the reward pool
     * @param amount The amount that will be added in the
     *               reward pool
     * @return true After execution
     */
    function _increaseRewardPool(
        uint256 amount
    ) 
        internal 
        returns (bool) 
    {
        rewardPool += amount;

        if (mainPoolExist) {
            RewardPool storage _pool = rewardPools[idMainPool];
            _pool.totalRewards += rewardPool;
            rewardPool = 0;
        }

        return true;
    }

    /**
     * @dev Function to check if there is liquidity for a token
     *      before swapping it
     * @param tokenToCheck The token that we are checking
     */
    function _checkLiquidity(
        address tokenToCheck
    )
    internal
    view
    returns (address)
    {
        IFactory _factory = IFactory(factory);
        address _pair0 = _factory.getPair(tokenToCheck, wbnb);
        address _pair1 = _factory.getPair(tokenToCheck, busd);

        if(
            _pair0 != address(0) &&
            IToken(wbnb).balanceOf(_pair0 ) > 0
        ) {
           return wbnb;
        } else if(
            _pair1 != address(0) &&
            IToken(busd).balanceOf(_pair0 ) > 0
        ) {
            return busd;
        } else {
            return address(0);
        }
    }
}