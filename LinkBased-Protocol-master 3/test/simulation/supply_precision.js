/*
    In this hardhat script,
    During every iteration:
    * We double the total LBD supply.
    * We test the following guarantee:
            - the difference in totalSupply() before and after the rebase(+1) should be exactly 1.

    USAGE:
    hardhat run ./test/simulation/supply_precision.js
*/

const { ethers, web3, upgrades, expect, BigNumber, isEthException, awaitTx, waitForSomeTime, currentTime, toLBDDenomination } = require('../setup')

const endSupply = BigNumber.from(2).pow(128).sub(1)

let lbdToken, preRebaseSupply, postRebaseSupply
preRebaseSupply = BigNumber.from(0)
postRebaseSupply = BigNumber.from(0)

async function exec() {
    const accounts = await ethers.getSigners()
    const deployer = accounts[0]
    const LbdToken = await ethers.getContractFactory('LbdToken')
    lbdToken = await upgrades.deployProxy(LbdToken, [])
    await lbdToken.deployed()
    lbdToken = lbdToken.connect(deployer)
    await awaitTx(lbdToken.setMonetaryPolicy(await deployer.getAddress()))

    let i = 0
    do {
        console.log('Iteration', i + 1)

        preRebaseSupply = await lbdToken.totalSupply()
        await awaitTx(lbdToken.rebase(2 * i, 1))
        postRebaseSupply = await lbdToken.totalSupply()
        console.log('Rebased by 1 LBD')
        console.log('Total supply is now', postRebaseSupply.toString(), 'LBD')

        console.log('Testing precision of supply')
        expect(postRebaseSupply.sub(preRebaseSupply).toNumber()).to.equal(1)

        console.log('Doubling supply')
        await awaitTx(lbdToken.rebase(2 * i + 1, postRebaseSupply))
        i++
    } while ((await lbdToken.totalSupply()).lt(endSupply))
}

exec()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error)
    process.exit(1)
  })

