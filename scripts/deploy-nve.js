
require('dotenv').config()

async function main() {
  try {
    const [deployer] = await ethers.getSigners()
    console.log('Deploying contracts with the account:', deployer.address)
    console.log('Account balance:', (await deployer.getBalance()).toString())
    const NVEContract = await ethers.getContractFactory('NVE')
    const result = await NVEContract.deploy()
    console.log('Deployed address:', result.address)
  } catch (error) {
    console.log('Fail to deploy contract')
    console.log(error)
  }
}

main()
