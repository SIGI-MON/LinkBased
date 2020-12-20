const bre = require('hardhat')
const { ethers, upgrades } = bre
const { getSavedContractAddresses, saveContractAddress } = require('./utils')

async function main() {
    await bre.run('compile')

    const ERC20UpgradeSafe = await ethers.getContractFactory('ERC20UpgradeSafe')
    const lpToken = await upgrades.deployProxy(ERC20UpgradeSafe, [])
    await lpToken.deployed()
    console.log('LP token deployed to:', lpToken.address)
    saveContractAddress(bre.network.name, 'lpToken', lpToken.address)

    const MockTetherToken = await ethers.getContractFactory('MockTetherToken')
    const mockTetherToken = await MockTetherToken.deploy(1000000000000, "Tether Token", "USDT", 6);
    console.log('Mock tether token deployed to:', mockTetherToken.address)
    saveContractAddress(bre.network.name, 'USDT', mockTetherToken.address)
}


main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error)
    process.exit(1)
  })
