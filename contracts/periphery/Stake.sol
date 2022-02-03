// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "./library/TransferHelper.sol";

contract Stake is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable{
    
    address public stakeToken;
    address public rewardsToken;
    uint public rewardsPerSecond;
    uint public BONUS_MULTIPLIER;
    uint public startTime;
    uint public endTime;
    uint public stakeTokenTotal;
    uint public accRewardsPerShare;
    uint public lastRewardBlockTimestamp;
    mapping(address => uint) public userStakeTime;
    mapping(address => uint) public stakeBalance;
    mapping(address => uint) public rewardDebt;
    

    event Stake(address staker, uint256 amount);
    event Reward(address staker, uint256 amount);
    event Withdraw(address staker, uint256 amount, uint256 remainingAmount);
    event ClaimReward(address indexed user, uint256 veeReward);
    event DisrubuteRewards(address staker, uint256 interestAccumulated);
    event NewVoteToken(address newVoteToken, address oldVoteToken);
    event NewRewardsPerSecond(uint newRewardsPerSecond, uint oldRewardsPerSecond);
    event NewMultiplier(uint newMultiplier, uint oldMultiplier);

    function initialize(address _stakeToken, address _rewardsToken, uint _startTime, uint _endTime) public initializer{
        __Ownable_init();
        __ReentrancyGuard_init();
        stakeToken = _stakeToken;
        rewardsToken = _rewardsToken;
        startTime = _startTime;
        endTime = _endTime;
        BONUS_MULTIPLIER = 1;
    }

    function updateMultiplier(uint multiplierNumber) public onlyOwner {
        emit NewMultiplier(multiplierNumber, BONUS_MULTIPLIER);
        BONUS_MULTIPLIER = multiplierNumber;
    }

    function setRewardsPerSecond(uint _rewardsPerSecond) external onlyOwner {
        emit NewRewardsPerSecond(_rewardsPerSecond, rewardsPerSecond);
        rewardsPerSecond = _rewardsPerSecond;
        
    }

    function getMultiplier(uint _from, uint _to) internal view returns (uint) {
        if (_to <= endTime) {
            return (_to - _from) * BONUS_MULTIPLIER;
        } else if (_from >= endTime) {
            return 0;
        } else {
            return (endTime - _from) * BONUS_MULTIPLIER;
        }
    }

    function updatePool() internal {
        if (getBlockTimestamp() <= lastRewardBlockTimestamp) {
            return;
        }
        if (stakeTokenTotal == 0) {
            lastRewardBlockTimestamp = getBlockTimestamp();
            return;
        } 
        uint multiplier = getMultiplier(lastRewardBlockTimestamp, getBlockTimestamp());
        uint veeReward = multiplier * rewardsPerSecond;
        accRewardsPerShare = accRewardsPerShare + veeReward * 1e12 / stakeTokenTotal;
        lastRewardBlockTimestamp = getBlockTimestamp();
    }

    function stake(uint amount) external {
        require(amount > 0, "amount error");
        updatePool();
        TransferHelper.safeTransferFrom(stakeToken, msg.sender, address(this), amount);
        userStakeTime[msg.sender] = getBlockTimestamp();
        stakeBalance[msg.sender] += amount;
        stakeTokenTotal += amount;
        emit Stake(msg.sender, amount);
    }

    function withdraw(uint amount) external {
        require(stakeBalance[msg.sender] >= amount, "insufficient balance");
        updatePool();
        if (stakeBalance[msg.sender] > 0) {
            uint256 reward = _estimateRewards(msg.sender);
            safeRewardsTransfer(msg.sender, reward);
            emit ClaimReward(msg.sender, reward);
        }
        rewardDebt[msg.sender] = stakeBalance[msg.sender] * accRewardsPerShare / 1e12;
        stakeBalance[msg.sender] -= amount;
        stakeTokenTotal -=amount;
        TransferHelper.safeTransfer(stakeToken, msg.sender, amount);
        emit Withdraw(msg.sender, amount, stakeBalance[msg.sender]);
    }

    function estimateRewards(address account) external view returns (uint) {
        return _estimateRewards(account);
    }

    function _estimateRewards(address account) internal view returns (uint) {
        return stakeBalance[account] * accRewardsPerShare / 1e12 - rewardDebt[account];
    }

    function claimReward(address _account) external nonReentrant {
        updatePool();
        if (stakeBalance[_account] > 0) {
            uint256 reward = _estimateRewards(_account);
            safeRewardsTransfer(_account, reward);
            rewardDebt[_account] = stakeBalance[_account] * accRewardsPerShare / 1e12;
            emit ClaimReward(_account, reward);
        }
    }

    function getBlockTimestamp() internal view returns (uint) {
        // solhint-disable-next-line not-rely-on-time
        return block.timestamp;
    }

    function safeRewardsTransfer(address to, uint amount) internal {
        TransferHelper.safeTransfer(rewardsToken, to, amount);
    }
}