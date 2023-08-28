// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

/**
 * @dev Interface of the ERC20 standard as defined in the EIP.
 */
interface IERC20 {
    /**
     * @dev Emitted when `value` tokens are moved from one account (`from`) to
     * another (`to`).
     *
     * Note that `value` may be zero.
     */
    event Transfer(address indexed from, address indexed to, uint256 value);

    /**
     * @dev Emitted when the allowance of a `spender` for an `owner` is set by
     * a call to {approve}. `value` is the new allowance.
     */
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );

    /**
     * @dev Returns the amount of tokens in existence.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns the amount of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @dev Moves `amount` tokens from the caller's account to `to`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(address to, uint256 amount) external returns (bool);

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     */
    function allowance(
        address owner,
        address spender
    ) external view returns (uint256);

    /**
     * @dev Sets `amount` as the allowance of `spender` over the caller's tokens.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * IMPORTANT: Beware that changing an allowance with this method brings the risk
     * that someone may use both the old and the new allowance by unfortunate
     * transaction ordering. One possible solution to mitigate this race
     * condition is to first reduce the spender's allowance to 0 and set the
     * desired value afterwards:
     * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
     *
     * Emits an {Approval} event.
     */
    function approve(address spender, uint256 amount) external returns (bool);

    /**
     * @dev Moves `amount` tokens from `from` to `to` using the
     * allowance mechanism. `amount` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool);
}

contract Stake {

    // Interest Rate - 20%
    uint private interestRate = 2000;
    uint private interestRateDecimalPlaces = 2;

    // Total Stakes Created
    uint private stakeCount;

    uint private minDurationToStake = 2 minutes;
    uint private minTokensToStake = 10 ** 9;

    // Stores Active Stakes Information
    struct StakeInfo {
        uint stakeId;
        uint startTS;
        uint endTS;
        uint amountAtStake;
        uint claimedAmount;
        address owner;
    }

    // Stake Id to Stake Information Mapping
    mapping(uint => StakeInfo) private stakeInfos;

    // Stores Paused Starting & Ending Timestamps
    uint[2][] private pausedHistory;

    // Stores Token Address
    address private tokenAddress;

    // Stores owner's address of this contract
    address private owner;

    mapping (address => uint[]) private userStakes;

    event Staked(address indexed from, uint indexed stakeId, uint amount, uint timestamp);

    event Claimed(address indexed from, uint indexed stakeId, uint amount, uint timestamp);
    
    event Unstaked(address indexed from, uint indexed stakeId, uint amount, uint timestamp);

    modifier onlyOwner() {
        require(msg.sender == owner, "Insufficient Access");
        _;
    }

    modifier isValidStakeId(uint _stakeId) {
        require(stakeInfos[_stakeId].stakeId == _stakeId && stakeInfos[_stakeId].owner != address(0), "Invalid stakeId");
        _;
    }

    modifier isRedeemable(uint _stakeId, uint _amount) {
        require(stakeInfos[_stakeId].owner == msg.sender, "You are not the owner of this stake");

        uint ROI = checkROI(_stakeId);
        require(ROI >= _amount, "Insufficient Amount to Claim");
        _;
    }

    modifier canUnstake(uint _stakeId) {
        require(stakeInfos[_stakeId].owner == msg.sender, "You are not the owner of this stake");
        require(stakeInfos[_stakeId].endTS < block.timestamp, "Stake Time is not over yet");
        _;
    }

    modifier isValidMonth(uint _month) {
        require(_month >= 1 && _month <= 12, "Month value should be from 1 to 12");
        _;
    }

    constructor(address _tokenAddress) {
        require(address(_tokenAddress) != address(0), "Token Address cannot be address 0");
        tokenAddress = _tokenAddress;
        owner = msg.sender;
    }

    function stakeToken(uint256 _stakeAmount, uint256 _duration) external  {

        require(_stakeAmount > 0, "Stake amount should not be 0");

        require(_stakeAmount >= minTokensToStake, "Stake Amount should be more than Minimum Tokens to Stake");

        require(_duration >= minDurationToStake, "Stake Duration should be more than Minimum Duration to Stake");

        require(IERC20(tokenAddress).balanceOf(msg.sender) >= _stakeAmount, "Insufficient Balance");

        require(IERC20(tokenAddress).allowance(msg.sender, address(this)) >= _stakeAmount, "Insufficient Allowance");

        IERC20(tokenAddress).transferFrom(msg.sender, address(this), _stakeAmount);

        stakeCount++;

        // Create a stake
        stakeInfos[stakeCount] = StakeInfo({
            stakeId: stakeCount,
            startTS: block.timestamp,
            endTS: block.timestamp + _duration,
            amountAtStake: _stakeAmount,
            claimedAmount: 0,
            owner: msg.sender
        });

        userStakes[msg.sender].push(stakeCount);

        emit Staked(msg.sender, stakeCount, _stakeAmount, block.timestamp);
    }

    function redeemROI(uint _stakeId) external isValidStakeId(_stakeId) {
        
        uint amount = checkROI(_stakeId);

        IERC20(tokenAddress).transfer(msg.sender, amount);
        stakeInfos[_stakeId].claimedAmount += amount;

        emit Claimed(msg.sender, _stakeId, amount, block.timestamp);

    }

    function unstake(uint _stakeId) external isValidStakeId(_stakeId) canUnstake(_stakeId) {

        StakeInfo storage stakeInfo = stakeInfos[_stakeId];

        uint tokensToUnstake = checkROI(_stakeId) + stakeInfo.amountAtStake;

        IERC20(tokenAddress).transfer(msg.sender, tokensToUnstake);

        stakeInfo.claimedAmount += tokensToUnstake;

        uint len = userStakes[msg.sender].length;
        for (uint i = 0; i < len; i++) {
            if (userStakes[msg.sender][i] == _stakeId) {
                userStakes[msg.sender][i] = userStakes[msg.sender][len - 1];
                userStakes[msg.sender].pop();
                break;
            }
        }

        emit Unstaked(msg.sender, _stakeId, tokensToUnstake, block.timestamp);

        delete stakeInfos[_stakeId];
    }

    function checkROI(uint _stakeId) public view isValidStakeId(_stakeId) returns (uint) {
        StakeInfo memory stakeInfo = stakeInfos[_stakeId];

        uint calculatePausedDuration = _getPausedDuration(_stakeId);
        // console.log("calculatePausedDuration: %s", calculatePausedDuration);

        uint ROI = ((stakeInfo.amountAtStake * interestRate) /
            (10 ** (interestRateDecimalPlaces + 2)));
        // console.log("ROI: %s", ROI);

        uint presentDuration = (block.timestamp - stakeInfo.startTS);
        // console.log("presentDuration: %s", presentDuration);

        return
            ((ROI * (presentDuration - calculatePausedDuration)) /
                (stakeInfo.endTS - stakeInfo.startTS)) -
            stakeInfo.claimedAmount;
    }

    function totalROI(uint _stakeId) external view isValidStakeId(_stakeId) returns (uint) {
        return checkROI(_stakeId) + stakeInfos[_stakeId].claimedAmount;
    }

    function setInterestRate(uint _interestRate, uint _interestRateDecimalPlaces) external onlyOwner {
        interestRate = _interestRate;
        interestRateDecimalPlaces = _interestRateDecimalPlaces;
    }

    function getInterestRate() external view returns (uint _interestRate, uint _interestRateDecimalPlaces) {
        return (interestRate, interestRateDecimalPlaces);
    }

    function _getPausedDuration(uint stakeId) internal view returns (uint) {
        if (pausedHistory.length == 0) return 0;

        StakeInfo memory stakeInfo = stakeInfos[stakeId];
        uint pausedDuration;

        for (uint i = pausedHistory.length - 1; i >= 0; i--) {
            if (pausedHistory[i][1] != 0 && pausedHistory[i][1] <= stakeInfo.startTS) {
                break;
            }

            uint pauseStartTS;
            uint pauseEndTS;

            pauseStartTS = pausedHistory[i][0] >= stakeInfo.startTS
                ? pausedHistory[i][0]
                : stakeInfo.startTS;

            pauseEndTS = pausedHistory[i][1] == 0
                ? block.timestamp
                : pausedHistory[i][1];

            pausedDuration += (pauseEndTS - pauseStartTS);

            if (i == 0) break;
        }
        return pausedDuration;
    }

    function getActiveStakes(address _address) public view returns (uint[] memory) {
        return userStakes[_address];
    }

    function getStakeInfo(uint _stakeId) external view isValidStakeId(_stakeId) 
        returns (uint stakeId, uint _startTS, uint _endTS, uint _amountAtStake, uint _claimedAmount, address _owner) {

        return (stakeInfos[_stakeId].stakeId, stakeInfos[_stakeId].startTS, stakeInfos[_stakeId].endTS, 
                stakeInfos[_stakeId].amountAtStake, stakeInfos[_stakeId].claimedAmount, stakeInfos[_stakeId].owner);

    }

    function pause() external onlyOwner {
        pausedHistory.push([block.timestamp, 0]);
    }

    function unpause() external onlyOwner {
        pausedHistory[pausedHistory.length - 1][1] = block.timestamp;
    }

    function setMinDurationToStake(uint _planDuration) external onlyOwner {
        require(_planDuration >= 1 minutes, "Plan Duration too low");
        minDurationToStake = _planDuration;
    }

    function getMinDurationToStake() external view returns (uint) {
        return minDurationToStake;
    }

    function setMinTokensToStake(uint _amount) external onlyOwner {
        require(_amount > 0, "Minimum Amount should be greater than 0");
        minTokensToStake = _amount;
    }

    function getMinTokensToStake() external view returns (uint) {
        return minTokensToStake;
    }

    function setTokenAddress(address _tokenAddress) external onlyOwner {
        tokenAddress = _tokenAddress;
    }

    function getTokenAddress() external view returns(address) {
        return tokenAddress;
    }

    function setOwner(address _owner) external onlyOwner {
        owner = _owner;
    }

    function getOwner() external view returns (address) {
        return owner;
    }

}