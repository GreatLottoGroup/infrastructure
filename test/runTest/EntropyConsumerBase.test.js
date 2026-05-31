const { expect } = require("chai");
const { loadFixture } = require("@nomicfoundation/hardhat-network-helpers");
const { ethers } = require("hardhat");
const { deployEntropyFixture, DEFAULT_FEE } = require("../utils/deployEntropyFixture");

describe("EntropyConsumerBase", function () {
  const RANDOM = "0x" + "11".repeat(32);
  const PROVIDER_RANDOM = "0x" + "22".repeat(32);
  const FEE = 100n;

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

  describe("_requestRandomness", function () {
    it("submits request, writes _request, emits RequestSubmitted", async function () {
      const { consumer, alice } = await loadFixture(deployEntropyFixture);
      const tx = consumer.connect(alice).requestRandomness(
        42n, alice.address, 3, RANDOM, { value: FEE }
      );
      await expect(tx)
        .to.emit(consumer, "RequestSubmitted")
        .withArgs(1n /* first seq from MockEntropyWithFee starts at 1 */, alice.address, 42n, 3, FEE);

      const req = await consumer.getRequest(1n);
      expect(req.exists).to.equal(true);
      expect(req.tokenId).to.equal(42n);
      expect(req.requester).to.equal(alice.address);
      expect(req.itemCount).to.equal(3);
      expect(req.paidFee).to.equal(FEE);
    });

    it("reverts ErrorInvalidUserRandom when userRandom == 0", async function () {
      const { consumer, alice } = await loadFixture(deployEntropyFixture);
      const ZERO_RANDOM = ethers.ZeroHash;
      await expect(
        consumer.connect(alice).requestRandomness(1n, alice.address, 1, ZERO_RANDOM, { value: FEE })
      ).to.be.revertedWithCustomError(consumer, "ErrorInvalidUserRandom");
    });

    it("reverts ErrorInsufficientEntropyFee when paid < fee", async function () {
      const { consumer, alice } = await loadFixture(deployEntropyFixture);
      await expect(
        consumer.connect(alice).requestRandomness(1n, alice.address, 1, RANDOM, { value: 50n })
      ).to.be.revertedWithCustomError(consumer, "ErrorInsufficientEntropyFee").withArgs(FEE, 50n);
    });

    it("refunds excess paid to requester", async function () {
      const { consumer, alice } = await loadFixture(deployEntropyFixture);
      const before = await ethers.provider.getBalance(alice.address);
      const overpay = FEE + 999n;
      const tx = await consumer.connect(alice).requestRandomness(
        1n, alice.address, 1, RANDOM, { value: overpay }
      );
      const receipt = await tx.wait();
      const gasCost = receipt.gasUsed * receipt.gasPrice;
      const after = await ethers.provider.getBalance(alice.address);
      expect(before - after).to.equal(FEE + gasCost);
    });

    it("invokes _postRequest hook after _request write, before refund", async function () {
      const { consumer, alice } = await loadFixture(deployEntropyFixture);
      await consumer.connect(alice).requestRandomness(77n, alice.address, 1, RANDOM, { value: FEE });
      // hook recorded the seq → _request[seq] was already written when the hook fired
      expect(await consumer.lastPostRequestSeq()).to.equal(1n);
      expect((await consumer.getRequest(1n)).tokenId).to.equal(77n);
    });
  });

  describe("entropyCallback", function () {
    it("dispatches to _onRequestFulfilled, deletes _request, emits RequestFulfilled", async function () {
      const { consumer, mockEntropy, alice, owner } = await loadFixture(deployEntropyFixture);
      // Submit request first (becomes seq=1 in MockEntropyWithFee)
      await consumer.connect(alice).requestRandomness(7n, alice.address, 2, RANDOM, { value: FEE });
      // Trigger callback via the harness's mockReveal helper
      const tx = await mockEntropy.connect(owner).mockReveal(
        await consumer.getAddress(),         // requester (the consumer contract)
        1n,                                  // sequence number
        PROVIDER_RANDOM                      // randomNumber injected to callback
      );

      await expect(tx).to.emit(consumer, "RequestFulfilled").withArgs(1n, alice.address, 7n);

      // _request[seq] deleted
      const req = await consumer.getRequest(1n);
      expect(req.exists).to.equal(false);

      // mock subclass recorded the callback data
      expect(await consumer.lastSequence()).to.equal(1n);
      expect(await consumer.lastTokenId()).to.equal(7n);
      expect(await consumer.lastRequester()).to.equal(alice.address);
      expect(await consumer.lastItemCount()).to.equal(2);
      expect(await consumer.lastRandomNumber()).to.equal(PROVIDER_RANDOM);
    });

    it("silently returns when callback fires for non-existent seq", async function () {
      const { consumer, mockEntropy, alice, owner } = await loadFixture(deployEntropyFixture);

      // Submit a real request as control (seq=1)
      await consumer.connect(alice).requestRandomness(7n, alice.address, 1, RANDOM, { value: FEE });

      // Force-trigger callback for a never-requested seq=999.
      // Base's entropyCallback should silent-return because _request[999].exists == false.
      // Tx must succeed (no revert), no RequestFulfilled emitted.
      const tx = await mockEntropy.connect(owner).mockForceCallback(
        await consumer.getAddress(),
        999n,
        PROVIDER_RANDOM
      );
      const receipt = await tx.wait();

      // No RequestFulfilled event emitted for seq=999
      const requestFulfilledFilter = consumer.filters.RequestFulfilled(999n);
      const events = await consumer.queryFilter(requestFulfilledFilter, receipt.blockNumber, receipt.blockNumber);
      expect(events.length).to.equal(0);

      // Real request seq=1 untouched
      expect((await consumer.getRequest(1n)).exists).to.equal(true);

      // mock subclass not invoked (its lastSequence stays at default 0)
      expect(await consumer.lastSequence()).to.equal(0n);
    });

    it("reverts entire callback when _onRequestFulfilled reverts", async function () {
      const { consumer, mockEntropy, alice, owner } = await loadFixture(deployEntropyFixture);
      await consumer.setRevertOnFulfill(true);
      await consumer.connect(alice).requestRandomness(7n, alice.address, 1, RANDOM, { value: FEE });
      // Subclass _onRequestFulfilled will revert with "fulfill-revert".
      // mockReveal in the harness directly invokes _entropyCallback on the consumer,
      // and a revert in the consumer's callback should bubble up and fail the reveal tx.
      await expect(
        mockEntropy.connect(owner).mockReveal(await consumer.getAddress(), 1n, PROVIDER_RANDOM)
      ).to.be.revertedWith("fulfill-revert");

      // Because the callback reverted, _request[1] was NOT deleted (rollback)
      const req = await consumer.getRequest(1n);
      expect(req.exists).to.equal(true);
    });
  });
});
