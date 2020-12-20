pragma solidity 0.6.12;

import "@openzeppelin/contracts-ethereum-package/contracts/access/Ownable.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/Initializable.sol";

interface IOracle {
    function latestAnswer() external returns (uint256);
}

contract Oracle is OwnableUpgradeSafe {
    IOracle public externalOracle;

    function initialize()
        public
        initializer
    {
        __Ownable_init();
    }

    function setExternalOracle(address _externalOracle)
        public
        onlyOwner
    {
        externalOracle = IOracle(_externalOracle);
    }

    function getData()
        public
        returns (uint256, bool)
    {
        uint256 answer = externalOracle.latestAnswer();
        return (answer, true);
    }
}
