const hre = require("hardhat");

const sleep = (delay) =>
  new Promise((resolve) => setTimeout(resolve, delay * 1000));

async function main() {
  const ethers = hre.ethers;

  console.log("network:", await ethers.provider.getNetwork());

  const signer = (await ethers.getSigners())[0];
  console.log("signer:", await signer.getAddress());

  /**
   *  Deploy
   */
  const market = await ethers.getContractFactory("ApesMarket", {
    signer: (await ethers.getSigners())[0],
  });

  const contract = await market.deploy(
    "0xdD40dF4712BDF9c6FeFA9d0dD2AB7E90DeFb8273"
  );
  await contract.deployed();

  console.log("contract deployed to:", contract.address);

  await sleep(300);
  await hre.run("verify:verify", {
    address: contract.address,
    contract: "contracts/ApesMarket.sol:ApesMarket",
    constructorArguments: ["0xdD40dF4712BDF9c6FeFA9d0dD2AB7E90DeFb8273"],
  });

  console.log("contract verified");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
