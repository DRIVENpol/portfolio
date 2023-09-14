// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import "../../lib/openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";

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

    uint256 public idMainPool;
    uint256 public totalStakedInPool;
    uint256 public totalGivenRewards;
    uint256 public totalUniqueStakers;

    uint256 public entryFee;
    uint256 public exitFee;
    uint256 public totalCollectedFees;
    uint256 public threshold;

    uint256[] public feeAllocations;
    address[] public feeReceivers;

    address public router = 0xD99D1c33F9fC3444f8101754aBC46c52416550D1; // Testnet
    address public factory = 0x46E9aD48575d08072E9A05a9BDE4F22973628A8E; // Testnet
    address public wbnb =  0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd; // Testnet
    address public busd;

    address public immutable zeroAddress = address(0);
    address public immutable deadAddress = 0x000000000000000000000000000000000000dEaD;

    bool public mainPoolExist;
    bool public generalPause;

    IToken public stakingToken;

    struct RewardPool {
        uint256 startDate;
        uint256 endDate;
        uint256 duration;
        uint256 totalClaimedRewards;
        uint256 totalAllocatedRewards;
        address token;
        bool enable;
        bool tokenHaveLiquditity;
    }

    struct User {
        uint256 totalStaked;
        mapping(uint256 => uint256) rewardsClaimedInPool;
        mapping(uint256 => uint256) lastClaimInPool;
        mapping(uint256 => uint256) claimedDaysInPool;
    }

    RewardPool[] public rewardPools;

    mapping(address => User) public users;
    mapping(address => uint256) public tokenToIndex;
    mapping(address => bool) public isTokenAdded;

    constructor(
        address _stakingToken
    ) {
        require(_validAddress(_stakingToken), "Staking: stakingToken must be valid address");

        stakingToken = IToken(_stakingToken);
    }

    /** Events */
    event PoolAdded(
        uint256 indexed poolIndex,
        uint256 startDate,
        uint256 endDate,
        uint256 duration,
        uint256 totalClaimedRewards,
        uint256 totalAllocatedRewards,
        address token,
        bool enable,
        bool tokenHaveLiquditity
    );
    event PoolModified(
        uint256 indexed poolIndex,
        uint256 startDate,
        uint256 endDate,
        uint256 duration,
        uint256 totalClaimedRewards,
        uint256 totalAllocatedRewards,
        address token,
        bool enable,
        bool tokenHaveLiquditity
    );
    event TogglePauseUpdate();
    event ChangeFees(
        uint256 entryFee,
        uint256 exitFee,
        uint256 threshold
    );
    event AddFeeAllocation(
        uint256 feeAllocation,
        address feeReceiver
    );
    event RemoveFeeAllocation(
        uint256 index
    );
    event ChangeRouterAndFactory(
        address router,
        address factory
    );
    event ChangeWbnbAndBusd(
        address wbnb,
        address busd
    );
    event ChangeStakingToken(
        address stakingToken
    );
    event Stake(
        address user,
        uint256 amount
    );
    event Unstake(
        address user,
        uint256 amount
    );
    event RedistributeFees(
        uint256 amount
    );
    event IncreaseRewardsInPool(
        uint256 amount
    );
    event ChangePoolStatus(
        uint256 poolIndex,
        bool status
    );

    /** External functions */

    /**
        * @dev Add new pool
        * @param duration Duration of pool
        * @param totalAllocatedRewards Total allocated rewards for pool
        * @param token Token for rewards
        * @param increaseAmount Increase amount of pool (yes/no)
        * @param increaseDuration Increase duration of pool (yes/no)
     */
    function addPool(
        uint256 duration,
        uint256 totalAllocatedRewards,
        address token,
        bool increaseAmount,
        bool increaseDuration
    )
        external
        onlyOwner 
    {
        // require(duration > 0, "Staking: duration must be greater than 0");
        // require(totalAllocatedRewards > 0, "Staking: totalAllocatedRewards must be greater than 0");
        require(_validAddress(token), "Staking: token must be valid address");

        if(isTokenAdded[token]) {
            if(increaseAmount && totalAllocatedRewards > 0) {
                rewardPools[tokenToIndex[token]].totalAllocatedRewards += totalAllocatedRewards;

                require(
                    IToken(token).transferFrom(
                        msg.sender,
                        address(this),
                        totalAllocatedRewards
                    ),
                    "Staking: transferFrom failed"
                );
            } else if(!increaseAmount && totalAllocatedRewards > 0){
                require(
                    rewardPools[tokenToIndex[token]].totalAllocatedRewards - totalAllocatedRewards > 0,
                    "Staking: totalAllocatedRewards must be greater than 0"
                );

                rewardPools[tokenToIndex[token]].totalAllocatedRewards -= totalAllocatedRewards;

                require(
                    IToken(token).transfer(
                        msg.sender,
                        totalAllocatedRewards
                    ),
                    "Staking: transfer failed"
                );
            }

            if(increaseDuration && duration > 0) {
                rewardPools[tokenToIndex[token]].duration += duration;
                rewardPools[tokenToIndex[token]].endDate += (duration * 1 days);
            } else if(!increaseDuration && duration > 0) {
                require(
                    rewardPools[tokenToIndex[token]].endDate - duration * 1 days > rewardPools[tokenToIndex[token]].startDate,
                    "Staking: duration must be greater than startDate"
                );

                rewardPools[tokenToIndex[token]].endDate -= (duration * 1 days);
                rewardPools[tokenToIndex[token]].duration -= duration;
            }

            emit PoolModified(
                tokenToIndex[token],
                rewardPools[tokenToIndex[token]].startDate,
                rewardPools[tokenToIndex[token]].endDate,
                rewardPools[tokenToIndex[token]].duration,
                rewardPools[tokenToIndex[token]].totalClaimedRewards,
                rewardPools[tokenToIndex[token]].totalAllocatedRewards,
                rewardPools[tokenToIndex[token]].token,
                rewardPools[tokenToIndex[token]].enable,
                rewardPools[tokenToIndex[token]].tokenHaveLiquditity
            );

            return;
        }

        require(
            IToken(token).transferFrom(
                msg.sender,
                address(this),
                totalAllocatedRewards
            ),
            "Staking: transferFrom failed"
        );

        uint256 index = rewardPools.length;

        if(address(stakingToken) == token) {
            idMainPool = index;
        }

        bool haveLiquidity = _checkLiquidity(token) != zeroAddress;

        rewardPools.push(RewardPool({
            startDate: block.timestamp,
            endDate: block.timestamp + (duration * 1 days),
            duration: duration,
            totalClaimedRewards: 0,
            totalAllocatedRewards: totalAllocatedRewards,
            token: token,
            enable: true,
            tokenHaveLiquditity: haveLiquidity
        }));

        tokenToIndex[token] = index;
        isTokenAdded[token] = true;

        emit PoolAdded(
            index,
            block.timestamp,
            block.timestamp + duration * 1 days,
            duration,
            0,
            totalAllocatedRewards,
            token,
            true,
            haveLiquidity
        );
    }

    /**
        * @dev Withdraw ERC20 tokens
        * @param tokenAddress Address of token
     */
    function withdrawERC20Tokens(
        address tokenAddress
    )
        external
        onlyOwner
    {
        uint256 amount = IToken(tokenAddress).balanceOf(address(this));

        require(
            IToken(tokenAddress).transfer(msg.sender, amount),
            "Can't withdraw tokens!"
        );
    }

    /**
        * @dev Pause/unpause
     */
    function togglePause() external onlyOwner {
        generalPause = !generalPause;

        emit TogglePauseUpdate();
    }

    /**
        * @dev Toggle pool pause
        * @param _poolIndex Index of pool
     */
    function togglePoolPause(
        uint256 _poolIndex
    )
        external
        onlyOwner
    {
        require(_poolIndex < rewardPools.length, "Staking: _poolIndex must be less than rewardPools length");

        rewardPools[_poolIndex].enable = !rewardPools[_poolIndex].enable;

        emit ChangePoolStatus(
            _poolIndex,
            rewardPools[_poolIndex].enable
        );
    }

    /**
        * @dev Change fees
        * @param _entryFee Entry fee
        * @param _exitFee Exit fee
        * @param _threshold Threshold
     */
    function changeFees(
        uint256 _entryFee,
        uint256 _exitFee,
        uint256 _threshold
    )
    external
    onlyOwner {
        require(_entryFee >= 0 && _entryFee <= 100, "Staking: entryFee must be between 0 and 100");
        require(_exitFee >= 0 && _exitFee <= 100, "Staking: exitFee must be between 0 and 100");
        require(_threshold > 0, "Staking: threshold must be greater than 0");

        entryFee = _entryFee;
        exitFee = _exitFee;
        threshold = _threshold;

        emit ChangeFees(
            _entryFee,
            _exitFee,
            _threshold
        );
    }

    /**
        * @dev Add fee allocation
        * @param _feeAllocation Fee allocation amount
        * @param _feeReceiver Fee receiver address
     */
    function addFeeAllocation(
        uint256 _feeAllocation,
        address _feeReceiver
    )
        external
        onlyOwner 
    {
        require(_feeAllocation > 0 && _feeAllocation <= 100, "Staking: feeAllocation must be between 0 and 100");
        require(_validAddress(_feeReceiver), "Staking: feeReceiver must be valid address");

        feeAllocations.push(_feeAllocation);
        feeReceivers.push(_feeReceiver);

        emit AddFeeAllocation(
            _feeAllocation,
            _feeReceiver
        );
    }

    /**
        * @dev Remove fee allocation
        * @param _index Index of fee allocation
     */
    function removeFeeAllocation(
        uint256 _index
    )
        external
        onlyOwner 
    {
        require(_index < feeAllocations.length, "Staking: index must be less than feeAllocations length");

        feeAllocations[_index] = feeAllocations[feeAllocations.length - 1];
        feeAllocations.pop();

        feeReceivers[_index] = feeReceivers[feeReceivers.length - 1];
        feeReceivers.pop();

        emit RemoveFeeAllocation(
            _index
        );
    }

    /**
        * @dev Change router and factory
        * @param _router Router address
        * @param _factory Factory address
     */
    function changeRouterAndFactory(
        address _router,
        address _factory
    )
        external
        onlyOwner 
    {
        require(_validAddress(_router), "Staking: router must be valid address");
        require(_validAddress(_factory), "Staking: factory must be valid address");

        router = _router;
        factory = _factory;

        emit ChangeRouterAndFactory(
            _router,
            _factory
        );
    }

    /**
        * @dev Change wbnb and busd
        * @param _wbnb WBNB address
        * @param _busd BUSD address
     */
    function changeWBNBandBUSD(
        address _wbnb,
        address _busd
    )
        external
        onlyOwner 
    {
        require(_validAddress(_wbnb), "Staking: wbnb must be valid address");
        require(_validAddress(_busd), "Staking: busd must be valid address");

        wbnb = _wbnb;
        busd = _busd;

        emit ChangeWbnbAndBusd(
            _wbnb,
            _busd
        );
    }

    /**
        * @dev Change staking token
        * @param _stakingToken Staking token address
     */
    function changeStakingToken(
        address _stakingToken
    )
        external
        onlyOwner 
    {
        require(_validAddress(_stakingToken), "Staking: stakingToken must be valid address");

        stakingToken = IToken(_stakingToken);

        emit ChangeStakingToken(
            _stakingToken
        );
    }

    /**
        * @dev Stake
        * @param amount Amount to stake
     */
    function stake(uint256 amount) external nonReentrant() {
        require(
            stakingToken.transferFrom(
                msg.sender,
                address(this),
                amount
            ),
            "Staking: transferFrom failed"
        );
    
        if(users[msg.sender].totalStaked == 0) {
            totalUniqueStakers++;
        }

        users[msg.sender].totalStaked += amount;
        totalStakedInPool += amount;

        uint256 _fee = amount * entryFee / 100;
        totalCollectedFees += _fee;

        _redistributeFees();

        emit Stake(
            msg.sender,
            amount
        );
    }

    /**
        * @dev Unstake
        * @param amount Amount to unstake
     */
    function unstake(uint256 amount) external nonReentrant() {
        require(generalPause == false, "Staking: generalPause must be false");
        require(users[msg.sender].totalStaked >= amount, "Staking: amount must be less than totalStaked");

        users[msg.sender].totalStaked -= amount;
        totalStakedInPool -= amount;

        uint256 _fee = amount * exitFee / 100;
        totalCollectedFees += _fee;

        _redistributeFees();

        require(
            stakingToken.transfer(
                msg.sender,
                amount - _fee
            ),
            "Staking: transfer failed"
        );

        emit Unstake(
            msg.sender,
            amount
        );
    }

    /** Public functions */

    /**
        * @dev Claim rewards
        * @param _poolIndex Index of pool from which to claim rewards
     */
    function claimRewards(
        uint256 _poolIndex
    )
        public
    {
        require(generalPause == false, "Staking: generalPause must be false");

        require(_poolIndex < rewardPools.length, "Staking: _poolIndex must be less than rewardPools length");

        RewardPool memory _pool = rewardPools[_poolIndex];
        User storage _user = users[msg.sender];

        require(_user.totalStaked > 0, "Staking: totalStaked must be greater than 0");
        
        if(_pool.enable == false) {
            return;
        }

        if(_user.lastClaimInPool[_poolIndex] + 1 days > block.timestamp) {
            return;
        }

        _user.lastClaimInPool[_poolIndex] = block.timestamp;

        (
            uint256 _toReceive,
            uint256 _claimedDays
        ) = computePendingRewards(msg.sender, _poolIndex);

        if(_toReceive == 0) {
            return;
        }

        if(_user.claimedDaysInPool[_poolIndex] + _claimedDays > _pool.duration) {
            return;
        }

        require(
            stakingToken.transfer(
                msg.sender,
                _toReceive
            ),
            "Staking: transfer failed"
        );
    }

    /**
        * @dev Claim all rewards
     */
    function claimAll() public {
        require(generalPause == false, "Staking: generalPause must be false");

        for(uint256 i = 0; i < rewardPools.length; i++) {
            if(rewardPools[i].enable) {
                claimRewards(i);
            }
        }
    }

    /**
        * @dev Compound rewards
        * @param _poolIndex Index of pool from which to compound rewards
     */
    function compoundRewards(
        uint256 _poolIndex
    )
        public
    {
        require(generalPause == false, "Staking: generalPause must be false");
        require(_poolIndex < rewardPools.length, "Staking: _poolIndex must be less than rewardPools length");

        RewardPool memory _pool = rewardPools[_poolIndex];
        User storage _user = users[msg.sender];

        require(_user.totalStaked > 0, "Staking: totalStaked must be greater than 0");

        if(_pool.tokenHaveLiquditity == false) {
            return;
        }

        if(_user.claimedDaysInPool[_poolIndex] == _pool.duration) {
            return;
        }

        if(_pool.enable == false) {
            return;
        }

        if(_user.lastClaimInPool[_poolIndex] + 1 days > block.timestamp) {
            return;
        }

        address _middleToken = _checkLiquidity(_pool.token);
        address _liqMainToken = _checkLiquidity(address(stakingToken));

        if(_middleToken == zeroAddress && _liqMainToken == zeroAddress) {
            return;
        }

        (
            uint256 _toReceive,
            uint256 _claimedDays
        ) = computePendingRewards(msg.sender, _poolIndex);

        if(_toReceive == 0) {
            return;
        }

        if(_user.claimedDaysInPool[_poolIndex] + _claimedDays > _pool.duration) {
            return;
        }

        _user.rewardsClaimedInPool[_poolIndex] += _toReceive / 10_000;
        _user.lastClaimInPool[_poolIndex] = block.timestamp;
        _user.claimedDaysInPool[_poolIndex] += _claimedDays;

        uint256 _toAdd = _swapTokenForStakingToken(_pool.token, _middleToken, _liqMainToken, msg.sender, _toReceive / 10_000);
    
        _user.totalStaked += _toAdd;
    }

    /**
        * @dev Compound all rewards
     */
    function compoundAll() public {
        require(generalPause == false, "Staking: generalPause must be false");

        for(uint256 i = 0; i < rewardPools.length; i++) {
            if(rewardPools[i].enable) {
                compoundRewards(i);
            }
        }
    }

    /**
        * @dev Get number of packages
     */
    function getNoOfPackages() public view returns (uint256) {
        return rewardPools.length;
    }

    /**
        * @dev Get ids of active packages
     */
    function getIdsOfActivePackages() public view returns (uint256[] memory) {
        uint256[] memory _ids = new uint256[](rewardPools.length);
        uint256 _counter = 0;

        for(uint256 i = 0; i < rewardPools.length; i++) {
            if(rewardPools[i].enable) {
                _ids[_counter] = i;
                _counter++;
            }
        }

        uint256[] memory _activeIds = new uint256[](_counter);

        for(uint256 i = 0; i < _counter; i++) {
            _activeIds[i] = _ids[i];
        }

        return _activeIds;
    }

    /**
        * @dev Get fees for stake and unstake
     */
    function getFees() public view returns (uint256, uint256) {
        return (entryFee, exitFee);
    }

    /**
        * @dev Get general share of user
     */
    function getGeneralShare(address _user) public view returns (uint256) {
        return _sharOfUser(_user);
    }

    /**
        * @dev Get staked amount by user
     */
    function getStakedByUser(address _user) public view returns (uint256) {
        return users[_user].totalStaked;
    }

    /**
        * @dev Can claim from pool or not
     */
    function getPoolHaveLiquditiy(address _token) public view returns (bool) {
        return rewardPools[tokenToIndex[_token]].tokenHaveLiquditity;
    }

    /**
        * @dev Get user details for pool
     */
    function getUserDetailsForPool(address _user, uint256 _poolIndex) public view returns (uint256, uint256, uint256) {
        return (
            users[_user].rewardsClaimedInPool[_poolIndex],
            users[_user].lastClaimInPool[_poolIndex],
            users[_user].claimedDaysInPool[_poolIndex]
        );
    }

    /**
        * @dev Get pool details
     */
    function getPoolDetails(uint256 _poolIndex) public view 
    returns (
        uint256, 
        uint256, 
        uint256, 
        uint256, 
        uint256,
        address,
        bool, 
        bool) 
        {
            RewardPool memory _pool = rewardPools[_poolIndex];

            return (
                _pool.startDate,
                _pool.endDate,
                _pool.duration,
                _pool.totalClaimedRewards,
                _pool.totalAllocatedRewards,
                _pool.token,
                _pool.enable,
                _pool.tokenHaveLiquditity
            );
    }

    /**
        * @dev Get pending rewards for user in pool
     */
    function computePendingRewards(
        address _user,
        uint256 _poolIndex
    ) 
        public
        view
        returns (uint256, uint256)
    {
        uint256 _share = _sharOfUser(_user);

        if (_share == 0) {
            return (0, 0);
        }

        RewardPool memory _pool = rewardPools[_poolIndex];
        User storage _userStorage = users[_user];

        uint256 _totalRewardsToReceive = _pool.totalAllocatedRewards * _share / 100;
        uint256 _rewardsToReceivePerDay = _totalRewardsToReceive / _pool.duration;

        if(_rewardsToReceivePerDay == 0) {
            return (0, 0);
        }

        // Case 1: Pool ended
        if (block.timestamp > _pool.endDate) {
            uint256 _claimedRewards = _userStorage.rewardsClaimedInPool[_poolIndex];
            // Pool duration - claimed days
            uint256 _daysSinceLastClaim = _pool.duration - _userStorage.claimedDaysInPool[_poolIndex];
            return (_totalRewardsToReceive / 10_000 - _claimedRewards, _daysSinceLastClaim);
        }

        // Case 2: Pool not ended
        if(block.timestamp <= _pool.endDate) {
            // Days since last claim until now
            uint256 _daysSinceLastClaim = (block.timestamp - _userStorage.lastClaimInPool[_poolIndex]) / 1 days;
            return (_rewardsToReceivePerDay * _daysSinceLastClaim / 10_000, _daysSinceLastClaim);
        }

        return (0, 0);
    }

    /** Internal functions */
    function _sharOfUser(address _user) internal view returns (uint256) {
        return users[_user].totalStaked * 100 * 10_000 / totalStakedInPool;
    }

    function _validAddress(address _address) internal view returns (bool) {
        return _address != zeroAddress && _address != deadAddress;
    }

    function _checkLiquidity(address _token) internal view returns (address) {
        address _pairWithWbnb = IFactory(factory).getPair(_token, wbnb);
        if (_pairWithWbnb != address(0)) {
            return _pairWithWbnb;
        }

        address _pairWithBusd = IFactory(factory).getPair(_token, busd);
        if (_pairWithBusd != address(0)) {
            return _pairWithBusd;
        }

        return address(0);
    }

    function _redistributeFees() internal {
        if(
            totalCollectedFees == 0 ||
            totalCollectedFees <= threshold ||
            feeAllocations.length == 0   
        ) {
            return;
        }

        uint256 _totalCollectedFees = totalCollectedFees;
        totalCollectedFees = 0;

        for(uint256 i = 0; i < feeAllocations.length; i++) {
            uint256 _fee = _totalCollectedFees * feeAllocations[i] / 100;

            if(_fee == 0) {
                continue;
            }

            if(feeReceivers[i] == zeroAddress) {
                continue;
            }

            if(feeReceivers[i] == address(this)){
                _increaseRewardsInPool(_fee);
                continue;
            }

            require(
                stakingToken.transfer(
                    feeReceivers[i],
                    _fee
                ),
                "Staking: transfer failed"
            );
        }

        emit RedistributeFees(
            _totalCollectedFees
        );
    }

    function _increaseRewardsInPool(uint256 _amount) internal {
        if(mainPoolExist) {
            rewardPools[idMainPool].totalAllocatedRewards += _amount;

            emit IncreaseRewardsInPool(
                _amount
            );
        } else {
            return;
        }
    }

    function _swapTokenForStakingToken(
        address _token,
        address _middleToken,
        address _liqMainToken,
        address _receiver,
        uint256 _amount
    )
        internal
        returns(uint256)
    {
        address[] memory _path;

        if(_middleToken == _liqMainToken) {
            _path = new address[](2);
            _path[0] = _token;
            _path[1] = address(stakingToken);
        } else {
            _path = new address[](4);
            _path[0] = _token;
            _path[1] = _middleToken;
            _path[2] = _liqMainToken;
            _path[3] = address(stakingToken);
        }


        IToken(_token).approve(router, _amount);

        uint256 _balanceBefore = stakingToken.balanceOf(address(this));

        IRouter(router).swapExactTokensForTokensSupportingFeeOnTransferTokens(
            _amount,
            0,
            _path,
            _receiver,
            block.timestamp + 360
        );

        uint256 _balanceAfter = stakingToken.balanceOf(address(this));

        return _balanceAfter - _balanceBefore;
    }
}
