pragma solidity 0.6.12;

import "@openzeppelin/contracts-ethereum-package/contracts/access/Ownable.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/Initializable.sol";
import "./lib/SafeMathInt.sol";
import "./LbdToken.sol";

contract Cascade is OwnableUpgradeSafe {
    using SafeMath for uint256;
    using SafeMathInt for int256;

    mapping(address => uint256) internal deposits_lpTokensDeposited;
    mapping(address => uint256) internal deposits_depositTimestamp;
    mapping(address => uint8)   internal deposits_multiplierLevel;
    mapping(address => uint256) internal deposits_mostRecentLBDWithdrawal;


    uint256 public totalDepositedLevel1;
    uint256 public totalDepositedLevel2;
    uint256 public totalDepositedLevel3;
    uint256 public totalDepositSecondsLevel1;
    uint256 public totalDepositSecondsLevel2;
    uint256 public totalDepositSecondsLevel3;
    uint256 public lastAccountingUpdateTimestamp;
    IERC20 public lpToken;
    LbdToken public LBD;
    uint256 public minTimeBetweenWithdrawals;

    function initialize()
        public
        initializer
    {
        __Ownable_init();
    }

    /**
     * Admin
     */

    function setLPToken(address _lpToken)
        public
        onlyOwner
    {
        lpToken = IERC20(_lpToken);
    }

    function setLBDToken(address _lbdToken)
        public
        onlyOwner
    {
        LBD = LbdToken(_lbdToken);
    }

    function setMinTimeBetweenWithdrawals(uint256 _minTimeBetweenWithdrawals)
        public
        onlyOwner
    {
        minTimeBetweenWithdrawals = _minTimeBetweenWithdrawals;
    }

    function adminWithdrawLBD(address recipient, uint256 amount)
        public
        onlyOwner
    {
        require(recipient != address(0x0), "bad recipient");
        require(amount > 0, "bad amount");

        bool ok = LBD.transfer(recipient, amount);
        require(ok, "transfer");
    }

    function rescueMistakenlySentTokens(address token, address recipient, uint256 amount)
        public
        onlyOwner
    {
        require(recipient != address(0x0), "bad recipient");
        require(amount > 0, "bad amount");

        bool ok = IERC20(token).transfer(recipient, amount);
        require(ok, "transfer");
    }

    /**
     * Public methods
     */

    function deposit(uint256 amount)
        public
    {
        updateDepositSeconds();

        uint256 allowance = lpToken.allowance(msg.sender, address(this));
        require(amount <= allowance, "allowance");

        if (deposits_multiplierLevel[msg.sender] > 0) {
            burnDepositSeconds(msg.sender);
        }

        totalDepositedLevel1 = totalDepositedLevel1.add(amount);

        deposits_lpTokensDeposited[msg.sender] = deposits_lpTokensDeposited[msg.sender].add(amount);
        deposits_depositTimestamp[msg.sender] = now;
        deposits_multiplierLevel[msg.sender] = 1;

        bool ok = lpToken.transferFrom(msg.sender, address(this), amount);
        require(ok, "transferFrom");
    }

    function upgradeMultiplierLevel()
        public
    {
        require(deposits_multiplierLevel[msg.sender] > 0, "no deposit");
        require(deposits_multiplierLevel[msg.sender] < 3, "fully upgraded");

        burnDepositSeconds(msg.sender);

        uint256 duration = now.sub(deposits_depositTimestamp[msg.sender]);

        if (deposits_multiplierLevel[msg.sender] == 1 && duration >= 60 days) {
            deposits_multiplierLevel[msg.sender] = 3;
            totalDepositedLevel3 = totalDepositedLevel3.add(deposits_lpTokensDeposited[msg.sender]);

        } else if (deposits_multiplierLevel[msg.sender] == 1 && duration >= 30 days) {
            deposits_multiplierLevel[msg.sender] = 2;
            totalDepositedLevel2 = totalDepositedLevel2.add(deposits_lpTokensDeposited[msg.sender]);

        } else if (deposits_multiplierLevel[msg.sender] == 2 && duration >= 60 days) {
            deposits_multiplierLevel[msg.sender] = 3;
            totalDepositedLevel3 = totalDepositedLevel3.add(deposits_lpTokensDeposited[msg.sender]);

        } else {
            revert("ineligible");
        }
    }

    function claimLBD()
        public
    {
        updateDepositSeconds();

        require(deposits_multiplierLevel[msg.sender] > 0, "doesn't exist");
        require(allowedToWithdraw(msg.sender), "too soon");

        uint256 owed = owedTo(msg.sender);
        require(LBD.balanceOf(address(this)) >= owed, "available tokens");

        deposits_mostRecentLBDWithdrawal[msg.sender] = now;

        bool ok = LBD.transfer(msg.sender, owed);
        require(ok, "transfer");
    }

    function withdrawLPTokens()
        public
    {
        updateDepositSeconds();
        claimLBD();

        require(deposits_multiplierLevel[msg.sender] > 0, "doesn't exist");
        require(deposits_lpTokensDeposited[msg.sender] > 0, "no stake");
        require(allowedToWithdraw(msg.sender), "too soon");

        burnDepositSeconds(msg.sender);

        uint256 deposited = deposits_lpTokensDeposited[msg.sender];

        delete deposits_lpTokensDeposited[msg.sender];
        delete deposits_depositTimestamp[msg.sender];
        delete deposits_multiplierLevel[msg.sender];
        delete deposits_mostRecentLBDWithdrawal[msg.sender];

        bool ok = lpToken.transfer(msg.sender, deposited);
        require(ok, "transfer");
    }

    /**
     * Accounting utilities
     */

    function updateDepositSeconds()
        private
    {
        uint256 delta = now.sub(lastAccountingUpdateTimestamp);
        totalDepositSecondsLevel1 = totalDepositSecondsLevel1.add(totalDepositedLevel1.mul(delta));
        totalDepositSecondsLevel2 = totalDepositSecondsLevel2.add(totalDepositedLevel2.mul(delta));
        totalDepositSecondsLevel3 = totalDepositSecondsLevel3.add(totalDepositedLevel3.mul(delta));

        lastAccountingUpdateTimestamp = now;
    }

    function burnDepositSeconds(address user)
        private
    {
        uint256 depositSecondsToBurn = now.sub(deposits_depositTimestamp[user]).mul(deposits_lpTokensDeposited[user]);
        if (deposits_multiplierLevel[user] == 1) {
            totalDepositedLevel1 = totalDepositedLevel1.sub(deposits_lpTokensDeposited[user]);
            totalDepositSecondsLevel1 = totalDepositSecondsLevel1.sub(depositSecondsToBurn);

        } else if (deposits_multiplierLevel[user] == 2) {
            totalDepositedLevel2 = totalDepositedLevel2.sub(deposits_lpTokensDeposited[user]);
            totalDepositSecondsLevel2 = totalDepositSecondsLevel2.sub(depositSecondsToBurn);

        } else if (deposits_multiplierLevel[user] == 3) {
            totalDepositedLevel3 = totalDepositedLevel3.sub(deposits_lpTokensDeposited[user]);
            totalDepositSecondsLevel3 = totalDepositSecondsLevel3.sub(depositSecondsToBurn);
        }
    }

    /**
     * Getters
     */

    function depositInfo(address user)
        public
        view
        returns (
            uint256 _lpTokensDeposited,
            uint256 _depositTimestamp,
            uint8   _multiplierLevel,
            uint256 _mostRecentLBDWithdrawal,
            uint256 _userDepositSeconds,
            uint256 _totalDepositSeconds
        )
    {
        uint256 delta = now.sub(lastAccountingUpdateTimestamp);
        _totalDepositSeconds = totalDepositSecondsLevel1.add(totalDepositedLevel1.mul(delta))
                                  .add(totalDepositSecondsLevel2.add(totalDepositedLevel2.mul(delta)).mul(2))
                                  .add(totalDepositSecondsLevel3.add(totalDepositedLevel3.mul(delta)).mul(3));

        return (
            deposits_lpTokensDeposited[user],
            deposits_depositTimestamp[user],
            deposits_multiplierLevel[user],
            deposits_mostRecentLBDWithdrawal[user],
            userDepositSeconds(user),
            _totalDepositSeconds
        );
    }

    function allowedToWithdraw(address user)
        public
        view
        returns (bool)
    {
        return deposits_mostRecentLBDWithdrawal[user] == 0
                ? now > deposits_depositTimestamp[user].add(minTimeBetweenWithdrawals)
                : now > deposits_mostRecentLBDWithdrawal[user].add(minTimeBetweenWithdrawals);
    }

    function userDepositSeconds(address user)
        public
        view
        returns (uint256)
    {
        return deposits_lpTokensDeposited[user]
                  .mul(now.sub(deposits_depositTimestamp[user]))
                  .mul(deposits_multiplierLevel[user]);
    }

    function totalDepositSeconds()
        public
        view
        returns (uint256)
    {
        return totalDepositSecondsLevel1
                  .add(totalDepositSecondsLevel2.mul(2))
                  .add(totalDepositSecondsLevel3.mul(3));
    }

    function rewardsPool()
        public
        view
        returns (uint256)
    {
        return LBD.balanceOf(address(this));
    }

    function owedTo(address user)
        public
        view
        returns (uint256 amount)
    {
        return rewardsPool().mul(userDepositSeconds(user)).div(totalDepositSeconds());
    }
}
