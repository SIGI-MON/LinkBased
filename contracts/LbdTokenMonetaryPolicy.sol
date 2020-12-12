pragma solidity 0.6.12;

import "@openzeppelin/contracts-ethereum-package/contracts/access/Ownable.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/Initializable.sol";

import "./lib/SafeMathInt.sol";
import "./lib/UInt256Lib.sol";
import "./LbdToken.sol";


interface IOracle {
    function getData() external returns (uint256, bool);
}

interface IERC20Decimals {
    function decimals() external view returns (uint);
}

interface IUniswapV2Router02 {
    function getAmountsOut(uint amountIn, address[] memory path) external view returns (uint[] memory amounts);
}

/**
 * @title LbdToken Monetary Supply Policy
 * @dev This is an implementation of the LbdToken Index Fund protocol.
 *      LbdToken operates symmetrically on expansion and contraction. It will both split and
 *      combine coins to maintain a stable unit price.
 *
 *      This component regulates the token supply of the LbdToken ERC20 token in response to
 *      market oracles.
 */
contract LbdTokenMonetaryPolicy is OwnableUpgradeSafe {
    using SafeMath for uint256;
    using SafeMathInt for int256;
    using UInt256Lib for uint256;

    event LogRebase(
        uint256 indexed epoch,
        uint256 exchangeRate,
        uint256 mcap,
        int256 requestedSupplyAdjustment,
        uint256 timestampSec
    );

    LbdToken public LBD;

    IERC20 public linkToken;

    // Provides the current LINK/USD price as an 8 decimal fixed point number.
    IOracle public linkPriceOracle;

    // Market oracle provides the token/USD exchange rate as an 18 decimal fixed point number.
    // (eg) An oracle value of 1.5e18 it would mean 1 LBD is trading for $1.50.
    IOracle public tokenPriceOracle;

    address public uniswapRouter;
    address public usdt;

    // If the current exchange rate is within this fractional distance from the target, no supply
    // update is performed. Fixed point number--same format as the rate.
    // (ie) abs(rate - targetRate) / targetRate < deviationThreshold, then no supply change.
    // DECIMALS Fixed point number.
    uint256 public deviationThreshold;

    // The rebase lag parameter, used to dampen the applied supply adjustment by 1 / rebaseLag
    // Check setRebaseLag comments for more details.
    // Natural number, no decimal places.
    uint256 public rebaseLag;

    // More than this much time must pass between rebase operations.
    uint256 public minRebaseTimeIntervalSec;

    // Block timestamp of last rebase operation
    uint256 public lastRebaseTimestampSec;

    // The rebase window begins this many seconds into the minRebaseTimeInterval period.
    // For example if minRebaseTimeInterval is 24hrs, it represents the time of day in seconds.
    uint256 public rebaseWindowOffsetSec;

    // The length of the time window where a rebase operation is allowed to execute, in seconds.
    uint256 public rebaseWindowLengthSec;

    // The number of rebase cycles since inception
    uint256 public epoch;

    uint256 private constant DECIMALS = 18;

    // Due to the expression in computeSupplyDelta(), MAX_RATE * MAX_SUPPLY must fit into an int256.
    // Both are 18 decimals fixed point numbers.
    uint256 private constant MAX_RATE = 10**6 * 10**DECIMALS;
    // MAX_SUPPLY = MAX_INT256 / MAX_RATE
    uint256 private constant MAX_SUPPLY = ~(uint256(1) << 255) / MAX_RATE;

    // This module orchestrates the rebase execution and downstream notification.
    address public orchestrator;

    address[] public charityRecipients;
    mapping(address => bool)    public charityExists;
    mapping(address => uint256) public charityIndex;
    mapping(address => uint256) public charityPercentOnExpansion;
    mapping(address => uint256) public charityPercentOnContraction;
    uint256 public totalCharityPercentOnExpansion;
    uint256 public totalCharityPercentOnContraction;


    /// Function to set uniswap router address and usdt token address
    function setUniswapRouter(
        address _uniswapRouter
    )
    public
    onlyOwner
    {
        uniswapRouter = _uniswapRouter;
    }


    function setUsdtToken(
        address _usdt
    )
    public
    onlyOwner
    {
        usdt = _usdt;
    }


    function setLBDToken(address _LBD)
        public
        onlyOwner
    {
        LBD = LbdToken(_LBD);
    }


    /**
     * @notice          Function to set address of link token.
     */
    function setLinkToken(address _linkToken)
    public
    onlyOwner
    {
        linkToken = IERC20(_linkToken);
    }

    /**
     * @notice Initiates a new rebase operation, provided the minimum time period has elapsed.
     *
     * @dev The supply adjustment equals (_totalSupply * DeviationFromTargetRate) / rebaseLag
     *      Where DeviationFromTargetRate is (TokenPriceOracleRate - targetPrice) / targetPrice
     *      and targetPrice is McapOracleRate / baseMcap
     */
    function rebase() external {
        require(msg.sender == orchestrator, "you are not the orchestrator");
        require(inRebaseWindow(), "the rebase window is closed");

        // This comparison also ensures there is no reentrancy.
        require(lastRebaseTimestampSec.add(minRebaseTimeIntervalSec) < now, "cannot rebase yet");

        // Snap the rebase time to the start of this window.
        lastRebaseTimestampSec = now.sub(now.mod(minRebaseTimeIntervalSec)).add(rebaseWindowOffsetSec);

        epoch = epoch.add(1);

        uint256 linkPrice;
        bool linkPriceValid;
        (linkPrice, linkPriceValid) = linkPriceOracle.getData();
        require(linkPriceValid, "invalid mcap");

        uint mcap = getLinkMarketCapUSD(linkPrice);

        uint256 targetPrice = mcap.div(10_000_000_000);

        uint tokenPrice = getTokenPriceFromUniswap();

        if (tokenPrice > MAX_RATE) {
            tokenPrice = MAX_RATE;
        }

        int256 supplyDelta = computeSupplyDelta(tokenPrice, targetPrice);

        // Apply the Dampening factor.
        supplyDelta = supplyDelta.div(rebaseLag.toInt256Safe());

        if (supplyDelta == 0) {
            emit LogRebase(epoch, tokenPrice, mcap, supplyDelta, now);
            return;
        }

        if (supplyDelta > 0 && LBD.totalSupply().add(uint256(supplyDelta)) > MAX_SUPPLY) {
            supplyDelta = (MAX_SUPPLY.sub(LBD.totalSupply())).toInt256Safe();
        }

        applyCharity(supplyDelta);
        uint256 supplyAfterRebase = LBD.rebase(epoch, supplyDelta);
        assert(supplyAfterRebase <= MAX_SUPPLY);
        emit LogRebase(epoch, tokenPrice, mcap, supplyDelta, now);
    }

    function applyCharity(int256 supplyDelta)
        private
    {
        uint256 totalCharityPercent = supplyDelta < 0 ? totalCharityPercentOnContraction
                                                      : totalCharityPercentOnExpansion;

        uint256 totalCharitySupply = uint256(supplyDelta.abs()).mul(totalCharityPercent).div(100);
        uint256 supplyAfterRebase = (supplyDelta < 0) ? LBD.totalSupply().sub(uint256(supplyDelta.abs()))
                                                      : LBD.totalSupply().add(uint256(supplyDelta));

        uint256 totalSharesDelta = totalCharitySupply.mul(LBD.totalShares())
                            .div(//------------------------------------------
                                   supplyAfterRebase.sub(totalCharitySupply)
                             );

        // Overflow protection without reverting.  If an overflow will occur, the charity program is finished.
        if (LBD.totalShares() + totalSharesDelta < LBD.totalShares()) {
            return;
        }

        for (uint256 i = 0; i < charityRecipients.length; i++) {
            address recipient = charityRecipients[i];
            uint256 recipientPercent = supplyDelta < 0 ? charityPercentOnContraction[recipient]
                                                       : charityPercentOnExpansion[recipient];
            if (recipientPercent == 0) {
                continue;
            }

            uint256 recipientSharesDelta = totalSharesDelta.mul(recipientPercent).div(totalCharityPercent);
            LBD.mintShares(recipient, recipientSharesDelta);
        }
    }

    function addCharityRecipient(address addr, uint256 percentOnExpansion, uint256 percentOnContraction)
        external
        onlyOwner
    {
        require(totalCharityPercentOnExpansion.add(percentOnExpansion) <= 100, "expansion");
        require(totalCharityPercentOnContraction.add(percentOnContraction) <= 100, "contraction");
        require(charityExists[addr] == false, "already exists");

        totalCharityPercentOnExpansion = totalCharityPercentOnExpansion.add(percentOnExpansion);
        totalCharityPercentOnContraction = totalCharityPercentOnContraction.add(percentOnContraction);
        charityExists[addr] = true;
        charityIndex[addr] = charityRecipients.length;
        charityPercentOnExpansion[addr] = percentOnExpansion;
        charityPercentOnContraction[addr] = percentOnContraction;
        charityRecipients.push(addr);
    }

    function removeCharityRecipient(address addr)
        external
        onlyOwner
    {
        require(charityExists[addr], "doesn't exist");
        require(charityRecipients.length > 0, "spacetime has shattered");
        require(charityRecipients.length - 1 >= charityIndex[addr], "too much cosmic radiation");

        totalCharityPercentOnExpansion = totalCharityPercentOnExpansion.sub(charityPercentOnExpansion[addr]);
        totalCharityPercentOnContraction = totalCharityPercentOnContraction.sub(charityPercentOnContraction[addr]);

        charityRecipients[charityIndex[addr]] = charityRecipients[charityRecipients.length - 1];
        charityRecipients.pop();
        delete charityExists[addr];
        delete charityIndex[addr];
        delete charityPercentOnExpansion[addr];
        delete charityPercentOnContraction[addr];
    }

    /**
     * @notice Sets the reference to the market cap oracle.
     * @param _linkOracle The address of the link price oracle contract.
     */
    function setLinkOracle(IOracle _linkOracle)
        external
        onlyOwner
    {
        linkPriceOracle = _linkOracle;
    }

    /**
     * @notice Sets the reference to the token price oracle.
     * @param tokenPriceOracle_ The address of the token price oracle contract.
     */
    function setTokenPriceOracle(IOracle tokenPriceOracle_)
        external
        onlyOwner
    {
        tokenPriceOracle = tokenPriceOracle_;
    }



    /**
     * @notice Sets the reference to the orchestrator.
     * @param orchestrator_ The address of the orchestrator contract.
     */
    function setOrchestrator(address orchestrator_)
        external
        onlyOwner
    {
        orchestrator = orchestrator_;
    }

    /**
     * @notice Sets the deviation threshold fraction. If the exchange rate given by the market
     *         oracle is within this fractional distance from the targetRate, then no supply
     *         modifications are made. DECIMALS fixed point number.
     * @param deviationThreshold_ The new exchange rate threshold fraction.
     */
    function setDeviationThreshold(uint256 deviationThreshold_)
        external
        onlyOwner
    {
        deviationThreshold = deviationThreshold_;
    }

    /**
     * @notice Sets the rebase lag parameter.
               It is used to dampen the applied supply adjustment by 1 / rebaseLag
               If the rebase lag R, equals 1, the smallest value for R, then the full supply
               correction is applied on each rebase cycle.
               If it is greater than 1, then a correction of 1/R of is applied on each rebase.
     * @param rebaseLag_ The new rebase lag parameter.
     */
    function setRebaseLag(uint256 rebaseLag_)
        external
        onlyOwner
    {
        require(rebaseLag_ > 0);
        rebaseLag = rebaseLag_;
    }

    /**
     * @notice Sets the parameters which control the timing and frequency of
     *         rebase operations.
     *         a) the minimum time period that must elapse between rebase cycles.
     *         b) the rebase window offset parameter.
     *         c) the rebase window length parameter.
     * @param minRebaseTimeIntervalSec_ More than this much time must pass between rebase
     *        operations, in seconds.
     * @param rebaseWindowOffsetSec_ The number of seconds from the beginning of
              the rebase interval, where the rebase window begins.
     * @param rebaseWindowLengthSec_ The length of the rebase window in seconds.
     */
    function setRebaseTimingParameters(
        uint256 minRebaseTimeIntervalSec_,
        uint256 rebaseWindowOffsetSec_,
        uint256 rebaseWindowLengthSec_)
        external
        onlyOwner
    {
        require(minRebaseTimeIntervalSec_ > 0, "minRebaseTimeIntervalSec cannot be 0");
        require(rebaseWindowOffsetSec_ < minRebaseTimeIntervalSec_, "rebaseWindowOffsetSec_ >= minRebaseTimeIntervalSec_");

        minRebaseTimeIntervalSec = minRebaseTimeIntervalSec_;
        rebaseWindowOffsetSec = rebaseWindowOffsetSec_;
        rebaseWindowLengthSec = rebaseWindowLengthSec_;
    }

    /**
     * @dev ZOS upgradable contract initialization method.
     *      It is called at the time of contract creation to invoke parent class initializers and
     *      initialize the contract's state variables.
     */
    function initialize(LbdToken LBD_)
        public
        initializer
    {
        __Ownable_init();

        deviationThreshold = 0;
        rebaseLag = 1;
        minRebaseTimeIntervalSec = 1 days;
        rebaseWindowOffsetSec = 79200;  // 10PM UTC
        rebaseWindowLengthSec = 60 minutes;
        lastRebaseTimestampSec = 0;
        epoch = 0;

        LBD = LBD_;
    }

    /**
     * @return If the latest block timestamp is within the rebase time window it, returns true.
     *         Otherwise, returns false.
     */
    function inRebaseWindow() public view returns (bool) {
        return (
            now.mod(minRebaseTimeIntervalSec) >= rebaseWindowOffsetSec &&
            now.mod(minRebaseTimeIntervalSec) < (rebaseWindowOffsetSec.add(rebaseWindowLengthSec))
        );
    }

    /**
     * @return Computes the total supply adjustment in response to the exchange rate
     *         and the targetRate.
     */
    function computeSupplyDelta(uint256 rate, uint256 targetRate)
        private
        view
        returns (int256)
    {
        if (withinDeviationThreshold(rate, targetRate)) {
            return 0;
        }

        // supplyDelta = totalSupply * (rate - targetRate) / targetRate
        int256 targetRateSigned = targetRate.toInt256Safe();
        return LBD.totalSupply().toInt256Safe()
            .mul(rate.toInt256Safe().sub(targetRateSigned))
            .div(targetRateSigned);
    }

    /**
     * @param rate The current exchange rate, an 18 decimal fixed point number.
     * @param targetRate The target exchange rate, an 18 decimal fixed point number.
     * @return If the rate is within the deviation threshold from the target rate, returns true.
     *         Otherwise, returns false.
     */
    function withinDeviationThreshold(uint256 rate, uint256 targetRate)
        private
        view
        returns (bool)
    {
        if (deviationThreshold == 0) {
            return false;
        }

        uint256 absoluteDeviationThreshold = targetRate.mul(deviationThreshold).div(10 ** DECIMALS);

        return (rate >= targetRate && rate.sub(targetRate) < absoluteDeviationThreshold)
            || (rate < targetRate && targetRate.sub(rate) < absoluteDeviationThreshold);
    }

    function getLinkMarketCapUSD(
        uint linkPrice
    )
    public
    view
    returns (uint)
    {
        uint totalSupply = linkToken.totalSupply();
        uint decimalsLink = IERC20Decimals(address(linkToken)).decimals();
        uint linkPrecision = 10**8;
        // Returns market cap of link tokens in WEI
        return totalSupply.mul(linkPrice).mul(10**DECIMALS).div(10**decimalsLink).div(linkPrecision);
    }

    function getTokenPriceFromUniswap()
    public
    view
    returns (uint)
    {
        uint[] memory amountsOut = new uint[](2);
        address[] memory path = new address[](2);

        path[0] = address(LBD);
        path[1] = address(usdt);

        amountsOut = IUniswapV2Router02(uniswapRouter).getAmountsOut(
            10**9,
            path
        );

        // Returns how much 1 BASE is worth USDT
        return amountsOut[1];
    }
}
