# @version >=0.2.4 <0.3.0

# IERC20 Interface
from vyper.interfaces import ERC20

# Total staked
totalStaked: public(uint256)

# Fee for emergency withdraw
emergencyFee: public(uint256)

# Rewards per day
rewardsPerDay: public(uint256)

# Token to stake
tokenToStake: public(ERC20)

# Token for rewards
rewardToken: public(ERC20)

# Owner
owner: public(address)

# Contracts is paused
isPaused: public(bool)

# Staked by user
stakedByUser: public(HashMap[address, uint256])

# Stake date
stakeDate: public(HashMap[address, uint256])

# Events
event Stake:
    user: indexed(address)
    amount: uint256

event UnstakeAndClaim:
    user: indexed(address)
    amount: uint256
    rewards: uint256

event EmergencyWithdraw:
    user: indexed(address)
    amount: uint256

# Function to compute pending rewards based on elapsed days
@internal
@view
def _computePendingRewards(_user: address) -> uint256:
    elapsedDays: uint256 = (block.timestamp - self.stakeDate[_user]) / 86400
    return elapsedDays * self.rewardsPerDay * self.stakedByUser[_user]

# Constructor
@external
def __init__(_emergencyFee: uint256, _rewardsPerDay: uint256, _tokenToStake: ERC20, _rewardToken: ERC20):
    self.emergencyFee = _emergencyFee
    self.tokenToStake = _tokenToStake
    self.rewardToken = _rewardToken
    self.rewardsPerDay = _rewardsPerDay

    self.isPaused = False

# Function to stake tokens 
@external
def stakeToken(_amount: uint256):
    assert _amount > 0, 'Cannot stake 0 tokens'
    assert not self.isPaused, 'Cannot stake while paused'

    self.tokenToStake.transferFrom(msg.sender, self, _amount)

    self.totalStaked += _amount
    self.stakedByUser[msg.sender] += _amount

    self.stakeDate[msg.sender] = block.timestamp

    log Stake(msg.sender, _amount)

# Function to emergency withdraw tokens
@external
@payable
def emergencyWithdraw(_amount: uint256):
    assert _amount > 0, 'Cannot withdraw 0 tokens'
    assert self.stakedByUser[msg.sender] >= _amount, 'Cannot withdraw more than staked'

    # Charge emergency fee in ethereum
    if self.emergencyFee > 0:
        assert msg.value >= self.emergencyFee, 'Incorrect emergency fee'

    self.tokenToStake.transfer(msg.sender, _amount)
    self.totalStaked -= _amount
    self.stakedByUser[msg.sender] -= _amount

    log EmergencyWithdraw(msg.sender, _amount)

# Function to withdraw tokens and pending rewards
@external
def withdrawTokensAndRewards():
    assert self.stakedByUser[msg.sender] > 0, 'Cannot withdraw 0 tokens'
    assert not self.isPaused, 'Cannot withdraw while paused'

    pendingRewards: uint256 = self._computePendingRewards(msg.sender)
    self.rewardToken.transfer(msg.sender, pendingRewards)

    self.tokenToStake.transfer(msg.sender, self.stakedByUser[msg.sender])
    self.totalStaked -= self.stakedByUser[msg.sender]

    _stakedByUser: uint256 = self.stakedByUser[msg.sender]
    self.stakedByUser[msg.sender] = 0

    log UnstakeAndClaim(msg.sender, _stakedByUser, pendingRewards)

# Function to pause/unpause the smart contract - only owner
@external
def pauseUnpause():
    assert msg.sender == self.owner, 'Only owner can pause/unpause'
    self.isPaused = not self.isPaused

# Function to renounce ownership - only owner
@external
def renounceOwnership():
    assert msg.sender == self.owner, 'Only owner can renounce ownership'
    self.owner = ZERO_ADDRESS

# Function to transfer ownership - only owner
@external
def transferOwnership(_newOwner: address):
    assert msg.sender == self.owner, 'Only owner can transfer ownership'
    self.owner = _newOwner

# Function to withdraw ERC20 tokens - only owner
@external
def withdrawERC20(_token: address, _amount: uint256):
    assert msg.sender == self.owner, 'Only owner can withdraw ERC20 tokens'

    dif: uint256 = ERC20(_token).balanceOf(self) - self.totalStaked
    assert _amount <= dif, 'Cannot withdraw stakers tokens'

    ERC20(_token).transfer(msg.sender, _amount)

# Function to change the staking token - only owner
@external
def changeStakingToken(_newToken: ERC20):
    assert msg.sender == self.owner, 'Only owner can change staking token'
    self.tokenToStake = _newToken

# Function to change the reward token - only owner
@external
def changeRewardToken(_newToken: ERC20):
    assert msg.sender == self.owner, 'Only owner can change reward token'
    self.rewardToken = _newToken

# Function to change the emergency fee - only owner
@external
def changeEmergencyFee(_newFee: uint256):
    assert msg.sender == self.owner, 'Only owner can change emergency fee'
    self.emergencyFee = _newFee

# Function to withdraw ether - only owner
@external
def withdrawEther():
    assert msg.sender == self.owner, 'Only owner can withdraw ether'

    _amount: uint256 = self.balance
    # send(self.owner, _amount) - not recommended, use raw_call
    raw_call(self.owner, b"", value=_amount)