require('@nomiclabs/hardhat-waffle')
require('@nomiclabs/hardhat-ethers')
require("@nomiclabs/hardhat-web3")
require('@openzeppelin/hardhat-upgrades')
require("@tenderly/hardhat-tenderly");

require('dotenv').config();


// This is a sample Buidler task. To learn how to create your own go to
// https://buidler.dev/guides/create-task.html
task('accounts', 'Prints the list of accounts', async () => {
  const accounts = await ethers.getSigners()

  for (const account of accounts) {
    console.log(await account.getAddress())
  }
})

// You have to export an object to set up your config
// This object can have the following optional entries:
// defaultNetwork, networks, solc, and paths.
// Go to https://buidler.dev/config/ to learn more
module.exports = {
  defaultNetwork: 'local',
  networks: {
    ropsten: {
      url: 'https://ropsten.infura.io/v3/34ee2e319e7945caa976d4d1e24db07f',
      accounts: [process.env.PK],
      chainId: 3,
      gasPrice: 40000000000,
      timeout: 50000
    },
    kovan: {
      url: 'https://kovan.tenderly.co',
      accounts: [process.env.PK],
      chainId: 42,
      gasPrice: 40000000000,
      timeout: 50000
    },
    mainnet: {
      url: 'https://mainnet.tenderly.co',
      accounts: [process.env.PK],
      chainId: 1,
      gasPrice: 25120000000,
      timeout: 500000
    },
    local: {
      url: 'http://localhost:8545',
    },
  },
  solidity: {
    version: '0.6.12',
  },
  paths: {
      tests: './test/unit',
  },
  tenderly: {
    project: process.env.PROJECT,
    username: process.env.USERNAME,
  }
}
