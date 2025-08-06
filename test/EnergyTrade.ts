import { expect } from "chai";
import { ethers } from "hardhat";
import { EnergyTrade, EnergyTrade__factory } from "../typechain-types";
import { Signer } from "ethers";

describe("EnergyTradeMatch", function () {
  let energyTrade: EnergyTrade;
  let owner: Signer;
  let addr1: Signer;
  let addr2: Signer;
  let addr3: Signer;
  let addr4: Signer;

  beforeEach(async function () {
    const bucketDuration = 900;
    [owner, addr1, addr2, addr3, addr4] = await ethers.getSigners();

    energyTrade = await (
      await new EnergyTrade__factory(owner).deploy(bucketDuration)
    ).waitForDeployment();
  });

  it("should set the deployer as the `contractOwner`", async function () {
    expect(await energyTrade.contractOwner()).to.equal(
      await owner.getAddress(),
    );
  });

  it("should set the current bucket status to Status.OPEN", async function () {
    expect(await energyTrade.bucketStatuses(0)).to.equal(0);
  });

  it("should fail placing a `bidRequest` with 0 `energyAmount`", async function () {
    const energyAmount = 0;
    const unitPrice = 1;
    const totalPrice = energyAmount * unitPrice;

    await expect(
      energyTrade
        .connect(addr1)
        .bidRequest(energyAmount, unitPrice, { value: totalPrice }),
    ).to.be.revertedWith("`_energyAmount` must be > 0.");
  });

  it("should fail placing a `bidRequest` with 0 `unitPrice`", async function () {
    const energyAmount = 1;
    const unitPrice = 0;
    const totalPrice = energyAmount * unitPrice;

    await expect(
      energyTrade
        .connect(addr1)
        .bidRequest(energyAmount, unitPrice, { value: totalPrice }),
    ).to.be.revertedWith("`_unitPrice` must be > 0.");
  });

  it("should fail placing a `bidRequest` with wrong value", async function () {
    const energyAmount = 1;
    const unitPrice = 1;
    const incorrectValue = 2;

    await expect(
      energyTrade.connect(addr1).bidRequest(energyAmount, unitPrice, {
        value: incorrectValue,
      }),
    ).to.be.revertedWith("Correct bid value must be included in bid request.");
  });

  it("should allow placing a valid `bidRequest`", async function () {
    const energyAmount = 1;
    const unitPrice = 1;
    const totalPrice = energyAmount * unitPrice;

    await energyTrade
      .connect(addr1)
      .bidRequest(energyAmount, unitPrice, { value: totalPrice });
    const bid = await energyTrade.bidBuckets(
      await energyTrade.currBucketID(),
      0,
    );

    expect(bid.traderAddr).to.equal(await addr1.getAddress());
    expect(bid.energyAmount).to.equal(energyAmount);
    expect(bid.unitPrice).to.equal(unitPrice);
  });

  it("should emit a `TradeReceived` event from a `bidRequest`", async function () {
    const energyAmount = 1;
    const unitPrice = 1;
    const totalPrice = energyAmount * unitPrice;

    await expect(
      energyTrade
        .connect(addr1)
        .bidRequest(energyAmount, unitPrice, { value: totalPrice }),
    )
      .to.emit(energyTrade, "TradeReceived")
      .withArgs(await addr1.getAddress(), 0, 0, 0, 1, 1);
  });

  it("should fail placing a `askRequest` with 0 `energyAmount`", async function () {
    const energyAmount = 0;
    const unitPrice = 1;

    await expect(
      energyTrade.connect(addr2).askRequest(energyAmount, unitPrice),
    ).to.be.revertedWith("`_energyAmount` must be > 0.");
  });

  it("should fail placing a `askRequest` with 0 `unitPrice`", async function () {
    const energyAmount = 1;
    const unitPrice = 0;

    await expect(
      energyTrade.connect(addr2).askRequest(energyAmount, unitPrice),
    ).to.be.revertedWith("`_unitPrice` must be > 0.");
  });

  it("should allow placing a valid `askRequest`", async function () {
    const energyAmount = 1;
    const unitPrice = 1;

    await energyTrade.connect(addr2).askRequest(energyAmount, unitPrice);
    const ask = await energyTrade.askBuckets(
      await energyTrade.currBucketID(),
      0,
    );

    expect(ask.traderAddr).to.equal(await addr2.getAddress());
    expect(ask.energyAmount).to.equal(energyAmount);
    expect(ask.unitPrice).to.equal(unitPrice);
  });

  it("should emit a `TradeReceived` event from an `askRequest`", async function () {
    const energyAmount = 1;
    const unitPrice = 1;

    await expect(energyTrade.connect(addr2).askRequest(energyAmount, unitPrice))
      .to.emit(energyTrade, "TradeReceived")
      .withArgs(await addr2.getAddress(), 0, 1, 0, 1, 1);
  });

  it("should allow the owner to close a bucket", async function () {
    await ethers.provider.send("evm_increaseTime", [900]);
    await ethers.provider.send("evm_mine", []);

    await energyTrade.connect(owner).rollBucket();
    expect(await energyTrade.bucketStatuses(0)).to.equal(1n);
  });

  it("should sort offers by `unitPrice` in ascending order", async function () {
    const addrs = [
      await addr1.getAddress(),
      await addr2.getAddress(),
      await owner.getAddress(),
    ];
    const amounts = [1, 1, 1];
    const prices = [3, 1, 2];
    const ordering1 = 0;
    const ordering2 = 0;

    expect(
      (
        await energyTrade.offerMergeSortTest(
          addrs,
          amounts,
          prices,
          ordering1,
          ordering2,
        )
      ).map((o: any) => o.unitPrice),
    ).to.deep.equal(prices.sort((a, b) => a - b));
  });

  it("should sort offers by `unitPrice` in descending order", async function () {
    const addrs = [
      await addr1.getAddress(),
      await addr2.getAddress(),
      await owner.getAddress(),
    ];
    const amounts = [1, 1, 1];
    const prices = [3, 1, 2];
    const ordering1 = 1;
    const ordering2 = 1;

    expect(
      (
        await energyTrade.offerMergeSortTest(
          addrs,
          amounts,
          prices,
          ordering1,
          ordering2,
        )
      ).map((o: any) => o.unitPrice),
    ).to.deep.equal(prices.sort((a, b) => b - a));
  });

  it("should sort offers by `energyAmount` in descending order", async function () {
    const addrs = [
      await addr1.getAddress(),
      await addr2.getAddress(),
      await owner.getAddress(),
    ];
    const amounts = [3, 1, 2];
    const prices = [1, 1, 1];
    const ordering1 = 1;
    const ordering2 = 1;

    expect(
      (
        await energyTrade.offerMergeSortTest(
          addrs,
          amounts,
          prices,
          ordering1,
          ordering2,
        )
      ).map((o: any) => o.unitPrice),
    ).to.deep.equal(prices.sort((a, b) => b - a));
  });

  it("should sort offers by `energyAmount` in ascending order", async function () {
    const addrs = [
      await addr1.getAddress(),
      await addr2.getAddress(),
      await owner.getAddress(),
    ];
    const amounts = [3, 1, 2];
    const prices = [1, 1, 1];
    const ordering1 = 0;
    const ordering2 = 0;

    expect(
      (
        await energyTrade.offerMergeSortTest(
          addrs,
          amounts,
          prices,
          ordering1,
          ordering2,
        )
      ).map((o: any) => o.unitPrice),
    ).to.deep.equal(prices.sort((a, b) => a - b));
  });

  it("should fail non-owners rolling a bucket", async function () {
    await expect(energyTrade.connect(addr1).rollBucket()).to.be.revertedWith(
      "Only contract owner can roll bucket.",
    );
  });

  it("should fail too soon rolling a bucket", async function () {
    await expect(energyTrade.connect(owner).rollBucket()).to.be.revertedWith(
      "Bucket must live at least `bucketDuration` long.",
    );
  });

  it("should set the previous bucket status to Status.CLOSED", async function () {
    await ethers.provider.send("evm_increaseTime", [900]);
    await ethers.provider.send("evm_mine", []);
    await energyTrade.connect(owner).rollBucket();

    expect(await energyTrade.bucketStatuses(0)).to.equal(1);
  });

  it("should set the new current bucket status to Status.OPEN", async function () {
    await ethers.provider.send("evm_increaseTime", [900]);
    await ethers.provider.send("evm_mine", []);
    await energyTrade.connect(owner).rollBucket();

    expect(await energyTrade.bucketStatuses(1)).to.equal(0);
  });

  it("should roll an empty bucket", async function () {
    await ethers.provider.send("evm_increaseTime", [900]);
    await ethers.provider.send("evm_mine", []);

    await energyTrade.connect(owner).rollBucket();
    const tradeCount = await energyTrade.getLastTradeBucketTradeCount();
    const clearingPrice = await energyTrade.getLastTradeBucketClearingPrice();

    expect(tradeCount).to.equal(0n);
    expect(clearingPrice).to.equal(0n);
  });

  it("should roll an empty bucket given one bid", async function () {
    const energyAmount = 1;
    const unitPrice = 1;
    const totalPrice = energyAmount * unitPrice;
    await energyTrade
      .connect(addr1)
      .bidRequest(energyAmount, unitPrice, { value: totalPrice });

    await ethers.provider.send("evm_increaseTime", [900]);
    await ethers.provider.send("evm_mine", []);

    await energyTrade.connect(owner).rollBucket();

    expect(await energyTrade.getLastTradeBucketTradeCount()).to.equal(0n);
    expect(await energyTrade.getLastTradeBucketClearingPrice()).to.equal(0n);
  });

  it("should roll an empty bucket given one ask", async function () {
    const energyAmount = 1;
    const unitPrice = 1;
    await energyTrade.connect(addr2).askRequest(energyAmount, unitPrice);

    await ethers.provider.send("evm_increaseTime", [900]);
    await ethers.provider.send("evm_mine", []);

    await energyTrade.connect(owner).rollBucket();

    expect(await energyTrade.getLastTradeBucketTradeCount()).to.equal(0n);
    expect(await energyTrade.getLastTradeBucketClearingPrice()).to.equal(0n);
  });

  it("should roll an empty bucket given mismatched bid and ask", async function () {
    const energyAmountBid = 1;
    const unitPriceBid = 1;
    const totalPrice = energyAmountBid * unitPriceBid;

    const energyAmountAsk = 1;
    const unitPriceAsk = 2;

    await energyTrade
      .connect(addr1)
      .bidRequest(energyAmountBid, unitPriceBid, { value: totalPrice });
    await energyTrade.connect(addr2).askRequest(energyAmountAsk, unitPriceAsk);

    await ethers.provider.send("evm_increaseTime", [900]);
    await ethers.provider.send("evm_mine", []);
    await energyTrade.connect(owner).rollBucket();

    expect(await energyTrade.getLastTradeBucketTradeCount()).to.equal(0n);
    expect(await energyTrade.getLastTradeBucketClearingPrice()).to.equal(0n);
  });

  it("should roll an empty bucket given lack of supply", async function () {
    const energyAmountBid = 2;
    const unitPriceBid = 1;
    const totalPrice = energyAmountBid * unitPriceBid;

    const energyAmountAsk = 1;
    const unitPriceAsk = 1;

    await energyTrade
      .connect(addr1)
      .bidRequest(energyAmountBid, unitPriceBid, { value: totalPrice });
    await energyTrade.connect(addr2).askRequest(energyAmountAsk, unitPriceAsk);

    await ethers.provider.send("evm_increaseTime", [900]);
    await ethers.provider.send("evm_mine", []);
    await energyTrade.connect(owner).rollBucket();

    expect(await energyTrade.getLastTradeBucketTradeCount()).to.equal(0n);
    expect(await energyTrade.getLastTradeBucketClearingPrice()).to.equal(0n);
  });

  it("should roll an empty bucket with one bid and two asks where the bid starts to match and then fails", async function () {
    const energyAmountBid = 2;
    const unitPriceBid = 2;
    const totalPrice = energyAmountBid * unitPriceBid;

    const energyAmountAsk1 = 1;
    const unitPriceAsk1 = 1;

    const energyAmountAsk2 = 1;
    const unitPriceAsk2 = 3;

    await energyTrade
      .connect(addr1)
      .bidRequest(energyAmountBid, unitPriceBid, { value: totalPrice });

    await energyTrade
      .connect(addr2)
      .askRequest(energyAmountAsk1, unitPriceAsk1);
    await energyTrade
      .connect(addr2)
      .askRequest(energyAmountAsk2, unitPriceAsk2);

    await ethers.provider.send("evm_increaseTime", [900]);
    await ethers.provider.send("evm_mine", []);
    await energyTrade.connect(owner).rollBucket();

    expect(await energyTrade.getLastTradeBucketTradeCount()).to.equal(0n);
    expect(await energyTrade.getLastTradeBucketClearingPrice()).to.equal(0n);
  });

  it("should roll a bucket with one match from one bid and ask", async function () {
    const energyAmountBid = 1;
    const unitPriceBid = 1;
    const totalPrice = energyAmountBid * unitPriceBid;

    const energyAmountAsk = 1;
    const unitPriceAsk = 1;

    await energyTrade
      .connect(addr1)
      .bidRequest(energyAmountBid, unitPriceBid, { value: totalPrice });
    await energyTrade.connect(addr2).askRequest(energyAmountAsk, unitPriceAsk);

    await ethers.provider.send("evm_increaseTime", [900]);
    await ethers.provider.send("evm_mine", []);

    await expect(energyTrade.connect(owner).rollBucket())
      .to.emit(energyTrade, "TradeMatched")
      .withArgs(
        await addr1.getAddress(),
        await addr2.getAddress(),
        0,
        0,
        1,
        1,
        false,
      );
    const [clearingPrice, tradeCount, energyAmounts, buyerAddrs, sellerAddrs] =
      await energyTrade.getLastTradeBucket();

    expect(clearingPrice).to.equal(1);
    expect(tradeCount).to.equal(1);
    expect(energyAmounts.length).to.equal(1);
    expect(energyAmounts[0]).to.equal(1);
    expect(buyerAddrs.length).to.equal(1);
    expect(buyerAddrs[0]).to.equal(await addr1.getAddress());
    expect(sellerAddrs.length).to.equal(1);
    expect(sellerAddrs[0]).to.equal(await addr2.getAddress());
  });

  it("should roll a bucket with one match from one bid and ask with the ask partially met", async function () {
    const energyAmountBid = 1;
    const unitPriceBid = 1;
    const totalPrice = energyAmountBid * unitPriceBid;

    const energyAmountAsk = 2;
    const unitPriceAsk = 1;

    await energyTrade
      .connect(addr1)
      .bidRequest(energyAmountBid, unitPriceBid, { value: totalPrice });
    await energyTrade.connect(addr2).askRequest(energyAmountAsk, unitPriceAsk);

    await ethers.provider.send("evm_increaseTime", [900]);
    await ethers.provider.send("evm_mine", []);

    await expect(energyTrade.connect(owner).rollBucket())
      .to.emit(energyTrade, "TradeMatched")
      .withArgs(
        await addr1.getAddress(),
        await addr2.getAddress(),
        0,
        0,
        1,
        1,
        false,
      );
    const [clearingPrice, tradeCount, energyAmounts, buyerAddrs, sellerAddrs] =
      await energyTrade.getLastTradeBucket();

    expect(clearingPrice).to.equal(1);
    expect(tradeCount).to.equal(1);
    expect(energyAmounts.length).to.equal(1);
    expect(energyAmounts[0]).to.equal(1);
    expect(buyerAddrs.length).to.equal(1);
    expect(buyerAddrs[0]).to.equal(await addr1.getAddress());
    expect(sellerAddrs.length).to.equal(1);
    expect(sellerAddrs[0]).to.equal(await addr2.getAddress());
  });

  it("should roll a bucket with one match from one bid and two asks", async function () {
    const energyAmountBid = 2;
    const unitPriceBid = 1;
    const totalPrice = energyAmountBid * unitPriceBid;

    const energyAmountAsk1 = 1;
    const unitPriceAsk1 = 1;

    const energyAmountAsk2 = 1;
    const unitPriceAsk2 = 1;

    await energyTrade
      .connect(addr1)
      .bidRequest(energyAmountBid, unitPriceBid, { value: totalPrice });
    await energyTrade
      .connect(addr2)
      .askRequest(energyAmountAsk1, unitPriceAsk1);
    await energyTrade
      .connect(addr3)
      .askRequest(energyAmountAsk2, unitPriceAsk2);

    await ethers.provider.send("evm_increaseTime", [900]);
    await ethers.provider.send("evm_mine", []);

    await energyTrade.connect(owner).rollBucket();
    const [clearingPrice, tradeCount, energyAmounts, buyerAddrs, sellerAddrs] =
      await energyTrade.getLastTradeBucket();

    expect(clearingPrice).to.equal(1);
    expect(tradeCount).to.equal(2);
    expect(energyAmounts.length).to.equal(2);
    expect(energyAmounts[0]).to.equal(1);
    expect(energyAmounts[1]).to.equal(1);
    expect(buyerAddrs.length).to.equal(2);
    expect(buyerAddrs[0]).to.equal(await addr1.getAddress());
    expect(buyerAddrs[1]).to.equal(await addr1.getAddress());
    expect(sellerAddrs.length).to.equal(2);
    expect(sellerAddrs[0]).to.equal(await addr2.getAddress());
    expect(sellerAddrs[1]).to.equal(await addr3.getAddress());
  });

  it("should roll a bucket with two matches from two bids and asks", async function () {
    const energyAmountBid = 1;
    const unitPriceBid = 1;
    const totalPrice = energyAmountBid * unitPriceBid;

    const energyAmountAsk = 1;
    const unitPriceAsk = 1;

    await energyTrade
      .connect(addr1)
      .bidRequest(energyAmountBid, unitPriceBid, { value: totalPrice });
    await energyTrade
      .connect(addr2)
      .bidRequest(energyAmountBid, unitPriceBid, { value: totalPrice });

    await energyTrade.connect(addr3).askRequest(energyAmountAsk, unitPriceAsk);
    await energyTrade.connect(addr4).askRequest(energyAmountAsk, unitPriceAsk);

    await ethers.provider.send("evm_increaseTime", [900]);
    await ethers.provider.send("evm_mine", []);

    await energyTrade.connect(owner).rollBucket();
    const [clearingPrice, tradeCount, energyAmounts, buyerAddrs, sellerAddrs] =
      await energyTrade.getLastTradeBucket();

    expect(clearingPrice).to.equal(1);
    expect(tradeCount).to.equal(2);
    expect(energyAmounts.length).to.equal(2);
    expect(energyAmounts[0]).to.equal(1);
    expect(energyAmounts[1]).to.equal(1);
    expect(buyerAddrs.length).to.equal(2);
    expect(buyerAddrs[0]).to.equal(await addr1.getAddress());
    expect(buyerAddrs[1]).to.equal(await addr2.getAddress());
    expect(sellerAddrs.length).to.equal(2);
    expect(sellerAddrs[0]).to.equal(await addr3.getAddress());
    expect(sellerAddrs[1]).to.equal(await addr4.getAddress());
  });

  it("should roll a bucket with two matches from two bids and one ask", async function () {
    const energyAmountBid = 1;
    const unitPriceBid = 1;
    const totalPrice = energyAmountBid * unitPriceBid;

    const energyAmountAsk = 2;
    const unitPriceAsk = 1;

    await energyTrade
      .connect(addr1)
      .bidRequest(energyAmountBid, unitPriceBid, { value: totalPrice });
    await energyTrade
      .connect(addr2)
      .bidRequest(energyAmountBid, unitPriceBid, { value: totalPrice });
    await energyTrade.connect(addr3).askRequest(energyAmountAsk, unitPriceAsk);

    await ethers.provider.send("evm_increaseTime", [900]);
    await ethers.provider.send("evm_mine", []);

    await energyTrade.connect(owner).rollBucket();
    const [clearingPrice, tradeCount, energyAmounts, buyerAddrs, sellerAddrs] =
      await energyTrade.getLastTradeBucket();

    expect(clearingPrice).to.equal(1);
    expect(tradeCount).to.equal(2);
    expect(energyAmounts.length).to.equal(2);
    expect(energyAmounts[0]).to.equal(1);
    expect(energyAmounts[1]).to.equal(1);
    expect(buyerAddrs.length).to.equal(2);
    expect(buyerAddrs[0]).to.equal(await addr1.getAddress());
    expect(buyerAddrs[1]).to.equal(await addr2.getAddress());
    expect(sellerAddrs.length).to.equal(2);
    expect(sellerAddrs[0]).to.equal(await addr3.getAddress());
    expect(sellerAddrs[1]).to.equal(await addr3.getAddress());
  });

  it("should roll a bucket with one match from two different bids and one ask", async function () {
    const energyAmountBid1 = 1;
    const unitPriceBid1 = 1;
    const totalPrice1 = energyAmountBid1 * unitPriceBid1;

    const energyAmountBid2 = 1;
    const unitPriceBid2 = 2;
    const totalPrice2 = energyAmountBid2 * unitPriceBid2;

    const energyAmountAsk = 1;
    const unitPriceAsk = 1;

    await energyTrade
      .connect(addr1)
      .bidRequest(energyAmountBid1, unitPriceBid1, { value: totalPrice1 });
    await energyTrade
      .connect(addr2)
      .bidRequest(energyAmountBid2, unitPriceBid2, { value: totalPrice2 });

    await energyTrade.connect(addr3).askRequest(energyAmountAsk, unitPriceAsk);

    await ethers.provider.send("evm_increaseTime", [900]);
    await ethers.provider.send("evm_mine", []);

    await expect(energyTrade.connect(owner).rollBucket())
      .to.emit(energyTrade, "TradeMatched")
      .withArgs(
        await addr2.getAddress(),
        await addr3.getAddress(),
        0,
        0,
        1,
        1,
        false,
      );
    const [clearingPrice, tradeCount, energyAmounts, buyerAddrs, sellerAddrs] =
      await energyTrade.getLastTradeBucket();

    expect(clearingPrice).to.equal(1);
    expect(tradeCount).to.equal(1);
    expect(energyAmounts.length).to.equal(1);
    expect(energyAmounts[0]).to.equal(1);
    expect(buyerAddrs.length).to.equal(1);
    expect(buyerAddrs[0]).to.equal(await addr2.getAddress());
    expect(sellerAddrs.length).to.equal(1);
    expect(sellerAddrs[0]).to.equal(await addr3.getAddress());
  });

  it("should roll a bucket with one match from one bid and two different asks", async function () {
    const energyAmountBid = 1;
    const unitPriceBid = 2;
    const totalPrice = energyAmountBid * unitPriceBid;

    const energyAmountAsk1 = 1;
    const unitPriceAsk1 = 2;

    const energyAmountAsk2 = 1;
    const unitPriceAsk2 = 1;

    await energyTrade
      .connect(addr1)
      .bidRequest(energyAmountBid, unitPriceBid, { value: totalPrice });
    await energyTrade
      .connect(addr2)
      .askRequest(energyAmountAsk1, unitPriceAsk1);
    await energyTrade
      .connect(addr3)
      .askRequest(energyAmountAsk2, unitPriceAsk2);

    await ethers.provider.send("evm_increaseTime", [900]);
    await ethers.provider.send("evm_mine", []);

    await expect(energyTrade.connect(owner).rollBucket())
      .to.emit(energyTrade, "TradeMatched")
      .withArgs(
        await addr1.getAddress(),
        await addr3.getAddress(),
        0,
        0,
        1,
        1,
        false,
      );
    const [clearingPrice, tradeCount, energyAmounts, buyerAddrs, sellerAddrs] =
      await energyTrade.getLastTradeBucket();

    expect(clearingPrice).to.equal(1);
    expect(tradeCount).to.equal(1);
    expect(energyAmounts.length).to.equal(1);
    expect(energyAmounts[0]).to.equal(1);
    expect(buyerAddrs.length).to.equal(1);
    expect(buyerAddrs[0]).to.equal(await addr1.getAddress());
    expect(sellerAddrs.length).to.equal(1);
    expect(sellerAddrs[0]).to.equal(await addr3.getAddress());
  });

  it("should roll a bucket with one match from two bids and one ask where the first bid cannot be met", async function () {
    const energyAmountBid1 = 2;
    const unitPriceBid1 = 2;
    const totalPrice1 = energyAmountBid1 * unitPriceBid1;

    const energyAmountBid2 = 1;
    const unitPriceBid2 = 1;
    const totalPrice2 = energyAmountBid2 * unitPriceBid2;

    const energyAmountAsk = 1;
    const unitPriceAsk = 1;

    await energyTrade
      .connect(addr1)
      .bidRequest(energyAmountBid1, unitPriceBid1, { value: totalPrice1 });
    await energyTrade
      .connect(addr2)
      .bidRequest(energyAmountBid2, unitPriceBid2, { value: totalPrice2 });
    await energyTrade.connect(addr3).askRequest(energyAmountAsk, unitPriceAsk);

    await ethers.provider.send("evm_increaseTime", [900]);
    await ethers.provider.send("evm_mine", []);

    await expect(energyTrade.connect(owner).rollBucket())
      .to.emit(energyTrade, "TradeMatched")
      .withArgs(
        await addr2.getAddress(),
        await addr3.getAddress(),
        0,
        0,
        1,
        1,
        false,
      );
    const [clearingPrice, tradeCount, energyAmounts, buyerAddrs, sellerAddrs] =
      await energyTrade.getLastTradeBucket();

    expect(clearingPrice).to.equal(1);
    expect(tradeCount).to.equal(1);
    expect(energyAmounts.length).to.equal(1);
    expect(energyAmounts[0]).to.equal(1);
    expect(buyerAddrs.length).to.equal(1);
    expect(buyerAddrs[0]).to.equal(await addr2.getAddress());
    expect(sellerAddrs.length).to.equal(1);
    expect(sellerAddrs[0]).to.equal(await addr3.getAddress());
  });

  it("should refund an unmet bid", async function () {
    const energyAmountBid = 1;
    const unitPriceBid = 1;
    const totalPrice = energyAmountBid * unitPriceBid;

    await energyTrade
      .connect(addr1)
      .bidRequest(energyAmountBid, unitPriceBid, { value: totalPrice });
    const traderMidBalance = await ethers.provider.getBalance(
      addr1.getAddress(),
    );

    await ethers.provider.send("evm_increaseTime", [900]);
    await ethers.provider.send("evm_mine", []);

    await energyTrade.connect(owner).rollBucket();
    const traderEndBalance = await ethers.provider.getBalance(
      addr1.getAddress(),
    );

    expect(traderEndBalance).to.be.above(traderMidBalance);
    expect(traderEndBalance - traderMidBalance).to.be.closeTo(
      totalPrice,
      ethers.parseEther("0.001"),
    );
  });

  it("should partially refund an overpaid bid", async function () {
    const energyAmountBid = 1;
    const unitPriceBid = 2;
    const totalPrice = energyAmountBid * unitPriceBid;

    const energyAmountAsk = 1;
    const unitPriceAsk = 1;

    await energyTrade
      .connect(addr1)
      .bidRequest(energyAmountBid, unitPriceBid, { value: totalPrice });
    await energyTrade.connect(addr2).askRequest(energyAmountAsk, unitPriceAsk);
    const traderMidBalance = await ethers.provider.getBalance(
      addr1.getAddress(),
    );

    await ethers.provider.send("evm_increaseTime", [900]);
    await ethers.provider.send("evm_mine", []);

    await energyTrade.connect(owner).rollBucket();
    const traderEndBalance = await ethers.provider.getBalance(
      addr1.getAddress(),
    );

    expect(traderEndBalance).to.be.above(traderMidBalance);
    expect(traderEndBalance - traderMidBalance).to.be.closeTo(
      totalPrice - 1,
      ethers.parseEther("0.001"),
    );
  });

  it("should emit a `TradeRejected` event due to an unmet bid", async function () {
    const energyAmountBid = 1;
    const unitPriceBid = 1;
    const totalPrice = energyAmountBid * unitPriceBid;

    await energyTrade
      .connect(addr1)
      .bidRequest(energyAmountBid, unitPriceBid, { value: totalPrice });

    await ethers.provider.send("evm_increaseTime", [900]);
    await ethers.provider.send("evm_mine", []);

    await expect(energyTrade.connect(owner).rollBucket())
      .to.emit(energyTrade, "TradeRejected")
      .withArgs(
        await addr1.getAddress(),
        0,
        0,
        0,
        1,
        "Bid rejected due to unmeetable demand at bid price.",
      );
  });

  it("should emit a `TradeRejected` event due to an unmet ask", async function () {
    const energyAmountBid = 1;
    const unitPriceBid = 1;

    await energyTrade.connect(addr1).askRequest(energyAmountBid, unitPriceBid);

    await ethers.provider.send("evm_increaseTime", [900]);
    await ethers.provider.send("evm_mine", []);

    await expect(energyTrade.connect(owner).rollBucket())
      .to.emit(energyTrade, "TradeRejected")
      .withArgs(
        await addr1.getAddress(),
        0,
        1,
        0,
        0,
        "Ask partially or fully rejected due to undemanded supply at ask price.",
      );
  });

  it("should not refund a successful match", async function () {
    const energyAmountBid = 1;
    const unitPriceBid = 1;
    const totalPrice = energyAmountBid * unitPriceBid;

    const energyAmountAsk = 1;
    const unitPriceAsk = 1;

    await energyTrade
      .connect(addr1)
      .bidRequest(energyAmountBid, unitPriceBid, { value: totalPrice });
    await energyTrade.connect(addr2).askRequest(energyAmountAsk, unitPriceAsk);
    const traderMidBalance = await ethers.provider.getBalance(
      addr1.getAddress(),
    );

    await ethers.provider.send("evm_increaseTime", [900]);
    await ethers.provider.send("evm_mine", []);

    await energyTrade.connect(owner).rollBucket();
    const traderEndBalance = await ethers.provider.getBalance(
      addr1.getAddress(),
    );

    expect(traderEndBalance).to.be.closeTo(
      traderMidBalance,
      ethers.parseEther("0.001"),
    );
  });

  it("should refund an unfulfilled trade", async function () {
    const energyAmountBid = 1;
    const unitPriceBid = 1;
    const totalPrice = energyAmountBid * unitPriceBid;

    const traderStartBalance = await ethers.provider.getBalance(
      addr1.getAddress(),
    );
    await energyTrade
      .connect(addr1)
      .bidRequest(energyAmountBid, unitPriceBid, { value: totalPrice });
    await energyTrade.connect(addr2).askRequest(energyAmountBid, unitPriceBid);

    await ethers.provider.send("evm_increaseTime", [900]);
    await ethers.provider.send("evm_mine", []);
    await energyTrade.connect(owner).rollBucket();

    await ethers.provider.send("evm_increaseTime", [900]);
    await ethers.provider.send("evm_mine", []);
    await energyTrade.connect(owner).rollBucket();

    expect(await ethers.provider.getBalance(addr1.getAddress())).to.be.closeTo(
      traderStartBalance,
      ethers.parseEther("0.001"),
    );
  });

  it("should set the old bucket status to Status.CLEARED", async function () {
    await ethers.provider.send("evm_increaseTime", [900]);
    await ethers.provider.send("evm_mine", []);
    await energyTrade.connect(owner).rollBucket();

    await ethers.provider.send("evm_increaseTime", [900]);
    await ethers.provider.send("evm_mine", []);
    await energyTrade.connect(owner).rollBucket();

    await ethers.provider.send("evm_increaseTime", [900]);
    await ethers.provider.send("evm_mine", []);
    await energyTrade.connect(owner).rollBucket();

    expect(await energyTrade.bucketStatuses(0)).to.equal(2);
  });

  it("should mark an old trade as cleared", async function () {
    const energyAmountBid = 1;
    const unitPriceBid = 1;
    const totalPrice = energyAmountBid * unitPriceBid;

    const traderStartBalance = await ethers.provider.getBalance(
      addr1.getAddress(),
    );

    await energyTrade
      .connect(addr1)
      .bidRequest(energyAmountBid, unitPriceBid, { value: totalPrice });
    await energyTrade.connect(addr2).askRequest(energyAmountBid, unitPriceBid);

    await ethers.provider.send("evm_increaseTime", [900]);
    await ethers.provider.send("evm_mine", []);
    await energyTrade.connect(owner).rollBucket();

    await ethers.provider.send("evm_increaseTime", [900]);
    await ethers.provider.send("evm_mine", []);
    await energyTrade.connect(owner).rollBucket();

    expect(await ethers.provider.getBalance(addr1.getAddress())).to.be.closeTo(
      traderStartBalance,
      ethers.parseEther("0.001"),
    );
  });

  it("should fail to mark energy as supplied due to invalid IDs", async function () {
    await expect(
      energyTrade.connect(addr1).markEnergySupplied(0, 1),
    ).to.be.revertedWith("`_tradeID` must be valid.");
  });

  it("should fail to mark energy as supplied due to wrong marker", async function () {
    const energyAmountBid = 1;
    const unitPriceBid = 1;
    const totalPrice = energyAmountBid * unitPriceBid;

    const energyAmountAsk = 1;
    const unitPriceAsk = 1;

    await energyTrade
      .connect(addr1)
      .bidRequest(energyAmountBid, unitPriceBid, { value: totalPrice });
    await energyTrade.connect(addr2).askRequest(energyAmountAsk, unitPriceAsk);

    await ethers.provider.send("evm_increaseTime", [900]);
    await ethers.provider.send("evm_mine", []);
    await energyTrade.connect(owner).rollBucket();

    await expect(
      energyTrade.connect(addr1).markEnergySupplied(0, 0),
    ).to.be.revertedWith("Only seller can mark energy supplied.");
  });

  it("should fail to mark energy as supplied due to energy already marked", async function () {
    const energyAmountBid = 1;
    const unitPriceBid = 1;
    const totalPrice = energyAmountBid * unitPriceBid;

    const energyAmountAsk = 1;
    const unitPriceAsk = 1;

    await energyTrade
      .connect(addr1)
      .bidRequest(energyAmountBid, unitPriceBid, { value: totalPrice });
    await energyTrade.connect(addr2).askRequest(energyAmountAsk, unitPriceAsk);

    await ethers.provider.send("evm_increaseTime", [900]);
    await ethers.provider.send("evm_mine", []);
    await energyTrade.connect(owner).rollBucket();

    await energyTrade.connect(addr2).markEnergySupplied(0, 0);
    await expect(
      energyTrade.connect(addr2).markEnergySupplied(0, 0),
    ).to.be.revertedWith("Energy cannot already be supplied.");
  });

  it("should mark energy as supplied", async function () {
    const energyAmountBid = 1;
    const unitPriceBid = 1;
    const totalPrice = energyAmountBid * unitPriceBid;

    const energyAmountAsk = 1;
    const unitPriceAsk = 1;

    await energyTrade
      .connect(addr1)
      .bidRequest(energyAmountBid, unitPriceBid, { value: totalPrice });
    await energyTrade.connect(addr2).askRequest(energyAmountAsk, unitPriceAsk);

    await ethers.provider.send("evm_increaseTime", [900]);
    await ethers.provider.send("evm_mine", []);
    await energyTrade.connect(owner).rollBucket();

    await expect(energyTrade.connect(addr2).markEnergySupplied(0, 0))
      .to.emit(energyTrade, "EnergySupplied")
      .withArgs(await addr2.getAddress(), await addr1.getAddress(), 0, 0, 1, 1);
  });

  it("should emit `EnergySupplied`", async function () {
    const energyAmountBid = 1;
    const unitPriceBid = 1;
    const totalPrice = energyAmountBid * unitPriceBid;

    const energyAmountAsk = 1;
    const unitPriceAsk = 1;

    await energyTrade
      .connect(addr1)
      .bidRequest(energyAmountBid, unitPriceBid, { value: totalPrice });
    await energyTrade.connect(addr2).askRequest(energyAmountAsk, unitPriceAsk);

    await ethers.provider.send("evm_increaseTime", [900]);
    await ethers.provider.send("evm_mine", []);
    await energyTrade.connect(owner).rollBucket();

    await expect(energyTrade.connect(addr2).markEnergySupplied(0, 0))
      .to.emit(energyTrade, "EnergySupplied")
      .withArgs(await addr2.getAddress(), await addr1.getAddress(), 0, 0, 1, 1);
  });
});
