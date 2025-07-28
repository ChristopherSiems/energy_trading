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
    const bucketDuration = 300;
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

  it("should allow the owner to close a bucket", async function () {
    await ethers.provider.send("evm_increaseTime", [300]);
    await ethers.provider.send("evm_mine", []);

    await energyTrade.connect(owner).rollBucket();
    expect(
      await energyTrade.bucketStatuses((await energyTrade.currBucketID()) - 1n),
    ).to.equal(1n);
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

  it("should delete old rolled bidBucket", async function () {
    await ethers.provider.send("evm_increaseTime", [300]);
    await ethers.provider.send("evm_mine", []);

    await energyTrade.connect(owner).rollBucket();
    await expect(energyTrade.bidBuckets(0, 0)).to.be.reverted;
  });

  it("should delete old rolled askBucket", async function () {
    await ethers.provider.send("evm_increaseTime", [300]);
    await ethers.provider.send("evm_mine", []);

    await energyTrade.connect(owner).rollBucket();
    await expect(energyTrade.askBuckets(0, 0)).to.be.reverted;
  });

  it("should roll an empty bucket", async function () {
    await ethers.provider.send("evm_increaseTime", [300]);
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

    await ethers.provider.send("evm_increaseTime", [300]);
    await ethers.provider.send("evm_mine", []);

    await energyTrade.connect(owner).rollBucket();
    const tradeCount = await energyTrade.getLastTradeBucketTradeCount();
    const clearingPrice = await energyTrade.getLastTradeBucketClearingPrice();

    expect(tradeCount).to.equal(0n);
    expect(clearingPrice).to.equal(0n);
  });

  it("should roll an empty bucket given one ask", async function () {
    const energyAmount = 1;
    const unitPrice = 1;
    await energyTrade.connect(addr2).askRequest(energyAmount, unitPrice);

    await ethers.provider.send("evm_increaseTime", [300]);
    await ethers.provider.send("evm_mine", []);

    await energyTrade.connect(owner).rollBucket();
    const tradeCount = await energyTrade.getLastTradeBucketTradeCount();
    const clearingPrice = await energyTrade.getLastTradeBucketClearingPrice();

    expect(tradeCount).to.equal(0n);
    expect(clearingPrice).to.equal(0n);
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

    await ethers.provider.send("evm_increaseTime", [300]);
    await ethers.provider.send("evm_mine", []);

    await energyTrade.connect(owner).rollBucket();
    const tradeCount = await energyTrade.getLastTradeBucketTradeCount();
    const clearingPrice = await energyTrade.getLastTradeBucketClearingPrice();

    expect(tradeCount).to.equal(0n);
    expect(clearingPrice).to.equal(0n);
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

    await ethers.provider.send("evm_increaseTime", [300]);
    await ethers.provider.send("evm_mine", []);

    await energyTrade.connect(owner).rollBucket();
    const tradeCount = await energyTrade.getLastTradeBucketTradeCount();
    const clearingPrice = await energyTrade.getLastTradeBucketClearingPrice();

    expect(tradeCount).to.equal(0n);
    expect(clearingPrice).to.equal(0n);
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

    await ethers.provider.send("evm_increaseTime", [300]);
    await ethers.provider.send("evm_mine", []);

    await energyTrade.connect(owner).rollBucket();
    const [clearingPrice, buyers, sellers, sellerAmounts] =
      await energyTrade.getLastTradeBucket();

    expect(buyers.length).to.equal(1);
    expect(sellers.length).to.equal(1);
    expect(sellerAmounts.length).to.equal(1);
    expect(sellers[0].length).to.equal(1);
    expect(sellerAmounts[0].length).to.equal(1);
    expect(buyers[0]).to.equal(await addr1.getAddress());
    expect(sellers[0][0]).to.equal(await addr2.getAddress());
    expect(sellerAmounts[0][0]).to.equal(1);
    expect(clearingPrice).to.equal(1);
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

    await ethers.provider.send("evm_increaseTime", [300]);
    await ethers.provider.send("evm_mine", []);

    await energyTrade.connect(owner).rollBucket();
    const [clearingPrice, buyers, sellers, sellerAmounts] =
      await energyTrade.getLastTradeBucket();

    expect(buyers.length).to.equal(1);
    expect(sellers.length).to.equal(1);
    expect(sellerAmounts.length).to.equal(1);
    expect(sellers[0].length).to.equal(1);
    expect(sellerAmounts[0].length).to.equal(1);
    expect(buyers[0]).to.equal(await addr1.getAddress());
    expect(sellers[0][0]).to.equal(await addr2.getAddress());
    expect(sellerAmounts[0][0]).to.equal(1);
    expect(clearingPrice).to.equal(1);
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

    await ethers.provider.send("evm_increaseTime", [300]);
    await ethers.provider.send("evm_mine", []);

    await energyTrade.connect(owner).rollBucket();
    const [clearingPrice, buyers, sellers, sellerAmounts] =
      await energyTrade.getLastTradeBucket();

    expect(buyers.length).to.equal(1);
    expect(sellers.length).to.equal(1);
    expect(sellerAmounts.length).to.equal(1);
    expect(sellers[0].length).to.equal(2);
    expect(sellerAmounts[0].length).to.equal(2);
    expect(buyers[0]).to.equal(await addr1.getAddress());
    expect(sellers[0][0]).to.equal(await addr2.getAddress());
    expect(sellers[0][1]).to.equal(await addr3.getAddress());
    expect(sellerAmounts[0][0]).to.equal(1);
    expect(sellerAmounts[0][1]).to.equal(1);
    expect(clearingPrice).to.equal(1);
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

    await ethers.provider.send("evm_increaseTime", [300]);
    await ethers.provider.send("evm_mine", []);

    await energyTrade.connect(owner).rollBucket();
    const [clearingPrice, buyers, sellers, sellerAmounts] =
      await energyTrade.getLastTradeBucket();

    expect(buyers.length).to.equal(2);
    expect(sellers.length).to.equal(2);
    expect(sellerAmounts.length).to.equal(2);
    expect(sellers[0].length).to.equal(1);
    expect(sellers[1].length).to.equal(1);
    expect(sellerAmounts[0].length).to.equal(1);
    expect(sellerAmounts[1].length).to.equal(1);
    expect(buyers[0]).to.equal(await addr1.getAddress());
    expect(buyers[1]).to.equal(await addr2.getAddress());
    expect(sellers[0][0]).to.equal(await addr3.getAddress());
    expect(sellers[1][0]).to.equal(await addr4.getAddress());
    expect(sellerAmounts[0][0]).to.equal(1);
    expect(sellerAmounts[1][0]).to.equal(1);
    expect(clearingPrice).to.equal(1);
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

    await ethers.provider.send("evm_increaseTime", [300]);
    await ethers.provider.send("evm_mine", []);

    await energyTrade.connect(owner).rollBucket();
    const [clearingPrice, buyers, sellers, sellerAmounts] =
      await energyTrade.getLastTradeBucket();

    expect(buyers.length).to.equal(2);
    expect(sellers.length).to.equal(2);
    expect(sellerAmounts.length).to.equal(2);
    expect(sellers[0].length).to.equal(1);
    expect(sellers[1].length).to.equal(1);
    expect(sellerAmounts[0].length).to.equal(1);
    expect(sellerAmounts[1].length).to.equal(1);
    expect(buyers[0]).to.equal(await addr1.getAddress());
    expect(buyers[1]).to.equal(await addr2.getAddress());
    expect(sellers[0][0]).to.equal(await addr3.getAddress());
    expect(sellers[1][0]).to.equal(await addr3.getAddress());
    expect(sellerAmounts[0][0]).to.equal(1);
    expect(sellerAmounts[1][0]).to.equal(1);
    expect(clearingPrice).to.equal(1);
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

    await ethers.provider.send("evm_increaseTime", [300]);
    await ethers.provider.send("evm_mine", []);

    await energyTrade.connect(owner).rollBucket();
    const [clearingPrice, buyers, sellers, sellerAmounts] =
      await energyTrade.getLastTradeBucket();

    expect(buyers.length).to.equal(1);
    expect(sellers.length).to.equal(1);
    expect(sellerAmounts.length).to.equal(1);
    expect(sellers[0].length).to.equal(1);
    expect(sellerAmounts[0].length).to.equal(1);
    expect(buyers[0]).to.equal(await addr2.getAddress());
    expect(sellers[0][0]).to.equal(await addr3.getAddress());
    expect(sellerAmounts[0][0]).to.equal(1);
    expect(clearingPrice).to.equal(1);
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

    await ethers.provider.send("evm_increaseTime", [300]);
    await ethers.provider.send("evm_mine", []);

    await energyTrade.connect(owner).rollBucket();
    const [clearingPrice, buyers, sellers, sellerAmounts] =
      await energyTrade.getLastTradeBucket();

    expect(buyers.length).to.equal(1);
    expect(sellers.length).to.equal(1);
    expect(sellerAmounts.length).to.equal(1);
    expect(sellers[0].length).to.equal(1);
    expect(sellerAmounts[0].length).to.equal(1);
    expect(buyers[0]).to.equal(await addr1.getAddress());
    expect(sellers[0][0]).to.equal(await addr3.getAddress());
    expect(sellerAmounts[0][0]).to.equal(1);
    expect(clearingPrice).to.equal(1);
  });

  it("should roll a bucket with one match from two bids and one ask where the first ask cannot be met", async function () {
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

    await ethers.provider.send("evm_increaseTime", [300]);
    await ethers.provider.send("evm_mine", []);

    const [clearingPrice, buyers, sellers, sellerAmounts] =
      await energyTrade.getLastTradeBucket();

    expect(buyers.length).to.equal(1);
    expect(sellers.length).to.equal(1);
    expect(sellerAmounts.length).to.equal(1);
    expect(sellers[0].length).to.equal(1);
    expect(sellerAmounts[0].length).to.equal(1);
    expect(buyers[0]).to.equal(await addr2.getAddress());
    expect(sellers[0][0]).to.equal(await addr3.getAddress());
    expect(sellerAmounts[0][0]).to.equal(1);
    expect(clearingPrice).to.equal(1);
  });
});
