// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/access/Ownable.sol";
import "@openzeppelin/math/SafeMath.sol";
import "@openzeppelin/utils/ReentrancyGuard.sol";
import "../helpers/IBEP20.sol";
import "../helpers/SafeBEP20.sol";

/// @notice The (older) MasterChef contract gives out a constant number of WKD tokens per block.
/// It is the only address with minting rights for WKD.
/// The idea for this MasterChef V2 (MCV2) contract is therefore to be the owner of a dummy token
/// that is deposited into the MasterChef V1 (MCV1) contract.
/// The allocation point for this pool on MCV1 is the total allocation point for all pools that receive incentives.
contract WKDLPPool is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeBEP20 for IBEP20;

    /// @notice Info of each MCV2 user.
    /// `amount` LP token amount the user has provided.
    /// `rewardDebt` Used to calculate the correct amount of rewards. See explanation below.
    ///
    /// We do some fancy math here. Basically, any point in time, the amount of Wkds
    /// entitled to a user but is pending to be distributed is:
    ///
    ///   pending reward = (user share * pool.accWkdPerShare) - user.rewardDebt
    ///
    ///   Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
    ///   1. The pool's `accWkdPerShare` (and `lastRewardBlock`) gets updated.
    ///   2. User receives the pending reward sent to his/her address.
    ///   3. User's `amount` gets updated. Pool's `totalBoostedShare` gets updated.
    ///   4. User's `rewardDebt` gets updated.
    struct UserInfo {
        uint256 amount;
        uint256 rewardDebt;
        uint256 boostMultiplier;
    }

    /// @notice Info of each MCV2 pool.
    /// `allocPoint` The amount of allocation points assigned to the pool.
    ///     Also known as the amount of "multipliers". Combined with `totalXAllocPoint`, it defines the % of
    ///     WKD rewards each pool gets.
    /// `accWkdPerShare` Accumulated Wkds per share, times 1e12.
    /// `lastRewardBlock` Last block number that pool update action is executed.
    /// `isRegular` The flag to set pool is regular or special. See below:
    ///     In MasterChef V2 farms are "regular pools". "special pools", which use a different sets of
    ///     `allocPoint` and their own `totalSpecialAllocPoint` are designed to handle the distribution of
    ///     the WKD rewards to all the PanWkdSwap products.
    /// `totalBoostedShare` The total amount of user shares in each pool. After considering the share boosts.
    struct PoolInfo {
        uint256 accWkdPerShare;
        uint256 lastRewardBlock;
        uint256 allocPoint;
        uint256 totalBoostedShare;
        bool isRegular;
    }

    /// @notice Address of WKD contract.
    IBEP20 public immutable WKD;

    /// @notice The only address can withdraw all the burn WKD.
    address public burnAdmin;
    /// @notice The contract handles the share boosts.
    address public boostContract;

    /// @notice Info of each MCV2 pool.
    PoolInfo[] public poolInfo;
    /// @notice Address of the LP token for each pool.
    IBEP20[] public lpToken;

    /// @notice Info of each pool user.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    /// @notice The whitelist of addresses allowed to deposit in special pools.
    mapping(address => bool) public whiteList;

    /// @notice Total regular allocation points. Must be the sum of all regular pools' allocation points.
    uint256 public totalRegularAllocPoint;
    /// @notice Total special allocation points. Must be the sum of all special pools' allocation points.
    uint256 public totalSpecialAllocPoint;

    uint256 public constant ACC_WKD_PRECISION = 1e9;

    /// @notice Basic boost factor, none boosted user's boost factor
    uint256 public constant BOOST_PRECISION = 100 * 1e10;
    /// @notice Hard limit for maxmium boost factor, it must be greater than BOOST_PRECISION
    uint256 public constant MAX_BOOST_PRECISION = 200 * 1e10;
    /// @notice total Wkd rate =  toRegular + toSpecial
    uint256 public constant WKD_RATE_TOTAL_PRECISION = 1e12;

    uint256 public WKD_PER_BLOCK = 237779 * 1e9;

    /// @notice WKD distribute % for regular farm pool
    //assuming all wkd goes to regular farms
    uint256 public wkdRateToRegularFarm = 1e12;
    /// @notice WKD distribute % for special pools
    //no boost farms
    uint256 public wkdRateToSpecialFarm = 0;

    event Init();
    event AddPool(
        uint256 indexed pid,
        uint256 allocPoint,
        IBEP20 indexed lpToken,
        bool isRegular
    );
    event SetPool(uint256 indexed pid, uint256 allocPoint);
    event UpdatePool(
        uint256 indexed pid,
        uint256 lastRewardBlock,
        uint256 lpSupply,
        uint256 accWkdPerShare
    );
    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(
        address indexed user,
        uint256 indexed pid,
        uint256 amount
    );

    event UpdateWkdRate(uint256 regularFarmRate, uint256 specialFarmRate);

    event UpdateWhiteList(address indexed user, bool isValid);
    event UpdateBoostContract(address indexed boostContract);
    event UpdateBoostMultiplier(
        address indexed user,
        uint256 pid,
        uint256 oldMultiplier,
        uint256 newMultiplier
    );

    /// @param _WKD The WKD token contract address.
    constructor(IBEP20 _WKD) public {
        WKD = _WKD;
    }

    /**
     * @dev Throws if caller is not the boost contract.
     */
    modifier onlyBoostContract() {
        require(
            boostContract == msg.sender,
            "Ownable: caller is not the boost contract"
        );
        _;
    }

    /// @notice Returns the number of MCV2 pools.
    function poolLength() public view returns (uint256 pools) {
        pools = poolInfo.length;
    }

    /// @notice Add a new pool. Can only be called by the owner.
    /// DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    /// @param _allocPoint Number of allocation points for the new pool.
    /// @param _lpToken Address of the LP BEP-20 token.
    /// @param _isRegular Whether the pool is regular or special. LP farms are always "regular". "Special" pools are
    /// @param _withUpdate Whether call "massUpdatePools" operation.
    /// only for WKD distributions within PanWkdSwap products.
    function add(
        uint256 _allocPoint,
        IBEP20 _lpToken,
        bool _isRegular,
        bool _withUpdate
    ) external onlyOwner {
        require(_lpToken.balanceOf(address(this)) == 0, "None BEP20 tokens");
        // stake WKD token will cause staked token and reward token mixed up,
        // may cause staked tokens withdraw as reward token,never do it.
        require(_lpToken != WKD, "WKD token can't be added to farm pools");

        if (_withUpdate) {
            massUpdatePools();
        }

        if (_isRegular) {
            totalRegularAllocPoint = totalRegularAllocPoint.add(_allocPoint);
        } else {
            totalSpecialAllocPoint = totalSpecialAllocPoint.add(_allocPoint);
        }
        lpToken.push(_lpToken);

        poolInfo.push(
            PoolInfo({
                allocPoint: _allocPoint,
                lastRewardBlock: block.number,
                accWkdPerShare: 0,
                isRegular: _isRegular,
                totalBoostedShare: 0
            })
        );
        emit AddPool(lpToken.length.sub(1), _allocPoint, _lpToken, _isRegular);
    }

    /// @notice Update the given pool's WKD allocation point. Can only be called by the owner.
    /// @param _pid The id of the pool. See `poolInfo`.
    /// @param _allocPoint New number of allocation points for the pool.
    /// @param _withUpdate Whether call "massUpdatePools" operation.
    function set(
        uint256 _pid,
        uint256 _allocPoint,
        bool _withUpdate
    ) external onlyOwner {
        // No matter _withUpdate is true or false, we need to execute updatePool once before set the pool parameters.
        updatePool(_pid);

        if (_withUpdate) {
            massUpdatePools();
        }

        if (poolInfo[_pid].isRegular) {
            totalRegularAllocPoint = totalRegularAllocPoint
                .sub(poolInfo[_pid].allocPoint)
                .add(_allocPoint);
        } else {
            totalSpecialAllocPoint = totalSpecialAllocPoint
                .sub(poolInfo[_pid].allocPoint)
                .add(_allocPoint);
        }
        poolInfo[_pid].allocPoint = _allocPoint;
        emit SetPool(_pid, _allocPoint);
    }

    /// @notice View function for checking pending WKD rewards.
    /// @param _pid The id of the pool. See `poolInfo`.
    /// @param _user Address of the user.
    function pendingWkd(uint256 _pid, address _user)
        external
        view
        returns (uint256)
    {
        PoolInfo memory pool = poolInfo[_pid];
        UserInfo memory user = userInfo[_pid][_user];
        uint256 accWkdPerShare = pool.accWkdPerShare;
        uint256 lpSupply = pool.totalBoostedShare;

        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 multiplier = block.number.sub(pool.lastRewardBlock);

            uint256 wkdReward = multiplier
                .mul(wkdPerBlock(pool.isRegular))
                .mul(pool.allocPoint)
                .div(
                    (
                        pool.isRegular
                            ? totalRegularAllocPoint
                            : totalSpecialAllocPoint
                    )
                );
            accWkdPerShare = accWkdPerShare.add(
                wkdReward.mul(ACC_WKD_PRECISION).div(lpSupply)
            );
        }
        //we assume no boosts
        uint256 boostedAmount = user
            .amount
            .mul(getBoostMultiplier(_user, _pid))
            .div(BOOST_PRECISION);
        return
            boostedAmount.mul(accWkdPerShare).div(ACC_WKD_PRECISION).sub(
                user.rewardDebt
            );
    }

    /// @notice Update Wkd reward for all the active pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            PoolInfo memory pool = poolInfo[pid];
            if (pool.allocPoint != 0) {
                updatePool(pid);
            }
        }
    }

    /// @notice Calculates and returns the `amount` of WKD per block.
    /// @param _isRegular If the pool belongs to regular or special.
    function wkdPerBlock(bool _isRegular) public view returns (uint256 amount) {
        if (_isRegular) {
            amount = WKD_PER_BLOCK.mul(wkdRateToRegularFarm).div(
                WKD_RATE_TOTAL_PRECISION
            );
        } else {
            amount = WKD_PER_BLOCK.mul(wkdRateToSpecialFarm).div(
                WKD_RATE_TOTAL_PRECISION
            );
        }
    }

    /// @notice Update reward variables for the given pool.
    /// @param _pid The id of the pool. See `poolInfo`.
    /// @return pool Returns the pool that was updated.
    function updatePool(uint256 _pid) public returns (PoolInfo memory pool) {
        pool = poolInfo[_pid];
        if (block.number > pool.lastRewardBlock) {
            uint256 lpSupply = pool.totalBoostedShare;
            uint256 totalAllocPoint = (
                pool.isRegular ? totalRegularAllocPoint : totalSpecialAllocPoint
            );

            if (lpSupply > 0 && totalAllocPoint > 0) {
                uint256 multiplier = block.number.sub(pool.lastRewardBlock);
                uint256 wkdReward = multiplier
                    .mul(wkdPerBlock(pool.isRegular))
                    .mul(pool.allocPoint)
                    .div(totalAllocPoint);
                pool.accWkdPerShare = pool.accWkdPerShare.add(
                    (wkdReward.mul(ACC_WKD_PRECISION).div(lpSupply))
                );
            }
            pool.lastRewardBlock = block.number;
            poolInfo[_pid] = pool;
            emit UpdatePool(
                _pid,
                pool.lastRewardBlock,
                lpSupply,
                pool.accWkdPerShare
            );
        }
    }

    /// @notice Deposit LP tokens to pool.
    /// @param _pid The id of the pool. See `poolInfo`.
    /// @param _amount Amount of LP tokens to deposit.
    function deposit(uint256 _pid, uint256 _amount) external nonReentrant {
        PoolInfo memory pool = updatePool(_pid);
        UserInfo storage user = userInfo[_pid][msg.sender];

        require(
            pool.isRegular || whiteList[msg.sender],
            "WKDLPPool: The address is not available to deposit in this pool"
        );

        uint256 multiplier = getBoostMultiplier(msg.sender, _pid);

        if (user.amount > 0) {
            settlePendingWkd(msg.sender, _pid, multiplier);
        }

        if (_amount > 0) {
            uint256 before = lpToken[_pid].balanceOf(address(this));
            lpToken[_pid].safeTransferFrom(msg.sender, address(this), _amount);
            _amount = lpToken[_pid].balanceOf(address(this)).sub(before);
            user.amount = user.amount.add(_amount);

            // Update total boosted share.
            pool.totalBoostedShare = pool.totalBoostedShare.add(
                _amount.mul(multiplier).div(BOOST_PRECISION)
            );
        }

        user.rewardDebt = user
            .amount
            .mul(multiplier)
            .div(BOOST_PRECISION)
            .mul(pool.accWkdPerShare)
            .div(ACC_WKD_PRECISION);
        poolInfo[_pid] = pool;

        emit Deposit(msg.sender, _pid, _amount);
    }

    /// @notice Withdraw LP tokens from pool.
    /// @param _pid The id of the pool. See `poolInfo`.
    /// @param _amount Amount of LP tokens to withdraw.
    function withdraw(uint256 _pid, uint256 _amount) external nonReentrant {
        PoolInfo memory pool = updatePool(_pid);
        UserInfo storage user = userInfo[_pid][msg.sender];

        require(user.amount >= _amount, "withdraw: Insufficient");

        uint256 multiplier = getBoostMultiplier(msg.sender, _pid);

        settlePendingWkd(msg.sender, _pid, multiplier);

        if (_amount > 0) {
            user.amount = user.amount.sub(_amount);
            lpToken[_pid].safeTransfer(msg.sender, _amount);
        }

        user.rewardDebt = user
            .amount
            .mul(multiplier)
            .div(BOOST_PRECISION)
            .mul(pool.accWkdPerShare)
            .div(ACC_WKD_PRECISION);
        poolInfo[_pid].totalBoostedShare = poolInfo[_pid].totalBoostedShare.sub(
            _amount.mul(multiplier).div(BOOST_PRECISION)
        );

        emit Withdraw(msg.sender, _pid, _amount);
    }

    /// @notice Withdraw without caring about the rewards. EMERGENCY ONLY.
    /// @param _pid The id of the pool. See `poolInfo`.
    function emergencyWithdraw(uint256 _pid) external nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        uint256 amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        uint256 boostedAmount = amount
            .mul(getBoostMultiplier(msg.sender, _pid))
            .div(BOOST_PRECISION);
        pool.totalBoostedShare = pool.totalBoostedShare > boostedAmount
            ? pool.totalBoostedShare.sub(boostedAmount)
            : 0;

        // Note: transfer can fail or succeed if `amount` is zero.
        lpToken[_pid].safeTransfer(msg.sender, amount);
        emit EmergencyWithdraw(msg.sender, _pid, amount);
    }

    /// @notice Update the % of WKD distributions for regular pools and special pools.
    /// @param _regularFarmRate The % of WKD to regular pools each block.
    /// @param _specialFarmRate The % of WKD to special pools each block.
    /// @param _withUpdate Whether call "massUpdatePools" operation.
    function updateWkdRate(
        uint256 _regularFarmRate,
        uint256 _specialFarmRate,
        bool _withUpdate
    ) external onlyOwner {
        require(
            _regularFarmRate.add(_specialFarmRate) == WKD_RATE_TOTAL_PRECISION,
            "WKDLPPool: Total rate must be 1e12"
        );
        if (_withUpdate) {
            massUpdatePools();
        }

        wkdRateToRegularFarm = _regularFarmRate;
        wkdRateToSpecialFarm = _specialFarmRate;

        emit UpdateWkdRate(_regularFarmRate, _specialFarmRate);
    }

    /// @notice Update whitelisted addresses for special pools.
    /// @param _user The address to be updated.
    /// @param _isValid The flag for valid or invalid.
    function updateWhiteList(address _user, bool _isValid) external onlyOwner {
        require(
            _user != address(0),
            "WKDLPPool: The white list address must be valid"
        );

        whiteList[_user] = _isValid;
        emit UpdateWhiteList(_user, _isValid);
    }

    /// @notice Update boost contract address and max boost factor.
    /// @param _newBoostContract The new address for handling all the share boosts.
    function updateBoostContract(address _newBoostContract) external onlyOwner {
        require(
            _newBoostContract != address(0) &&
                _newBoostContract != boostContract,
            "WKDLPPool: New boost contract address must be valid"
        );

        boostContract = _newBoostContract;
        emit UpdateBoostContract(_newBoostContract);
    }

    /// @notice Update user boost factor.
    /// @param _user The user address for boost factor updates.
    /// @param _pid The pool id for the boost factor updates.
    /// @param _newMultiplier New boost multiplier.
    function updateBoostMultiplier(
        address _user,
        uint256 _pid,
        uint256 _newMultiplier
    ) external onlyBoostContract nonReentrant {
        require(
            _user != address(0),
            "WKDLPPool: The user address must be valid"
        );
        require(
            poolInfo[_pid].isRegular,
            "WKDLPPool: Only regular farm could be boosted"
        );
        require(
            _newMultiplier >= BOOST_PRECISION &&
                _newMultiplier <= MAX_BOOST_PRECISION,
            "WKDLPPool: Invalid new boost multiplier"
        );

        PoolInfo memory pool = updatePool(_pid);
        UserInfo storage user = userInfo[_pid][_user];

        uint256 prevMultiplier = getBoostMultiplier(_user, _pid);
        settlePendingWkd(_user, _pid, prevMultiplier);

        user.rewardDebt = user
            .amount
            .mul(_newMultiplier)
            .div(BOOST_PRECISION)
            .mul(pool.accWkdPerShare)
            .div(ACC_WKD_PRECISION);
        pool.totalBoostedShare = pool
            .totalBoostedShare
            .sub(user.amount.mul(prevMultiplier).div(BOOST_PRECISION))
            .add(user.amount.mul(_newMultiplier).div(BOOST_PRECISION));
        poolInfo[_pid] = pool;
        userInfo[_pid][_user].boostMultiplier = _newMultiplier;

        emit UpdateBoostMultiplier(_user, _pid, prevMultiplier, _newMultiplier);
    }

    /// @notice Get user boost multiplier for specific pool id.
    /// @param _user The user address.
    /// @param _pid The pool id.
    function getBoostMultiplier(address _user, uint256 _pid)
        public
        view
        returns (uint256)
    {
        uint256 multiplier = userInfo[_pid][_user].boostMultiplier;
        return multiplier > BOOST_PRECISION ? multiplier : BOOST_PRECISION;
    }

    /// @notice Settles, distribute the pending WKD rewards for given user.
    /// @param _user The user address for settling rewards.
    /// @param _pid The pool id.
    /// @param _boostMultiplier The user boost multiplier in specific pool id.
    function settlePendingWkd(
        address _user,
        uint256 _pid,
        uint256 _boostMultiplier
    ) internal {
        UserInfo memory user = userInfo[_pid][_user];

        uint256 boostedAmount = user.amount.mul(_boostMultiplier).div(
            BOOST_PRECISION
        );
        uint256 accWkd = boostedAmount.mul(poolInfo[_pid].accWkdPerShare).div(
            ACC_WKD_PRECISION
        );
        uint256 pending = accWkd.sub(user.rewardDebt);
        // SafeTransfer WKD
        _safeTransfer(_user, pending);
    }

    function emergencyRescue(uint256 _amount, address _token) public onlyOwner {
        IBEP20(_token).transfer(msg.sender, _amount);
    }

    /// @notice Safe Transfer WKD.
    /// @param _to The WKD receiver address.
    /// @param _amount transfer WKD amounts.
    function _safeTransfer(address _to, uint256 _amount) internal {
        if (_amount > 0) {
            if (WKD.balanceOf(address(this)) < _amount) {
                revert("Not enough WKD for rewards");
            }
            uint256 balance = WKD.balanceOf(address(this));
            if (balance < _amount) {
                _amount = balance;
            }
            WKD.safeTransfer(_to, _amount);
        }
    }
}
