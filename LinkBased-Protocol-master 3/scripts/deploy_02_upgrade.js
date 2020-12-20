const bre = require('hardhat')
const { ethers, upgrades } = bre
const { getSavedContractAddresses, saveContractAddress } = require('./utils')

async function main() {
    await bre.run('compile')

    const contracts = getSavedContractAddresses()[bre.network.name]

    const LbdToken = await ethers.getContractFactory('LbdToken')
    const lbdToken = await upgrades.upgradeProxy(contracts.lbdToken, LbdToken)
    await lbdToken.deployed()
    console.log('LbdToken re-deployed to:', lbdToken.address)
    saveContractAddress(bre.network.name, 'lbdToken', lbdToken.address)
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error)
    process.exit(1)
  })
