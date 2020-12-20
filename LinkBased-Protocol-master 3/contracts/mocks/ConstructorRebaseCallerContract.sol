pragma solidity 0.6.12;

import "../LbdTokenOrchestrator.sol";


contract ConstructorRebaseCallerContract {
    constructor(address orchestrator) public {
        // Take out a flash loan.
        // Do something funky...
        LbdTokenOrchestrator(orchestrator).rebase();  // should fail
        // pay back flash loan.
    }
}
