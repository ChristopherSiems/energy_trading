function offerSort(offers, unitPriceOrdering, energyAmountOrdering) {
  return offers.sort((a, b) => {
    if (a.unitPrice === b.unitPrice)
      return energyAmountOrdering === "ASCENDING"
        ? a.energyAmount - b.energyAmount
        : b.energyAmount - a.energyAmount;
    else
      return unitPriceOrdering === "ASCENDING"
        ? a.unitPrice - b.unitPrice
        : b.unitPrice - a.unitPrice;
  });
}

const tradeData = JSON.parse(args[0]);
const bidsSorted = offerSort(tradeData.bids, "DESCENDING", "ASCENDING");

let currBid;
let currBidUnitPrice;
let currBidEnergyAmount;
let askOffset;
let currAsksConsumedCount;
let currMatchedTrades;
let currAsk;
let currAskEnergyAmount;
let askEnergyAmounts;
let currMatchedAmounts;

let asksSorted = offerSort(tradeData.asks, "ASCENDING", "DESCENDING");
let askIndex = 0;
let currClearingPrice = 0;
let matchedTrades = [];

const askCount = asksSorted.length;

for (let bidIndex = 0; bidIndex < bidsSorted.length; bidIndex++) {
  currBid = bidsSorted[bidIndex];
  currBidUnitPrice = currBid.unitPrice;

  if (askIndex >= askCount || currBidUnitPrice < asksSorted[askIndex].unitPrice)
    break;

  currBidEnergyAmount = currBid.energyAmount;
  askOffset = 0;
  currAsksConsumedCount = 0;
  currMatchedTrades = [];

  while (askIndex + askOffset < askCount) {
    currAsk = asksSorted[askIndex + askOffset];
    currAskEnergyAmount = currAsk.energyAmount;

    if (currBidUnitPrice < currAsk.unitPrice) break;
    if (currBidEnergyAmount < currAskEnergyAmount) {
      currMatchedAmounts = currBidEnergyAmount;
      currAskEnergyAmount -= currBidEnergyAmount;
      currBidEnergyAmount = 0;
    } else if (currBidEnergyAmount > currAskEnergyAmount) {
      currMatchedAmounts = currAskEnergyAmount;
      currBidEnergyAmount -= currAskEnergyAmount;
      currAskEnergyAmount = 0;
      currAsksConsumedCount++;
    } else {
      currMatchedAmounts = currBidEnergyAmount;
      currBidEnergyAmount = 0;
      currAskEnergyAmount = 0;
      currAsksConsumedCount++;
    }

    currMatchedTrades[askOffset] = {
      buyerAddr: currBid.traderAddr,
      sellerAddr: currAsk.traderAddr,
      energyAmount: currMatchedAmounts,
      supplied: false,
    };

    if (currBidEnergyAmount === 0) {
      currClearingPrice = currAsk.unitPrice;
      break;
    }

    currAsk.energyAmount = currAskEnergyAmount;
    askOffset++;
  }

  if (currBidEnergyAmount > 0) continue;
  matchedTrades = matchedTrades.concat(currMatchedTrades);
  askIndex += currAsksConsumedCount;
}

return Functions.encodeString(
  JSON.stringify({
    clearingPrice: currClearingPrice,
    matchedTrades: matchedTrades,
  }),
);
