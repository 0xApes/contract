const hre = require("hardhat");

const sleep = (delay) =>
  new Promise((resolve) => setTimeout(resolve, delay * 1000));

async function main() {
  const ethers = hre.ethers;

  console.log("network:", await ethers.provider.getNetwork());

  const signer = (await ethers.getSigners())[0];
  console.log("signer:", await signer.getAddress());

  /**
   *  Deploy Native Punks
   */
  const nativePunks = await ethers.getContractFactory("Apes", {
    signer: (await ethers.getSigners())[0],
  });

  const contract = await nativePunks.deploy();
  await contract.deployed();

  console.log("contract deployed to:", contract.address);

  await sleep(60);
  await hre.run("verify:verify", {
    address: contract.address,
    contract: "contracts/Apes.sol:Apes",
    constructorArguments: [],
  });

  console.log("contract verified");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
