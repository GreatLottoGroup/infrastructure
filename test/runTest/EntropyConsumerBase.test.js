const { expect } = require("chai");
const { loadFixture } = require("@nomicfoundation/hardhat-network-helpers");
const { ethers } = require("hardhat");
const { deployEntropyFixture, DEFAULT_FEE } = require("../utils/deployEntropyFixture");

describe("EntropyConsumerBase", function () {

  describe("deployment", function () {
    it("sets entropy address, provider, defaults", async function () {
      const { mockEntropy, consumer, owner } = await loadFixture(deployEntropyFixture);
      expect(await consumer.entropy()).to.equal(await mockEntropy.getAddress());
      expect(await consumer.entropyProvider()).to.equal(owner.address);
      expect(await consumer.callbackGasLimit()).to.equal(500_000n);
      expect(await consumer.entropyTimeout()).to.equal(3600n);
    });

    it("reverts on zero address in constructor", async function () {
      const Mock = await ethers.getContractFactory("MockEntropyConsumer");
      const ZERO = ethers.ZeroAddress;
      await expect(Mock.deploy(ZERO, ethers.Wallet.createRandom().address))
        .to.be.revertedWithCustomError(Mock, "ErrorZeroAddress");
      await expect(Mock.deploy(ethers.Wallet.createRandom().address, ZERO))
        .to.be.revertedWithCustomError(Mock, "ErrorZeroAddress");
    });

    it("entropyFee() returns the fee from MockEntropy", async function () {
      const { consumer } = await loadFixture(deployEntropyFixture);
      expect(await consumer.entropyFee()).to.equal(DEFAULT_FEE);
    });

    it("getRequest() returns empty Request for unknown seq", async function () {
      const { consumer } = await loadFixture(deployEntropyFixture);
      const req = await consumer.getRequest(999);
      expect(req.exists).to.equal(false);
      expect(req.tokenId).to.equal(0n);
    });
  });
});
