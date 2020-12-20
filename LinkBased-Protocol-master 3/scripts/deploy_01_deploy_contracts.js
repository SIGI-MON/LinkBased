const bre = require('hardhat')
const { ethers, upgrades } = bre
const { getSavedContractAddresses, saveContractAddress } = require('./utils')

async function main() {
    await bre.run('compile')

    const Oracle = await ethers.getContractFactory('Oracle')
    const oracle = await upgrades.deployProxy(Oracle, [])
    await oracle.deployed()
    console.log('Link price oracle deployed to:', oracle.address)
    saveContractAddress(bre.network.name, 'linkOracle', oracle.address);

    const LbdToken = await ethers.getContractFactory('LbdToken')
    const lbdToken = await upgrades.deployProxy(LbdToken, [])
    await lbdToken.deployed()
    console.log('LbdToken deployed to:', lbdToken.address)
    saveContractAddress(bre.network.name, 'lbdToken', lbdToken.address)

    const LbdTokenMonetaryPolicy = await ethers.getContractFactory('LbdTokenMonetaryPolicy')
    const lbdTokenMonetaryPolicy = await upgrades.deployProxy(LbdTokenMonetaryPolicy, [lbdToken.address])
    await lbdTokenMonetaryPolicy.deployed()
    console.log('LbdTokenMonetaryPolicy deployed to:', lbdTokenMonetaryPolicy.address)
    saveContractAddress(bre.network.name, 'lbdTokenMonetaryPolicy', lbdTokenMonetaryPolicy.address)

    const LbdTokenOrchestrator = await ethers.getContractFactory('LbdTokenOrchestrator')
    const lbdTokenOrchestrator = await upgrades.deployProxy(LbdTokenOrchestrator, [lbdTokenMonetaryPolicy.address])
    await lbdTokenOrchestrator.deployed()
    console.log('LbdTokenOrchestrator deployed to:', lbdTokenOrchestrator.address)
    saveContractAddress(bre.network.name, 'lbdTokenOrchestrator', lbdTokenOrchestrator.address)

    const Cascade = await ethers.getContractFactory('Cascade')
    const cascade = await upgrades.deployProxy(Cascade, [])
    await cascade.deployed()
    console.log('Cascade deployed to:', cascade.address)

    saveContractAddress(bre.network.name, 'cascade', cascade.address)

    await (await lbdToken.setMonetaryPolicy(lbdTokenMonetaryPolicy.address)).wait()
    console.log('LbdToken.setMonetaryPolicy(', lbdTokenMonetaryPolicy.address, ') succeeded')


    await (await lbdTokenMonetaryPolicy.setOrchestrator(lbdTokenOrchestrator.address)).wait()
    console.log('LbdTokenMonetaryPolicy.setOrchestrator(', lbdTokenOrchestrator.address, ') succeeded')

    const contracts = getSavedContractAddresses()[bre.network.name]

    await (await oracle.setExternalOracle(contracts.linkExternalOracle)).wait()
    console.log('oracle.setExternalOracle(', contracts.linkExternalOracle, ')')

    await (await lbdTokenMonetaryPolicy.setLinkOracle(contracts.linkOracle)).wait()
    console.log('LbdTokenMonetaryPolicy.setLinkOracle(', contracts.linkOracle, ') succeeded')

    await (await lbdTokenMonetaryPolicy.setLinkToken(contracts.linkToken)).wait()
    console.log('LbdTokenMonetaryPolicy.setLinkToken(', contracts.linkToken, ') succeeded')

    await (await lbdTokenMonetaryPolicy.setUniswapRouter(contracts.uniswapRouter)).wait()
    console.log('LbdTokenMonetaryPolicy.setUniswapRouter(', contracts.uniswapRouter, ') succeeded')

    await (await lbdTokenMonetaryPolicy.setUsdtToken(contracts.USDT)).wait()
    console.log('LbdTokenMonetaryPolicy.setUsdtToken(', contracts.USDT, ') succeeded');

    await (await cascade.setLPToken(contracts.lpToken)).wait()
    console.log('Cascade.setLPToken(', contracts.lpToken, ') succeeded')

    await (await cascade.setLBDToken(contracts.lbdToken)).wait()
    console.log('Cascade.setLBDToken(', contracts.lbdToken, ') succeeded')
}


main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error)
    process.exit(1)
  })
