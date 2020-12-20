const { ethers, web3, upgrades, expect, BigNumber, isEthException, awaitTx, waitForSomeTime, currentTime, toLBDDenomination, DECIMALS } = require('../setup')

const INTIAL_SUPPLY = toLBDDenomination(50 * 10 ** 6)
const transferAmount = toLBDDenomination(10)
const unitTokenAmount = toLBDDenomination(1)
const ZERO_ADDRESS = '0x0000000000000000000000000000000000000000'

let lbdToken, b, r, deployer, deployerAddr, user, userAddr, initialSupply, accounts, provider
async function setupContracts() {
    accounts = await ethers.getSigners()
    ;([ deployer, user ] = accounts)
    deployerAddr = await deployer.getAddress()
    userAddr = await user.getAddress()

    const LbdToken = await ethers.getContractFactory('LbdToken')
    lbdToken = await upgrades.deployProxy(LbdToken, [])
    await lbdToken.deployed()
    lbdToken = lbdToken.connect(deployer)
    initialSupply = await lbdToken.totalSupply()
}

describe('LbdToken', () => {
    before('setup LbdToken contract', setupContracts);

    it('should reject any ether sent to it', async () => {
        const asdf = await isEthException(user.sendTransaction({ to: lbdToken.address, value: 1 }));
        expect(
            asdf
        ).to.be.true;
    });
});

describe('LbdToken:Initialization', () => {
    before('setup LbdToken contract', setupContracts)

    it('should transfer 50M LBD to the deployer', async () => {
        (await lbdToken.balanceOf(deployerAddr)).should.equal(INTIAL_SUPPLY)
    })

    it('should set the totalSupply to 50M', async () => {
        initialSupply.should.equal(INTIAL_SUPPLY)
    })

    it('should set the owner', async () => {
        expect(await lbdToken.owner()).to.equal(deployerAddr)
    })

    it('should set detailed ERC20 parameters', async () => {
        expect(await lbdToken.name()).to.equal('Lbd Protocol')
        expect(await lbdToken.symbol()).to.equal('LBD')
        expect(await lbdToken.decimals()).to.equal(DECIMALS)
    })

    it('should have 9 decimals', async () => {
        const decimals = await lbdToken.decimals()
        expect(decimals).to.equal(DECIMALS)
    })

    it('should have LBD symbol', async () => {
        const symbol = await lbdToken.symbol()
        expect(symbol).to.equal('LBD')
    })
})

describe('LbdToken:setMonetaryPolicy', () => {
    before('setup LbdToken contract', setupContracts)

    it('should set reference to policy contract', async () => {
        const policy = accounts[1]
        const policyAddr = await policy.getAddress()
        await lbdToken.setMonetaryPolicy(policyAddr)
        expect(await lbdToken.monetaryPolicy()).to.equal(policyAddr)
    })

    it('should emit policy updated event', async () => {
        const policy = accounts[1]
        const policyAddr = await policy.getAddress()
        const r = await awaitTx(lbdToken.setMonetaryPolicy(policyAddr))
        const log = r.events[0]
        expect(log).to.exist
        expect(log.event).to.equal('LogMonetaryPolicyUpdated')
        expect(log.args.monetaryPolicy).to.equal(policyAddr)
    })
})

describe('LbdToken:setMonetaryPolicy:accessControl', () => {
    before('setup LbdToken contract', setupContracts)

    it('should be callable by owner', async () => {
        const policy = accounts[1]
        const policyAddr = await policy.getAddress()
        expect(
            await isEthException(lbdToken.setMonetaryPolicy(policyAddr))
        ).to.be.false
    })
})

describe('LbdToken:setMonetaryPolicy:accessControl', () => {
    before('setup LbdToken contract', setupContracts)

    it('should NOT be callable by non-owner', async () => {
        const policy = accounts[1]
        const user = accounts[2]
        const policyAddr = await policy.getAddress()
        expect(
            await isEthException(lbdToken.connect(user).setMonetaryPolicy(policyAddr))
        ).to.be.true
    })
})

describe('LbdToken:Rebase:accessControl', () => {
    before('setup LbdToken contract', async () => {
        await setupContracts()
        await lbdToken.setMonetaryPolicy(userAddr)
    })

    it('should be callable by monetary policy', async () => {
        expect(
            await isEthException(lbdToken.connect(user).rebase(1, transferAmount))
        ).to.be.false
    })

    it('should not be callable by others', async () => {
        expect(
            await isEthException(lbdToken.rebase(1, transferAmount))
        ).to.be.true
    })
})

describe('LbdToken:Rebase:Expansion', () => {
    // Rebase +5M (10%), with starting balances A:750 and B:250.
    let A, B, policy
    const rebaseAmt = INTIAL_SUPPLY / 10

    before('setup LbdToken contract', async () => {
        await setupContracts()
        A = accounts[2]
        B = accounts[3]
        policy = accounts[1]
        const policyAddr = await policy.getAddress()
        await awaitTx(lbdToken.setMonetaryPolicy(policyAddr))
        await awaitTx(lbdToken.transfer(await A.getAddress(), toLBDDenomination(750)))
        await awaitTx(lbdToken.transfer(await B.getAddress(), toLBDDenomination(250)))
        r = await awaitTx(lbdToken.connect(policy).rebase(1, rebaseAmt))
    })

    it('should increase the totalSupply', async () => {
        b = await lbdToken.totalSupply()
        expect(b).to.equal(initialSupply.add(rebaseAmt))
    })

    it('should emit Rebase', async () => {
        const log = r.events[0]
        expect(log).to.exist
        expect(log.event).to.equal('LogRebase')
        expect(log.args.epoch).to.equal(1)
        expect(log.args.totalSupply).to.equal(initialSupply.add(rebaseAmt))
    })
})

describe('LbdToken:Rebase:Expansion', () => {
    const MAX_SUPPLY = BigNumber.from(2).pow(128).sub(1)
    let policy

    describe('when totalSupply is less than MAX_SUPPLY and expands beyond', () => {
        before('setup LbdToken contract', async () => {
            await setupContracts()
            policy = accounts[1]
            const policyAddr = await policy.getAddress()
            await awaitTx(lbdToken.setMonetaryPolicy(policyAddr))
            const totalSupply = await lbdToken.totalSupply()
            await awaitTx(lbdToken.connect(policy).rebase(1, MAX_SUPPLY.sub(totalSupply).sub(toLBDDenomination(1))))
            r = await awaitTx(lbdToken.connect(policy).rebase(2, toLBDDenomination(2)))
        })

        it('should increase the totalSupply to MAX_SUPPLY', async () => {
            b = await lbdToken.totalSupply()
            expect(b).to.equal(MAX_SUPPLY)
        })

        it('should emit Rebase', async () => {
            const log = r.events[0]
            expect(log).to.exist
            expect(log.event).to.equal('LogRebase')
            expect(log.args.epoch.toNumber()).to.equal(2)
            expect(log.args.totalSupply).to.equal(MAX_SUPPLY)
        })
    })

    describe('when totalSupply is MAX_SUPPLY and expands', () => {
        before(async () => {
            b = await lbdToken.totalSupply()
            expect(b).to.equal(MAX_SUPPLY)
            r = await awaitTx(lbdToken.connect(policy).rebase(3, toLBDDenomination(2)))
        })

        it('should NOT change the totalSupply', async () => {
            b = await lbdToken.totalSupply()
            expect(b).to.equal(MAX_SUPPLY)
        })

        it('should emit Rebase', async () => {
            const log = r.events[0]
            expect(log).to.exist
            expect(log.event).to.equal('LogRebase')
            expect(log.args.epoch.toNumber()).to.equal(3)
            expect(log.args.totalSupply).to.equal(MAX_SUPPLY)
        })
    })
})

describe('LbdToken:Rebase:NoChange', () => {
    // Rebase (0%), with starting balances A:750 and B:250.
    let A, B, policy

    before('setup LbdToken contract', async () => {
        await setupContracts()
        A = accounts[2]
        B = accounts[3]
        policy = accounts[1]
        const policyAddr = await policy.getAddress()
        await awaitTx(lbdToken.setMonetaryPolicy(policyAddr))
        await awaitTx(lbdToken.transfer(await A.getAddress(), toLBDDenomination(750)))
        await awaitTx(lbdToken.transfer(await B.getAddress(), toLBDDenomination(250)))
        r = await awaitTx(lbdToken.connect(policy).rebase(1, 0))
    })

    it('should NOT CHANGE the totalSupply', async () => {
        b = await lbdToken.totalSupply()
        expect(b).to.equal(initialSupply)
    })


    it('should emit Rebase', async () => {
        const log = r.events[0]
        expect(log).to.exist
        expect(log.event).to.equal('LogRebase')
        expect(log.args.epoch).to.equal(1)
        expect(log.args.totalSupply).to.equal(initialSupply)
    })
})

describe('LbdToken:Rebase:Contraction', () => {
    // Rebase -5M (-10%), with starting balances A:750 and B:250.
    const rebaseAmt = INTIAL_SUPPLY / 10
    let A, B, policy

    before('setup LbdToken contract', async () => {
        await setupContracts()
        A = accounts[2]
        B = accounts[3]
        policy = accounts[1]
        const policyAddr = await policy.getAddress()
        await awaitTx(lbdToken.setMonetaryPolicy(policyAddr))
        await awaitTx(lbdToken.transfer(await A.getAddress(), toLBDDenomination(750)))
        await awaitTx(lbdToken.transfer(await B.getAddress(), toLBDDenomination(250)))
        r = await awaitTx(lbdToken.connect(policy).rebase(1, -rebaseAmt))
    })

    it('should decrease the totalSupply', async () => {
        b = await lbdToken.totalSupply()
        expect(b).to.equal(initialSupply.sub(rebaseAmt))
    })


    it('should emit Rebase', async () => {
        const log = r.events[0]
        expect(log).to.exist
        expect(log.event).to.equal('LogRebase')
        expect(log.args.epoch).to.equal(1)
        expect(log.args.totalSupply).to.equal(initialSupply.sub(rebaseAmt))
    })
})

describe('LbdToken:Transfer', () => {
    let A, B, C

    before('setup LbdToken contract', async () => {
        await setupContracts()
        A = accounts[2]
        B = accounts[3]
        C = accounts[4]
    })

    describe('deployer transfers 12 to A', () => {
        it('should have correct balances', async () => {
            const deployerBefore = await lbdToken.balanceOf(await deployer.getAddress())
            await awaitTx(lbdToken.transfer(await A.getAddress(), toLBDDenomination(12)))
            b = await lbdToken.balanceOf(await deployer.getAddress())
            expect(b).to.equal(deployerBefore.sub(toLBDDenomination(12)))
            b = await lbdToken.balanceOf(await A.getAddress())
            expect(b).to.equal(toLBDDenomination(12))
        })
    })

    describe('deployer transfers 15 to B', async () => {
        it('should have balances [973,15]', async () => {
            const deployerBefore = await lbdToken.balanceOf(await deployer.getAddress())
            await awaitTx(lbdToken.transfer(await B.getAddress(), toLBDDenomination(15)))
            b = await lbdToken.balanceOf(await deployer.getAddress())
            expect(b).to.equal(deployerBefore.sub(toLBDDenomination(15)))
            b = await lbdToken.balanceOf(await B.getAddress())
            expect(b).to.equal(toLBDDenomination(15))
        })
    })

    describe('deployer transfers the rest to C', async () => {
        it('should have balances [0,973]', async () => {
            const deployerBefore = await lbdToken.balanceOf(await deployer.getAddress())
            await awaitTx(lbdToken.transfer(await C.getAddress(), deployerBefore))
            b = await lbdToken.balanceOf(await deployer.getAddress())
            expect(b).to.equal(0)
            b = await lbdToken.balanceOf(await C.getAddress())
            expect(b).to.equal(deployerBefore)
        })
    })

    describe('when the recipient address is the contract address', async () => {
        it('reverts on transfer', async () => {
            const owner = A
            expect(
                await isEthException(lbdToken.connect(owner).transfer(lbdToken.address, unitTokenAmount))
            ).to.be.true
        })

        it('reverts on transferFrom', async () => {
            const owner = A
            expect(
                await isEthException(lbdToken.connect(owner).transferFrom(await owner.getAddress(), lbdToken.address, unitTokenAmount))
            ).to.be.true
        })
    })

    describe('when the recipient is the zero address', () => {
        before(async () => {
            const owner = A
            r = await awaitTx(lbdToken.connect(owner).approve(ZERO_ADDRESS, transferAmount))
        })

        it('emits an approval event', async () => {
            const owner = A
            expect(r.events.length).to.equal(1)
            expect(r.events[0].event).to.equal('Approval')
            expect(r.events[0].args.owner).to.equal(await owner.getAddress())
            expect(r.events[0].args.spender).to.equal(ZERO_ADDRESS)
            expect(r.events[0].args.value).to.equal(transferAmount)
        })

        it('transferFrom should fail', async () => {
            const owner = A
            expect(
                await isEthException(lbdToken.connect(C).transferFrom(await owner.getAddress(), ZERO_ADDRESS, transferAmount))
            ).to.be.true
        })
    })
})
