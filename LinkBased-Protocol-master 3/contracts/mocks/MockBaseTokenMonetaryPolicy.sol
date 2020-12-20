pragma solidity 0.6.12;

import "./Mock.sol";


contract MockLbdTokenMonetaryPolicy is Mock {

    function rebase() external {
        emit FunctionCalled("LbdTokenMonetaryPolicy", "rebase", msg.sender);
    }
}
