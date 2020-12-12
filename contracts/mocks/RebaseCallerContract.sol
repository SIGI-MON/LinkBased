pragma solidity 0.6.12;

import "../LbdTokenOrchestrator.sol";


contract RebaseCallerContract {

    function callRebase(address orchestrator) public returns (bool) {
        // Take out a flash loan.
        // Do something funky...
        LbdTokenOrchestrator(orchestrator).rebase();  // should fail
        // pay back flash loan.
        return true;
    }
}
