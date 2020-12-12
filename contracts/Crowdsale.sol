pragma solidity ^0.6.12;

import "./OZ/SafeMath.sol";
import "./OZ/ReentrancyGuard.sol";
import "./OZ/IERC20.sol";
import "./OZ/Context.sol";


/**
 * Crowdsale contract.
 * @author Nikola Madjarevic
 * Github: madjarevicn
 */
contract Crowdsale is Context, ReentrancyGuard {

    using SafeMath for uint;

    // The token being sold
    IERC20 private _token;

    // Wallet receiving all the funds
    address payable _wallet;

    // How many token units a buyer gets per wei.
    // The rate is the conversion between wei and the smallest and indivisible token unit.
    uint private _rate;

    // Amount of wei raised
    uint private _weiRaised;


    /**
     * Event for token purchase logging
     * @param purchaser who paid for the tokens
     * @param beneficiary who got the tokens
     * @param value weis paid for purchase
     * @param amount amount of tokens purchased
     */
    event TokensPurchased(address indexed purchaser, address indexed beneficiary, uint256 value, uint256 amount);


    constructor(
        address token,
        uint rate,
        address payable wallet
    )
    public
    {
        require(address(token) != address(0), "Crowdsale: token is the zero address");
        require(rate > 0, "Crowdsale: rate is 0");
        require(wallet != address(0), "Crowdsale: Destination wallet is 0x");

        _token = IERC20(token);
        _rate = rate;
        _wallet = wallet;
    }



    /**
     * @return the token being sold.
     */
    function token()
    public
    view
    returns (address)
    {
        return address(_token);
    }


    /**
     * @return the number of token units a buyer gets per wei.
     */
    function rate()
    public
    view
    returns (uint)
    {
        return _rate;
    }


    /**
     * @return the amount of wei raised.
     */
    function weiRaised()
    public
    view
    returns (uint)
    {
        return _weiRaised;
    }


    /**
     * @dev low level token purchase ***DO NOT OVERRIDE***
     * This function has a non-reentrancy guard, so it shouldn't be called by
     * another `nonReentrant` function.
     * @param beneficiary Recipient of the token purchase
     */
    function buyTokens(
        address beneficiary
    )
    public
    nonReentrant
    payable
    {
        uint256 weiAmount = msg.value;
        _preValidatePurchase(beneficiary, weiAmount);

        // Calculate amount of tokens being bought
        uint256 tokens = _getTokenAmount(weiAmount);

        // update state
        _weiRaised = _weiRaised.add(weiAmount);

        // Process purchase, send tokens to beneficiary
        _processPurchase(beneficiary, tokens);

        // Emit event that tokens are being bought
        emit TokensPurchased(_msgSender(), beneficiary, weiAmount, tokens);

        // Forward funds to admin wallet
        _forwardFunds();
    }


    function withdrawUnsoldTokens()
    public
    {
        require(msg.sender == _wallet);

        uint balance = _token.balanceOf(address(this));
        _deliverTokens(
            _wallet,
            balance
        );
    }


    /**
     * @dev Validation of an incoming purchase. Use require statements to revert state when conditions are not met.
     * @param beneficiary Address performing the token purchase
     * @param weiAmount Value in wei involved in the purchase
     */
    function _preValidatePurchase(
        address beneficiary,
        uint256 weiAmount
    )
    internal
    view
    {
        require(beneficiary != address(0), "Crowdsale: beneficiary is the zero address");
        require(weiAmount != 0, "Crowdsale: weiAmount is 0");
        this; // silence state mutability warning without generating bytecode - see https://github.com/ethereum/solidity/issues/2691
    }


    /**
     * @dev Source of tokens. Override this method to modify the way in which the crowdsale ultimately gets and sends
     * its tokens.
     * @param beneficiary Address performing the token purchase
     * @param tokenAmount Number of tokens to be emitted
     */
    function _deliverTokens(address beneficiary, uint256 tokenAmount) internal {
        _token.transfer(beneficiary, tokenAmount);
    }


    /**
     * @dev Executed when a purchase has been validated and is ready to be executed. Doesn't necessarily emit/send
     * tokens.
     * @param beneficiary Address receiving the tokens
     * @param tokenAmount Number of tokens to be purchased
     */
    function _processPurchase(address beneficiary, uint256 tokenAmount) internal {
        _deliverTokens(beneficiary, tokenAmount);
    }


    /**
     * @dev Override to extend the way in which ether is converted to tokens.
     * @param weiAmount Value in wei to be converted into tokens
     * @return Number of tokens that can be purchased with the specified _weiAmount
     */
    function _getTokenAmount(
        uint256 weiAmount
    )
    internal
    view
    returns (uint256)
    {
        return weiAmount.mul(_rate);
    }


    /**
     * @dev Determines how ETH is stored/forwarded on purchases.
     */
    function _forwardFunds()
    internal
    {
        _wallet.transfer(msg.value);
    }

}
