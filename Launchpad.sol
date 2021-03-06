// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.0;

import "hardhat/console.sol";

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/interfaces/IERC20Upgradeable.sol";
import "./IStaking.sol";

contract LaunchpadV2 is OwnableUpgradeable, ReentrancyGuardUpgradeable {
  using SafeERC20Upgradeable for IERC20Upgradeable;
  uint256 public constant PRECISION = 10000; // 1 mil

  address public lockStakingAddress;

  struct User {
    uint256 amount;
    uint256 firstTimeDeposit;
    uint256 claimedMark;
  }

  struct Pool {
    uint256 totalAmount;
    address depositToken;
    address releaseToken;
    uint256 releaseAmount;
    uint256 releaseRate; // rate busd => token * Precision
    uint256 maxAmountUserCanBuy;
    uint256[] claimPercent;
    uint256 startTime;
    uint256 endTime;
    uint256 delayTime; // |----buyTime---|---delayTime----|-refundTime-lockingTime-------|
    uint256 refundTime;
    uint256 lockingTime;
    uint256 minBuyAmountPercent;
  }

  struct ExtraInfoPool {
    uint256 minBuyAmountPercent;
  }

  uint256 public nextPoolId;

  mapping(uint256 => Pool) public pools;
  mapping(uint256 => mapping(address => User)) public users; // poolId => address user
  mapping(uint256 => ExtraInfoPool) public extraInfoPool;

  event Buy(uint256 poolId, address indexed user, uint256 amount);
  event Claim(uint256 poolId, address indexed user, uint256 amount);
  event Refund(uint256 poolId, address indexed user, uint256 amount);

  function initialize() public initializer {
    __Ownable_init();
    __ReentrancyGuard_init_unchained();
  }

  function setLockStakingAddress(address _lockStakingAddress)
    external
    onlyOwner
  {
    lockStakingAddress = _lockStakingAddress;
  }

  function getAmountUserCanBuy(uint256 poolId) public view returns (uint256) {
    return pools[poolId].maxAmountUserCanBuy;
  }

  function getClaimPercent(uint256 poolId)
    external
    view
    returns (uint256[] memory)
  {
    return pools[poolId].claimPercent;
  }

  function getClaimToken(uint256 poolId, address account)
    public
    view
    returns (uint256)
  {
    Pool memory poolInfo = pools[poolId];
    User memory userInfo = users[poolId][account];

    uint256 claimMarks = (block.timestamp <
      poolInfo.endTime + poolInfo.delayTime)
      ? 0
      : ((block.timestamp - (poolInfo.endTime + poolInfo.delayTime)) /
        poolInfo.lockingTime) + 1;
    if (claimMarks == userInfo.claimedMark) return 0;

    if (claimMarks > poolInfo.claimPercent.length - 1)
      claimMarks = poolInfo.claimPercent.length - 1;

    uint256 claimedPercent;
    for (uint256 i = userInfo.claimedMark + 1; i <= claimMarks; i++)
      claimedPercent += poolInfo.claimPercent[i];
    return (userInfo.amount * claimedPercent) / PRECISION;
  }

  function addPool(
    address depositToken,
    address releaseToken,
    uint256 releaseAmount,
    uint256 releaseRate,
    uint256 maxAmountUserCanBuy,
    uint256 minBuyAmountPercent,
    uint256[] memory claimPercent,
    uint256 startTime,
    uint256 endTime,
    uint256 delayTime,
    uint256 refundTime,
    uint256 lockingTime
  ) external onlyOwner {
    pools[nextPoolId].depositToken = depositToken;
    pools[nextPoolId].releaseToken = releaseToken;
    pools[nextPoolId].releaseAmount = releaseAmount;
    pools[nextPoolId].releaseRate = releaseRate;
    pools[nextPoolId].maxAmountUserCanBuy = maxAmountUserCanBuy;
    pools[nextPoolId].startTime = startTime;
    pools[nextPoolId].endTime = startTime + endTime;
    pools[nextPoolId].delayTime = delayTime;
    pools[nextPoolId].lockingTime = lockingTime;
    pools[nextPoolId].refundTime = refundTime;
    pools[nextPoolId].claimPercent = claimPercent;

    extraInfoPool[nextPoolId].minBuyAmountPercent = minBuyAmountPercent;

    nextPoolId++;
  }

  function updatePool(
    uint256 poolId,
    address depositToken,
    address releaseToken,
    uint256 releaseAmount,
    uint256 releaseRate,
    uint256 maxAmountUserCanBuy,
    uint256[] memory claimPercent,
    uint256 startTime,
    uint256 endTime,
    uint256 delayTime,
    uint256 refundTime,
    uint256 lockingTime
  ) external onlyOwner {
    pools[poolId].depositToken = depositToken;
    pools[poolId].releaseToken = releaseToken;
    pools[poolId].releaseAmount = releaseAmount;
    pools[poolId].releaseRate = releaseRate;
    pools[poolId].maxAmountUserCanBuy = maxAmountUserCanBuy;
    pools[poolId].startTime = startTime;
    pools[poolId].endTime = startTime + endTime;
    pools[poolId].delayTime = delayTime;
    pools[poolId].lockingTime = lockingTime;
    pools[poolId].refundTime = refundTime;
    pools[poolId].claimPercent = claimPercent;
  }

  function updateReleaseToken(uint256 poolId, address releaseToken)
    external
    onlyOwner
  {
    pools[poolId].releaseToken = releaseToken;
  }

  function updateEndTime(uint256 poolId, uint256 endTime) external onlyOwner {
    pools[poolId].endTime = pools[poolId].startTime + endTime;
  }

  function updateMaxAmountUserCanBuy(
    uint256 poolId,
    uint256 maxAmountUserCanBuy
  ) external onlyOwner {
    pools[poolId].maxAmountUserCanBuy = maxAmountUserCanBuy;
  }

  function updateMinBuyAmountPercent(
    uint256 poolId,
    uint256 minBuyAmountPercent
  ) external onlyOwner {
    extraInfoPool[poolId].minBuyAmountPercent = minBuyAmountPercent;
  }

  function updateClaimPercent(uint256 poolId, uint256[] memory claimPercent)
    external
    onlyOwner
  {
    pools[poolId].claimPercent = claimPercent;
  }

  function updateDelayTime(uint256 poolId, uint256 delayTime)
    external
    onlyOwner
  {
    pools[poolId].delayTime = delayTime;
  }

  function updateLockingTime(uint256 poolId, uint256 lockingTime)
    external
    onlyOwner
  {
    pools[poolId].lockingTime = lockingTime;
  }

  function updateReleaseAmount(uint256 poolId, uint256 releaseAmount)
    external
    onlyOwner
  {
    pools[poolId].releaseAmount = releaseAmount;
  }

  function updateRefundTime(uint256 poolId, uint256 refundTime)
    external
    onlyOwner
  {
    pools[poolId].refundTime = refundTime;
  }

  function buy(uint256 poolId, uint256 _amount) external nonReentrant {
    require(_amount > 0, "buy zero amount");
    require(nextPoolId > poolId, "not exist pool");
    Pool storage poolInfo = pools[poolId];
    require(
      block.timestamp > poolInfo.startTime &&
        block.timestamp < poolInfo.endTime,
      "End pool"
    );
    uint256 amountUserCanDeposit = getAmountUserCanBuy(poolId);
    uint256 minBuyAmount = (amountUserCanDeposit *
      extraInfoPool[poolId].minBuyAmountPercent) / 100;

    User storage userInfo = users[poolId][msg.sender];

    require(
      userInfo.amount + _amount <= amountUserCanDeposit,
      "exceed buy amount"
    );

    require(
      userInfo.amount + _amount >= minBuyAmount,
      "Not greater than min purchase amount"
    );

    require(
      poolInfo.totalAmount + _amount <= poolInfo.releaseAmount,
      "Sold out"
    );

    userInfo.amount += _amount;
    poolInfo.totalAmount += _amount;

    IERC20Upgradeable(poolInfo.depositToken).safeTransferFrom(
      msg.sender,
      address(this),
      (_amount * poolInfo.releaseRate) / PRECISION
    );

    emit Buy(poolId, msg.sender, _amount);
  }

  function claim(uint256 poolId) external nonReentrant {
    require(nextPoolId > poolId, "not exist pool");
    Pool memory poolInfo = pools[poolId];

    User storage userInfo = users[poolId][msg.sender];
    require(userInfo.amount > 0, "Not amount to withdraw");
    uint256 claimMarks = (block.timestamp <
      poolInfo.endTime + poolInfo.delayTime)
      ? 0
      : ((block.timestamp - (poolInfo.endTime + poolInfo.delayTime)) /
        poolInfo.lockingTime) + 1;

    if (claimMarks > poolInfo.claimPercent.length - 1)
      claimMarks = poolInfo.claimPercent.length - 1;

    require(
      userInfo.claimedMark < claimMarks,
      "you claimed reward or not in claim time"
    );

    uint256 claimedPercent;
    for (uint256 i = userInfo.claimedMark + 1; i <= claimMarks; i++)
      claimedPercent += poolInfo.claimPercent[i];
    uint256 claimedAmount = (userInfo.amount * claimedPercent) / PRECISION;
    userInfo.claimedMark = claimMarks;

    IERC20Upgradeable(poolInfo.releaseToken).safeTransfer(
      msg.sender,
      claimedAmount
    );

    emit Claim(poolId, msg.sender, claimedAmount);
  }

  function refund(uint256 poolId) external nonReentrant {
    User storage userInfo = users[poolId][msg.sender];
    require(userInfo.amount > 0, "not enough amount, can not refund");
    require(userInfo.claimedMark == 0, "claimed token");
    require(nextPoolId > poolId, "not exist pool");
    Pool storage poolInfo = pools[poolId];
    require(
      block.timestamp > poolInfo.endTime + poolInfo.delayTime &&
        block.timestamp <
        poolInfo.endTime + poolInfo.delayTime + poolInfo.refundTime,
      "Not in refund time"
    );

    uint256 amount = userInfo.amount;
    poolInfo.totalAmount -= userInfo.amount;
    userInfo.amount = 0;

    IERC20Upgradeable(poolInfo.depositToken).safeTransfer(
      msg.sender,
      (amount * poolInfo.releaseRate) / PRECISION
    );

    emit Refund(poolId, msg.sender, amount);
  }

  function marketing(
    address token,
    address marketingAddress,
    uint256 amount
  ) external onlyOwner {
    IERC20Upgradeable(token).safeTransfer(marketingAddress, amount);
  }
}
