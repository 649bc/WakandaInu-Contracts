// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

import "@openzeppelin/access/Ownable.sol";
import "../helpers/SafeBEP20.sol";
import "@openzeppelin/utils/Pausable.sol";

contract WakandaInuPool is Ownable, Pausable {
    using SafeERC20 for IERC20;

    struct UserInfo {
        uint256 shares; // number of shares for a user.
        uint256 lastDepositedTime; // keep track of deposited time for potential penalty.
        uint256 wkdAtLastUserAction; // keep track of wakandaInu deposited at the last user action.
        uint256 lastUserActionTime; // keep track of the last user action time.
        uint256 lockStartTime; // lock start time.
        uint256 lockEndTime; // lock end time.
        bool locked; //lock status.
        uint256 lockedAmount; // amount deposited during lock period.
    }



    // constants
    IERC20 public immutable token; // wakandaInu token.
    mapping(address => UserInfo) public userInfo;
    mapping(address => bool) public freePerformanceFeeUsers; // free performance fee users.
    mapping(address => bool) public freeWithdrawFeeUsers; // free withdraw fee users.
    mapping(address => bool) public freeOverdueFeeUsers; // free overdue fee users.
    uint256 public totalShares;
    address public admin;
    address public operator;
    uint256 public wkdPoolPID;
     uint256 public totalLockedAmount; // total lock amount.
      uint256 public performanceFee = 200; // 2%
    uint256 public performanceFeeContract = 200; // 2%
    uint256 public withdrawFee = 10; // 0.1%
    uint256 public withdrawFeeContract = 10; // 0.1%
    uint256 public overdueFee = 100 * 1e10; // 100%
    uint256 public withdrawFeePeriod = 72 hours; // 3 days




event Deposit(address indexed sender, uint256 amount, uint256 shares, uint256 duration, uint256 lastDepositedTime);
    event Withdraw(address indexed sender, uint256 amount, uint256 shares);
    event Harvest(address indexed sender, uint256 amount);
    event Pause();
    event Unpause();
     event Lock(
        address indexed sender,
        uint256 lockedAmount,
        uint256 shares,
        uint256 lockedDuration,
        uint256 blockTimestamp
    );
    event Unlock(address indexed sender, uint256 amount, uint256 blockTimestamp);
    event NewAdmin(address admin);
    event NewOperator(address operator);
    event FreeFeeUser(address indexed user, bool indexed free);
    event NewPerformanceFee(uint256 performanceFee);
    event NewPerformanceFeeContract(uint256 performanceFeeContract);
    event NewWithdrawFee(uint256 withdrawFee);
    event NewOverdueFee(uint256 overdueFee);
    event NewWithdrawFeeContract(uint256 withdrawFeeContract);
    event NewWithdrawFeePeriod(uint256 withdrawFeePeriod);
    event NewMaxLockDuration(uint256 maxLockDuration);
    event NewDurationFactor(uint256 durationFactor);
    event NewDurationFactorOverdue(uint256 durationFactorOverdue);
    event NewUnlockFreeDuration(uint256 unlockFreeDuration);



 /**
     * @notice Constructor
     * @param _token: WKD token contract
     * @param _admin: address of the admin
    
     * @param _operator: address of operator
     */
    constructor(
        IERC20 _token,
        address _admin,
        address _operator
    ) {
        token = _token;
        admin = _admin;
        operator = _operator;
    }

  /**
     * @notice Checks if the msg.sender is the admin address.
     */
    modifier onlyAdmin() {
        require(msg.sender == admin, "admin: wut?");
        _;
    }

    /**
     * @notice Checks if the msg.sender is either the wkd owner address or the operator address.
     */
    modifier onlyOperatorOrWkdOwner(address _user) {
        require(msg.sender == _user || msg.sender == operator, "Not operator or wkd owner");
        _;
    }

function updateUserShare(address _user) internal {
        UserInfo storage user = userInfo[_user];
        if (user.shares > 0) {
            if (user.locked) {
                // Calculate the user's current token amount and update related parameters.
                uint256 currentAmount = (balanceOf() * (user.shares)) / totalShares;
                totalShares -= user.shares;
            
                // Recalculate the user's share.
                uint256 pool = balanceOf();
                uint256 currentShares;
                if (totalShares != 0) {
                    currentShares = (currentAmount * totalShares) / (pool - currentAmount);
                } else {
                    currentShares = currentAmount;
                }
                user.shares = currentShares;
                totalShares += currentShares;
                // After the lock duration, update related parameters.
                if (user.lockEndTime < block.timestamp) {
                    user.locked = false;
                    user.lockStartTime = 0;
                    user.lockEndTime = 0;
                    totalLockedAmount -= user.lockedAmount;
                    user.lockedAmount = 0;
                    emit Unlock(_user, currentAmount, block.timestamp);
                }
            } 
        }
    }


 /**
     * @notice Unlock user wkd funds.
     * @dev Only possible when contract not paused.
     * @param _user: User address
     */
    function unlock(address _user) external onlyOperatorOrWkdOwner(_user) whenNotPaused {
        UserInfo storage user = userInfo[_user];
        require(user.locked && user.lockEndTime < block.timestamp, "Cannot unlock yet");
        depositOperation(0, 0, _user);
    }



/**
     * @notice Deposit funds into the wkd Pool.
     * @dev Only possible when contract not paused.
     * @param _amount: number of tokens to deposit (in WKD)
     * @param _lockDuration: Token lock duration
     */
    function deposit(uint256 _amount, uint256 _lockDuration) external whenNotPaused {
        require(_amount > 0 || _lockDuration > 0, "Nothing to deposit");
        depositOperation(_amount, _lockDuration, msg.sender);
    }

    /**
     * @notice The operation of deposite.
     * @param _amount: number of tokens to deposit (in WKD)
     * @param _lockDuration: Token lock duration
     * @param _user: User address
     */
    function depositOperation(
        uint256 _amount,
        uint256 _lockDuration,
        address _user
    ) internal {
        UserInfo storage user = userInfo[_user];
        if (user.shares == 0 || _amount > 0) {
            require(_amount > MIN_DEPOSIT_AMOUNT, "Deposit amount must be greater than MIN_DEPOSIT_AMOUNT");
        }
        // Calculate the total lock duration and check whether the lock duration meets the conditions.
        uint256 totalLockDuration = _lockDuration;
        if (user.lockEndTime >= block.timestamp) {
            // Adding funds during the lock duration is equivalent to re-locking the position, needs to update some variables.
            if (_amount > 0) {
                user.lockStartTime = block.timestamp;
                totalLockedAmount -= user.lockedAmount;
                user.lockedAmount = 0;
            }
            totalLockDuration += user.lockEndTime - user.lockStartTime;
        }
        require(_lockDuration == 0 || totalLockDuration >= MIN_LOCK_DURATION, "Minimum lock period is one week");
        require(totalLockDuration <= MAX_LOCK_DURATION, "Maximum lock period exceeded");


        // Handle stock funds.
        if (totalShares == 0) {
            uint256 stockAmount = available();
            token.safeTransfer(treasury, stockAmount);
        }
        // Update user share.
        updateUserShare(_user);

        // Update lock duration.
        if (_lockDuration > 0) {
            if (user.lockEndTime < block.timestamp) {
                user.lockStartTime = block.timestamp;
                user.lockEndTime = block.timestamp + _lockDuration;
            } else {
                user.lockEndTime += _lockDuration;
            }
            user.locked = true;
        }

        uint256 currentShares;
        uint256 currentAmount;
        uint256 userCurrentLockedBalance;
        uint256 pool = balanceOf();
        if (_amount > 0) {
            token.safeTransferFrom(_user, address(this), _amount);
            currentAmount = _amount;
        }

        // Calculate lock funds
        if (user.shares > 0 && user.locked) {
            userCurrentLockedBalance = (pool * user.shares) / totalShares;
            currentAmount += userCurrentLockedBalance;
            totalShares -= user.shares;
            user.shares = 0;

            // Update lock amount
            if (user.lockStartTime == block.timestamp) {
                user.lockedAmount = userCurrentLockedBalance;
                totalLockedAmount += user.lockedAmount;
            }
        }
        if (totalShares != 0) {
            currentShares = (currentAmount * totalShares) / (pool - userCurrentLockedBalance);
        } else {
            currentShares = currentAmount;
        }


        if (_amount > 0 || _lockDuration > 0) {
            user.lastDepositedTime = block.timestamp;
        }
        totalShares += currentShares;

        user.wkdAtLastUserAction = (user.shares * balanceOf()) / totalShares;
        user.lastUserActionTime = block.timestamp;

        emit Deposit(_user, _amount, currentShares, _lockDuration, block.timestamp);
    }

/**
     * @notice Withdraw funds from the Wkd Pool.
     * @param _amount: Number of amount to withdraw
     */
    function withdrawByAmount(uint256 _amount) public whenNotPaused {
        require(_amount > MIN_WITHDRAW_AMOUNT, "Withdraw amount must be greater than MIN_WITHDRAW_AMOUNT");
        withdrawOperation(0, _amount);
    }

    /**
     * @notice Withdraw funds from the Wkd Pool.
     * @param _shares: Number of shares to withdraw
     */
    function withdraw(uint256 _shares) public whenNotPaused {
        require(_shares > 0, "Nothing to withdraw");
        withdrawOperation(_shares, 0);
    }

    /**
     * @notice The operation of withdraw.
     * @param _shares: Number of shares to withdraw
     * @param _amount: Number of amount to withdraw
     */
    function withdrawOperation(uint256 _shares, uint256 _amount) internal {
        UserInfo storage user = userInfo[msg.sender];
        require(_shares <= user.shares, "Withdraw amount exceeds balance");
        require(user.lockEndTime < block.timestamp, "Still in lock");
        // Calculate the percent of withdraw shares, when unlocking or calculating the Performance fee, the shares will be updated.
        uint256 currentShare = _shares;
        uint256 sharesPercent = (_shares * PRECISION_FACTOR_SHARE) / user.shares;

        
        // Update user share.
        updateUserShare(msg.sender);

        if (_shares == 0 && _amount > 0) {
            uint256 pool = balanceOf();
            currentShare = (_amount * totalShares) / pool; // Calculate equivalent shares
            if (currentShare > user.shares) {
                currentShare = user.shares;
            }
        } else {
            currentShare = (sharesPercent * user.shares) / PRECISION_FACTOR_SHARE;
        }
        uint256 currentAmount = (balanceOf() * currentShare) / totalShares;
        user.shares -= currentShare;
        totalShares -= currentShare;

        // Calculate withdraw fee
        if (!freeWithdrawFeeUsers[msg.sender] && (block.timestamp < user.lastDepositedTime + withdrawFeePeriod)) {
            uint256 feeRate = withdrawFee;
            if (_isContract(msg.sender)) {
                feeRate = withdrawFeeContract;
            }
            uint256 currentWithdrawFee = (currentAmount * feeRate) / 10000;
            token.safeTransfer(treasury, currentWithdrawFee);
            currentAmount -= currentWithdrawFee;
        }

        token.safeTransfer(msg.sender, currentAmount);

        if (user.shares > 0) {
            user.wkdAtLastUserAction = (user.shares * balanceOf()) / totalShares;
        } else {
            user.wkdAtLastUserAction = 0;
        }

        user.lastUserActionTime = block.timestamp;


        emit Withdraw(msg.sender, currentAmount, currentShare);
    }

    /**
     * @notice Withdraw all funds for a user
     */
    function withdrawAll() external {
        withdraw(userInfo[msg.sender].shares);
    }
    /**
     * @notice Set admin address
     * @dev Only callable by the contract owner.
     */
    function setAdmin(address _admin) external onlyOwner {
        require(_admin != address(0), "Cannot be zero address");
        admin = _admin;
        emit NewAdmin(admin);
    }

/**
     * @notice Set operator address
     * @dev Callable by the contract owner.
     */
    function setOperator(address _operator) external onlyOwner {
        require(_operator != address(0), "Cannot be zero address");
        operator = _operator;
        emit NewOperator(operator);
    }

     /**
     * @notice Set free performance fee address
     * @dev Only callable by the contract admin.
     * @param _user: User address
     * @param _free: true:free false:not free
     */
    function setFreePerformanceFeeUser(address _user, bool _free) external onlyAdmin {
        require(_user != address(0), "Cannot be zero address");
        freePerformanceFeeUsers[_user] = _free;
        emit FreeFeeUser(_user, _free);
    }

      /**
     * @notice Set free overdue fee address
     * @dev Only callable by the contract admin.
     * @param _user: User address
     * @param _free: true:free false:not free
     */
    function setOverdueFeeUser(address _user, bool _free) external onlyAdmin {
        require(_user != address(0), "Cannot be zero address");
        freeOverdueFeeUsers[_user] = _free;
        emit FreeFeeUser(_user, _free);
    }

    /**
     * @notice Set free withdraw fee address
     * @dev Only callable by the contract admin.
     * @param _user: User address
     * @param _free: true:free false:not free
     */
    function setWithdrawFeeUser(address _user, bool _free) external onlyAdmin {
        require(_user != address(0), "Cannot be zero address");
        freeWithdrawFeeUsers[_user] = _free;
        emit FreeFeeUser(_user, _free);
    }

    /**
     * @notice Set performance fee
     * @dev Only callable by the contract admin.
     */
    function setPerformanceFee(uint256 _performanceFee) external onlyAdmin {
        require(_performanceFee <= MAX_PERFORMANCE_FEE, "performanceFee cannot be more than MAX_PERFORMANCE_FEE");
        performanceFee = _performanceFee;
        emit NewPerformanceFee(performanceFee);
    }


/**
     * @notice Set performance fee for contract
     * @dev Only callable by the contract admin.
     */
    function setPerformanceFeeContract(uint256 _performanceFeeContract) external onlyAdmin {
        require(
            _performanceFeeContract <= MAX_PERFORMANCE_FEE,
            "performanceFee cannot be more than MAX_PERFORMANCE_FEE"
        );
        performanceFeeContract = _performanceFeeContract;
        emit NewPerformanceFeeContract(performanceFeeContract);
    }

    /**
     * @notice Set withdraw fee
     * @dev Only callable by the contract admin.
     */
    function setWithdrawFee(uint256 _withdrawFee) external onlyAdmin {
        require(_withdrawFee <= MAX_WITHDRAW_FEE, "withdrawFee cannot be more than MAX_WITHDRAW_FEE");
        withdrawFee = _withdrawFee;
        emit NewWithdrawFee(withdrawFee);
    }

    /**
     * @notice Set overdue fee
     * @dev Only callable by the contract admin.
     */
    function setOverdueFee(uint256 _overdueFee) external onlyAdmin {
        require(_overdueFee <= MAX_OVERDUE_FEE, "overdueFee cannot be more than MAX_OVERDUE_FEE");
        overdueFee = _overdueFee;
        emit NewOverdueFee(_overdueFee);
    }

    /**
     * @notice Set withdraw fee for contract
     * @dev Only callable by the contract admin.
     */
    function setWithdrawFeeContract(uint256 _withdrawFeeContract) external onlyAdmin {
        require(_withdrawFeeContract <= MAX_WITHDRAW_FEE, "withdrawFee cannot be more than MAX_WITHDRAW_FEE");
        withdrawFeeContract = _withdrawFeeContract;
        emit NewWithdrawFeeContract(withdrawFeeContract);
    }

    /**
     * @notice Set withdraw fee period
     * @dev Only callable by the contract admin.
     */
    function setWithdrawFeePeriod(uint256 _withdrawFeePeriod) external onlyAdmin {
        require(
            _withdrawFeePeriod <= MAX_WITHDRAW_FEE_PERIOD,
            "withdrawFeePeriod cannot be more than MAX_WITHDRAW_FEE_PERIOD"
        );
        withdrawFeePeriod = _withdrawFeePeriod;
        emit NewWithdrawFeePeriod(withdrawFeePeriod);
    }

    /**
     * @notice Set MAX_LOCK_DURATION
     * @dev Only callable by the contract admin.
     */
    function setMaxLockDuration(uint256 _maxLockDuration) external onlyAdmin {
        require(
            _maxLockDuration <= MAX_LOCK_DURATION_LIMIT,
            "MAX_LOCK_DURATION cannot be more than MAX_LOCK_DURATION_LIMIT"
        );
        MAX_LOCK_DURATION = _maxLockDuration;
        emit NewMaxLockDuration(_maxLockDuration);
    }

    /**
     * @notice Set DURATION_FACTOR
     * @dev Only callable by the contract admin.
     */
    function setDurationFactor(uint256 _durationFactor) external onlyAdmin {
        require(_durationFactor > 0, "DURATION_FACTOR cannot be zero");
        DURATION_FACTOR = _durationFactor;
        emit NewDurationFactor(_durationFactor);
    }

    /**
     * @notice Set DURATION_FACTOR_OVERDUE
     * @dev Only callable by the contract admin.
     */
    function setDurationFactorOverdue(uint256 _durationFactorOverdue) external onlyAdmin {
        require(_durationFactorOverdue > 0, "DURATION_FACTOR_OVERDUE cannot be zero");
        DURATION_FACTOR_OVERDUE = _durationFactorOverdue;
        emit NewDurationFactorOverdue(_durationFactorOverdue);
    }

    /**
     * @notice Set UNLOCK_FREE_DURATION
     * @dev Only callable by the contract admin.
     */
    function setUnlockFreeDuration(uint256 _unlockFreeDuration) external onlyAdmin {
        require(_unlockFreeDuration > 0, "UNLOCK_FREE_DURATION cannot be zero");
        UNLOCK_FREE_DURATION = _unlockFreeDuration;
        emit NewUnlockFreeDuration(_unlockFreeDuration);
    }

/**
     * @notice Withdraw unexpected tokens sent to the wkd Pool
     */
    function inCaseTokensGetStuck(address _token) external onlyAdmin {
        require(_token != address(token), "Token cannot be same as deposit token");

        uint256 amount = IERC20(_token).balanceOf(address(this));
        IERC20(_token).safeTransfer(msg.sender, amount);
    }


/**
     * @notice Trigger stopped state
     * @dev Only possible when contract not paused.
     */
    function pause() external onlyAdmin whenNotPaused {
        _pause();
        emit Pause();
    }

    /**
     * @notice Return to normal state
     * @dev Only possible when contract is paused.
     */
    function unpause() external onlyAdmin whenPaused {
        _unpause();
        emit Unpause();
    }

    /**
     * @notice Calculate Performance fee.
     * @param _user: User address
     * @return Returns Performance fee.
     */
    function calculatePerformanceFee(address _user) public view returns (uint256) {
        UserInfo storage user = userInfo[_user];
        if (user.shares > 0 && !user.locked && !freePerformanceFeeUsers[_user]) {
            uint256 pool = balanceOf() + calculateTotalPendingWkdRewards();
            uint256 totalAmount = (user.shares * pool) / totalShares;
            uint256 earnAmount = totalAmount - user.wkdAtLastUserAction;
            uint256 feeRate = performanceFee;
            if (_isContract(_user)) {
                feeRate = performanceFeeContract;
            }
            uint256 currentPerformanceFee = (earnAmount * feeRate) / 10000;
            return currentPerformanceFee;
        }
        return 0;
    }

    /**
     * @notice Calculate overdue fee.
     * @param _user: User address
     * @return Returns Overdue fee.
     */
    function calculateOverdueFee(address _user) public view returns (uint256) {
        UserInfo storage user = userInfo[_user];
        if (
            user.shares > 0 &&
            user.locked &&
            !freeOverdueFeeUsers[_user] &&
            ((user.lockEndTime + UNLOCK_FREE_DURATION) < block.timestamp)
        ) {
            uint256 pool = balanceOf() + calculateTotalPendingWkdRewards();
            uint256 earnAmount = currentAmount - user.lockedAmount;
            uint256 currentAmount = (pool * (user.shares)) / totalShares ;
            uint256 overdueDuration = block.timestamp - user.lockEndTime - UNLOCK_FREE_DURATION;
            if (overdueDuration > DURATION_FACTOR_OVERDUE) {
                overdueDuration = DURATION_FACTOR_OVERDUE;
            }
            // Rates are calculated based on the user's overdue duration.
            uint256 overdueWeight = (overdueDuration * overdueFee) / DURATION_FACTOR_OVERDUE;
            uint256 currentOverdueFee = (earnAmount * overdueWeight) / PRECISION_FACTOR;
            return currentOverdueFee;
        }
        return 0;
    }

    /**
     * @notice Calculate Performance Fee Or Overdue Fee
     * @param _user: User address
     * @return Returns  Performance Fee Or Overdue Fee.
     */
    function calculatePerformanceFeeOrOverdueFee(address _user) internal view returns (uint256) {
        return calculatePerformanceFee(_user) + calculateOverdueFee(_user);
    }

    /**
     * @notice Calculate withdraw fee.
     * @param _user: User address
     * @param _shares: Number of shares to withdraw
     * @return Returns Withdraw fee.
     */
    function calculateWithdrawFee(address _user, uint256 _shares) public view returns (uint256) {
        UserInfo storage user = userInfo[_user];
        if (user.shares < _shares) {
            _shares = user.shares;
        }
        if (!freeWithdrawFeeUsers[msg.sender] && (block.timestamp < user.lastDepositedTime + withdrawFeePeriod)) {
            uint256 pool = balanceOf() + calculateTotalPendingWkdRewards();
            uint256 sharesPercent = (_shares * PRECISION_FACTOR) / user.shares;
            uint256 currentTotalAmount = (pool * (user.shares)) /
                totalShares -
                calculatePerformanceFeeOrOverdueFee(_user);
            uint256 currentAmount = (currentTotalAmount * sharesPercent) / PRECISION_FACTOR;
            uint256 feeRate = withdrawFee;
            if (_isContract(msg.sender)) {
                feeRate = withdrawFeeContract;
            }
            uint256 currentWithdrawFee = (currentAmount * feeRate) / 10000;
            return currentWithdrawFee;
        }
        return 0;
    }


    /**
     * @notice Current pool available balance
     * @dev The contract puts 100% of the tokens to work.
     */
    function available() public view returns (uint256) {
        return token.balanceOf(address(this));
    }

    /**
     * @notice Calculates the total underlying tokens
     */
    function balanceOf() public view returns (uint256) {
        return token.balanceOf(address(this));+
    }

    /**
     * @notice Checks if address is a contract
     */
    function _isContract(address addr) internal view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(addr)
        }
        return size > 0;
    }





}