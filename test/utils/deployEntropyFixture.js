const { ethers } = require("hardhat");

const DEFAULT_FEE = 100n;

async function deployEntropyFixture() {
  const [owner, alice, bob, attacker] = await ethers.getSigners();

  // Standalone IEntropyV2 mock with a configurable fee. Pyth's stock MockEntropy
  // hardcodes getFeeV2 to a `pure` 0, so we use this harness instead.
  const MockEntropyWithFee = await ethers.getContractFactory("MockEntropyWithFee");
  const mockEntropy = await MockEntropyWithFee.deploy(owner.address, DEFAULT_FEE);
  await mockEntropy.waitForDeployment();

  // Deploy MockEntropyConsumer with owner as provider (matches mock's defaultProvider)
  // and owner as the DEFAULT_ADMIN_ROLE holder (EntropyConsumerBase 3rd ctor arg).
  const MockEntropyConsumer = await ethers.getContractFactory("MockEntropyConsumer");
  const consumer = await MockEntropyConsumer.deploy(
    await mockEntropy.getAddress(),
    owner.address,
    owner.address
  );
  await consumer.waitForDeployment();

  return { mockEntropy, consumer, owner, alice, bob, attacker, DEFAULT_FEE };
}

module.exports = { deployEntropyFixture, DEFAULT_FEE };
