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

    it("reverts ErrorRefundFailed when requester rejects ETH", async function () {
      const { consumer, alice } = await loadFixture(deployEntropyFixture);
      const Rejector = await ethers.getContractFactory("RejectingReceiver");
      const rejector = await Rejector.deploy();
      await rejector.waitForDeployment();
      const overpay = FEE + 1n;
      // alice sends overpay; refund target is the rejector contract → refund fails
      await expect(
        consumer.connect(alice).requestRandomness(
          1n,
          await rejector.getAddress(),
          1,
          RANDOM,
          { value: overpay }
        )
      ).to.be.revertedWithCustomError(consumer, "ErrorRefundFailed");
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

  describe("retryRequest", function () {
    const NEW_RANDOM = "0x" + "33".repeat(32);
    const FAR_DEADLINE = 9999999999n;

    async function submit(consumer, alice) {
      await consumer.connect(alice).requestRandomness(5n, alice.address, 2, RANDOM, { value: FEE });
      return 1n; // first seq from MockEntropyWithFee is 1 (verified in Task 3)
    }

    async function fastForward(seconds) {
      await ethers.provider.send("evm_increaseTime", [seconds]);
      await ethers.provider.send("evm_mine");
    }

    it("retries successfully after timeout", async function () {
      const { consumer, alice } = await loadFixture(deployEntropyFixture);
      const oldSeq = await submit(consumer, alice);
      await fastForward(3601);

      const tx = consumer.connect(alice).retryRequest(oldSeq, NEW_RANDOM, FAR_DEADLINE, { value: FEE });
      // newSeq should be 2 (incremented from 1)
      await expect(tx).to.emit(consumer, "RequestRetried").withArgs(oldSeq, 2n, alice.address, FEE, FEE);

      expect((await consumer.getRequest(oldSeq)).exists).to.equal(false);
      const newReq = await consumer.getRequest(2n);
      expect(newReq.exists).to.equal(true);
      expect(newReq.tokenId).to.equal(5n);
      expect(newReq.itemCount).to.equal(2);
      expect(newReq.requester).to.equal(alice.address);
    });

    it("reverts ErrorRetryNotAllowed before timeout if not CALLBACK_FAILED", async function () {
      const { consumer, alice } = await loadFixture(deployEntropyFixture);
      const oldSeq = await submit(consumer, alice);
      await expect(
        consumer.connect(alice).retryRequest(oldSeq, NEW_RANDOM, FAR_DEADLINE, { value: FEE })
      ).to.be.revertedWithCustomError(consumer, "ErrorRetryNotAllowed");
    });

    it("retries on CALLBACK_FAILED before timeout", async function () {
      const { consumer, mockEntropy, alice } = await loadFixture(deployEntropyFixture);
      const oldSeq = await submit(consumer, alice);
      // Mark CALLBACK_FAILED on the harness for this seq, no time passing
      await mockEntropy.markCallbackFailed(oldSeq);

      const tx = consumer.connect(alice).retryRequest(oldSeq, NEW_RANDOM, FAR_DEADLINE, { value: FEE });
      await expect(tx).to.emit(consumer, "RequestRetried");

      expect((await consumer.getRequest(oldSeq)).exists).to.equal(false);
      expect((await consumer.getRequest(2n)).exists).to.equal(true);
    });

    it("reverts ErrorRequestNotFound for unknown seq", async function () {
      const { consumer, alice } = await loadFixture(deployEntropyFixture);
      await expect(
        consumer.connect(alice).retryRequest(999n, NEW_RANDOM, FAR_DEADLINE, { value: FEE })
      ).to.be.revertedWithCustomError(consumer, "ErrorRequestNotFound");
    });

    it("reverts ErrorNotRequester for non-original requester", async function () {
      const { consumer, alice, bob } = await loadFixture(deployEntropyFixture);
      const oldSeq = await submit(consumer, alice);
      await fastForward(3601);
      await expect(
        consumer.connect(bob).retryRequest(oldSeq, NEW_RANDOM, FAR_DEADLINE, { value: FEE })
      ).to.be.revertedWithCustomError(consumer, "ErrorNotRequester");
    });

    it("reverts ErrorInvalidUserRandom for zero random", async function () {
      const { consumer, alice } = await loadFixture(deployEntropyFixture);
      const oldSeq = await submit(consumer, alice);
      await fastForward(3601);
      await expect(
        consumer.connect(alice).retryRequest(oldSeq, ethers.ZeroHash, FAR_DEADLINE, { value: FEE })
      ).to.be.revertedWithCustomError(consumer, "ErrorInvalidUserRandom");
    });

    it("reverts ErrorInsufficientEntropyFee when msg.value < fee", async function () {
      const { consumer, alice } = await loadFixture(deployEntropyFixture);
      const oldSeq = await submit(consumer, alice);
      await fastForward(3601);
      await expect(
        consumer.connect(alice).retryRequest(oldSeq, NEW_RANDOM, FAR_DEADLINE, { value: 50n })
      ).to.be.revertedWithCustomError(consumer, "ErrorInsufficientEntropyFee");
    });

    it("propagates _beforeRetry revert", async function () {
      const { consumer, alice } = await loadFixture(deployEntropyFixture);
      const oldSeq = await submit(consumer, alice);
      await fastForward(3601);
      await consumer.setRevertOnBeforeRetry(true);
      await expect(
        consumer.connect(alice).retryRequest(oldSeq, NEW_RANDOM, FAR_DEADLINE, { value: FEE })
      ).to.be.revertedWith("before-retry-revert");
    });

    it("reverts on stale deadline", async function () {
      const { consumer, alice } = await loadFixture(deployEntropyFixture);
      const oldSeq = await submit(consumer, alice);
      await fastForward(3601);
      const past = (await ethers.provider.getBlock("latest")).timestamp - 1;
      await expect(
        consumer.connect(alice).retryRequest(oldSeq, NEW_RANDOM, past, { value: FEE })
      ).to.be.revertedWithCustomError(consumer, "DeadLineExpiredTransaction");
    });

    it("refunds excess msg.value to caller on retry", async function () {
      const { consumer, alice } = await loadFixture(deployEntropyFixture);
      const oldSeq = await submit(consumer, alice);
      await fastForward(3601);
      const before = await ethers.provider.getBalance(alice.address);
      const overpay = FEE + 999n;
      const tx = await consumer.connect(alice).retryRequest(oldSeq, NEW_RANDOM, FAR_DEADLINE, { value: overpay });
      const receipt = await tx.wait();
      const gasCost = receipt.gasUsed * receipt.gasPrice;
      const after = await ethers.provider.getBalance(alice.address);
      expect(before - after).to.equal(FEE + gasCost);
    });

    it("reverts ErrorRefundFailed when caller rejects ETH refund on retry", async function () {
      // Setup: deploy a rejector, submit a request from it (so it becomes requester),
      // fast-forward, retry from the rejector with overpay → refund target is rejector → revert.
      const { consumer } = await loadFixture(deployEntropyFixture);
      const Rejector = await ethers.getContractFactory("RejectingReceiverCaller");
      const caller = await Rejector.deploy(await consumer.getAddress());
      await caller.waitForDeployment();

      // Caller submits request; ETH forwarded directly (no receive() invocation)
      await caller.submitRequest(5n, RANDOM, { value: FEE });
      // first seq is 1
      await fastForward(3601);

      // Caller calls retryRequest; refund target is caller (msg.sender), but caller refuses ETH
      await expect(
        caller.retryRequestFromMe(1n, NEW_RANDOM, FAR_DEADLINE, { value: FEE + 1n })
      ).to.be.revertedWithCustomError(consumer, "ErrorRefundFailed");
    });

    it("invokes _postRetry hook with old + new seq after _request[newSeq] is written", async function () {
      const { consumer, alice } = await loadFixture(deployEntropyFixture);
      const oldSeq = await submit(consumer, alice);
      await fastForward(3601);
      await consumer.connect(alice).retryRequest(oldSeq, NEW_RANDOM, FAR_DEADLINE, { value: FEE });
      expect(await consumer.lastPostRetryOldSeq()).to.equal(oldSeq);
      expect(await consumer.lastPostRetryNewSeq()).to.equal(2n);
      // hook saw newSeq populated
      expect((await consumer.getRequest(2n)).tokenId).to.equal(5n);
    });
  });

  describe("governance setters", function () {
    it("setEntropyProvider: success + event + zero-address revert + non-admin revert", async function () {
      const { consumer, owner, alice, bob } = await loadFixture(deployEntropyFixture);
      const oldProvider = await consumer.entropyProvider();
      await expect(consumer.connect(owner).setEntropyProvider(bob.address))
        .to.emit(consumer, "EntropyProviderChanged").withArgs(oldProvider, bob.address);
      expect(await consumer.entropyProvider()).to.equal(bob.address);

      await expect(consumer.connect(owner).setEntropyProvider(ethers.ZeroAddress))
        .to.be.revertedWithCustomError(consumer, "ErrorZeroAddress");

      await expect(consumer.connect(alice).setEntropyProvider(bob.address))
        .to.be.revertedWithCustomError(consumer, "AccessControlUnauthorizedAccount");
    });

    it("setCallbackGasLimit: bounds [100_000, 2_000_000] + event + non-admin revert", async function () {
      const { consumer, owner, alice } = await loadFixture(deployEntropyFixture);
      await expect(consumer.connect(owner).setCallbackGasLimit(750_000))
        .to.emit(consumer, "CallbackGasLimitChanged").withArgs(500_000, 750_000);
      expect(await consumer.callbackGasLimit()).to.equal(750_000n);

      await expect(consumer.connect(owner).setCallbackGasLimit(99_999))
        .to.be.revertedWithCustomError(consumer, "ErrorInvalidCallbackGasLimit");
      await expect(consumer.connect(owner).setCallbackGasLimit(2_000_001))
        .to.be.revertedWithCustomError(consumer, "ErrorInvalidCallbackGasLimit");

      await expect(consumer.connect(alice).setCallbackGasLimit(750_000))
        .to.be.revertedWithCustomError(consumer, "AccessControlUnauthorizedAccount");
    });

    it("setEntropyTimeout: bounds [60s, 24h] + event + non-admin revert", async function () {
      const { consumer, owner, alice } = await loadFixture(deployEntropyFixture);
      await expect(consumer.connect(owner).setEntropyTimeout(7200))
        .to.emit(consumer, "EntropyTimeoutChanged").withArgs(3600, 7200);
      expect(await consumer.entropyTimeout()).to.equal(7200n);

      await expect(consumer.connect(owner).setEntropyTimeout(59))
        .to.be.revertedWithCustomError(consumer, "ErrorInvalidEntropyTimeout");
      await expect(consumer.connect(owner).setEntropyTimeout(24 * 3600 + 1))
        .to.be.revertedWithCustomError(consumer, "ErrorInvalidEntropyTimeout");

      await expect(consumer.connect(alice).setEntropyTimeout(7200))
        .to.be.revertedWithCustomError(consumer, "AccessControlUnauthorizedAccount");
    });
  });
});
