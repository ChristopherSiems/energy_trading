// SPDX-License-Identifier: MIT

pragma solidity ^0.8.28;

contract EnergyTrade {
  address public contractOwner;
  uint256 public currBucketID;
  uint256 public bucketStartTime;
  uint256 public bucketDuration;
  TradeBucket public lastTradeBucket;

  enum Status {
    OPEN,
    CLOSED
  }

  enum Ordering {
    ASCENDING,
    DESCENDING
  }

  struct Offer {
    address traderAddr;
    uint256 energyAmount;
    uint256 unitPrice;
  }

  struct SellerHook {
    address sellerAddr;
    uint256 energyAmount;
  }

  struct Trade {
    address buyerAddr;
    SellerHook[] sellersInfo;
  }

  struct TradeBucket {
    Trade[] confirmedTrades;
    uint256 clearingPrice;
  }

  mapping(uint256 => Offer[]) public bidBuckets;
  mapping(uint256 => Offer[]) public askBuckets;
  mapping(uint256 => Status) public bucketStatuses;

  constructor(uint256 _bucketDuration) {
    contractOwner = msg.sender;
    currBucketID = 0;
    bucketStatuses[currBucketID] = Status.OPEN;
    bucketStartTime = block.timestamp;
    bucketDuration = _bucketDuration;
  }

  modifier prerequest(uint256 _energyAmount, uint256 _unitPrice) {
    require(_energyAmount > 0, "`_energyAmount` must be > 0.");
    require(_unitPrice > 0, "`_unitPrice` must be > 0.");

    _;
  }

  function getLastTradeBucketTradeCount() external view returns (uint256) {
    return lastTradeBucket.confirmedTrades.length;
  }

  function getLastTradeBucketClearingPrice() external view returns (uint256) {
    return lastTradeBucket.clearingPrice;
  }

  function getLastTradeBucket()
    external
    view
    returns (
      uint256 clearingPrice,
      address[] memory buyers,
      address[][] memory sellers,
      uint256[][] memory sellerAmounts
    )
  {
    buyers = new address[](lastTradeBucket.confirmedTrades.length);
    sellers = new address[][](lastTradeBucket.confirmedTrades.length);
    sellerAmounts = new uint256[][](lastTradeBucket.confirmedTrades.length);

    for (uint256 i = 0; i < lastTradeBucket.confirmedTrades.length; i++) {
      buyers[i] = lastTradeBucket.confirmedTrades[i].buyerAddr;

      address[] memory sellerAddrs = new address[](
        lastTradeBucket.confirmedTrades[i].sellersInfo.length
      );
      uint256[] memory sellerAmountsInternal = new uint256[](
        lastTradeBucket.confirmedTrades[i].sellersInfo.length
      );

      for (
        uint256 j = 0;
        j < lastTradeBucket.confirmedTrades[i].sellersInfo.length;
        j++
      ) {
        sellerAddrs[j] = lastTradeBucket
          .confirmedTrades[i]
          .sellersInfo[j]
          .sellerAddr;
        sellerAmountsInternal[j] = lastTradeBucket
          .confirmedTrades[i]
          .sellersInfo[j]
          .energyAmount;
      }

      sellers[i] = sellerAddrs;
      sellerAmounts[i] = sellerAmountsInternal;
    }

    return (lastTradeBucket.clearingPrice, buyers, sellers, sellerAmounts);
  }

  function bidRequest(
    uint256 _energyAmount,
    uint256 _unitPrice
  ) external payable prerequest(_energyAmount, _unitPrice) {
    require(
      msg.value == _energyAmount * _unitPrice,
      "Correct bid value must be included in bid request."
    );
    bidBuckets[currBucketID].push(Offer(msg.sender, _energyAmount, _unitPrice));
  }

  function askRequest(
    uint256 _energyAmount,
    uint256 _unitPrice
  ) external prerequest(_energyAmount, _unitPrice) {
    askBuckets[currBucketID].push(Offer(msg.sender, _energyAmount, _unitPrice));
  }

  function rollBucket() external {
    require(
      msg.sender == contractOwner,
      "Only contract owner can roll bucket."
    );
    require(
      block.timestamp >= bucketStartTime + bucketDuration,
      "Bucket must live at least `bucketDuration` long."
    );

    uint256 prevBucketID = currBucketID;
    uint256 currAskIndex = 0;
    uint256 askOffset;
    uint256 asksEmptied;
    uint256 currProvision;
    uint256 currClearingPrice = 0;
    uint256 tradeCount = 0;
    SellerHook[] memory currSellersTruncated;
    Trade[] memory tradesConfirmedTruncated;

    bucketStatuses[currBucketID] = Status.CLOSED;
    currBucketID++;
    bucketStatuses[currBucketID] = Status.OPEN;
    bucketStartTime = block.timestamp;

    Offer[] memory bidsMemory = new Offer[](bidBuckets[prevBucketID].length);
    Offer[] memory asksMemory = new Offer[](askBuckets[prevBucketID].length);
    uint256[] memory askAmountsFallback = new uint256[](asksMemory.length);
    SellerHook[] memory currSellers = new SellerHook[](asksMemory.length);
    Trade[] memory tradesConfirmed = new Trade[](bidsMemory.length);

    for (uint256 i = 0; i < bidsMemory.length; i++)
      bidsMemory[i] = bidBuckets[prevBucketID][i];
    for (uint256 i = 0; i < asksMemory.length; i++)
      asksMemory[i] = askBuckets[prevBucketID][i];

    Offer[] memory bidsSorted = offerMergeSort(
      bidsMemory,
      Ordering.DESCENDING,
      Ordering.ASCENDING
    );
    Offer[] memory asksSorted = offerMergeSort(
      asksMemory,
      Ordering.ASCENDING,
      Ordering.DESCENDING
    );

    for (uint256 bidIndex = 0; bidIndex < bidsSorted.length; bidIndex++) {
      if (
        currAskIndex >= asksSorted.length ||
        bidsSorted[bidIndex].unitPrice < asksSorted[currAskIndex].unitPrice
      ) break;

      askOffset = 0;
      asksEmptied = 0;
      while (currAskIndex + askOffset < asksSorted.length) {
        askAmountsFallback[askOffset] = asksSorted[currAskIndex + askOffset]
          .energyAmount;
        if (
          bidsSorted[bidIndex].energyAmount <
          asksSorted[currAskIndex + askOffset].energyAmount
        ) {
          currProvision = bidsSorted[bidIndex].energyAmount;
          asksSorted[currAskIndex + askOffset].energyAmount -= bidsSorted[
            bidIndex
          ].energyAmount;
          bidsSorted[bidIndex].energyAmount = 0;
        } else if (
          bidsSorted[bidIndex].energyAmount >
          asksSorted[currAskIndex + askOffset].energyAmount
        ) {
          currProvision = asksSorted[currAskIndex + askOffset].energyAmount;
          bidsSorted[bidIndex].energyAmount -= asksSorted[
            currAskIndex + askOffset
          ].energyAmount;
          asksSorted[currAskIndex + askOffset].energyAmount = 0;
          asksEmptied++;
        } else {
          currProvision = bidsSorted[bidIndex].energyAmount;
          bidsSorted[bidIndex].energyAmount = 0;
          asksSorted[currAskIndex + askOffset].energyAmount = 0;
          asksEmptied++;
        }

        currSellers[askOffset] = SellerHook(
          asksSorted[currAskIndex + askOffset].traderAddr,
          currProvision
        );
        if (bidsSorted[bidIndex].energyAmount == 0) {
          currClearingPrice = asksSorted[currAskIndex + askOffset].unitPrice;
          break;
        }
        askOffset++;
      }

      if (bidsSorted[bidIndex].energyAmount > 0) {
        for (uint256 j = 0; j < askOffset; j++)
          asksSorted[currAskIndex + j].energyAmount = askAmountsFallback[j];
        continue;
      }

      currSellersTruncated = new SellerHook[](askOffset + 1);
      for (uint256 j = 0; j < askOffset + 1; j++)
        currSellersTruncated[j] = currSellers[j];

      tradesConfirmed[bidIndex] = Trade(
        bidsSorted[bidIndex].traderAddr,
        currSellersTruncated
      );
      currAskIndex += asksEmptied;
      tradeCount++;
    }

    tradesConfirmedTruncated = new Trade[](tradeCount);
    for (uint256 i = 0; i < tradeCount; i++)
      tradesConfirmedTruncated[i] = tradesConfirmed[i];
    lastTradeBucket = TradeBucket(tradesConfirmedTruncated, currClearingPrice);

    delete bidBuckets[prevBucketID];
    delete askBuckets[prevBucketID];
  }

  function offerMergeSort(
    Offer[] memory _offers,
    Ordering _unitPriceOrdering,
    Ordering _energyAmountOrdering
  ) public pure returns (Offer[] memory result) {
    if (_offers.length <= 1) return _offers;

    Offer[] memory leftOffers = new Offer[](_offers.length / 2);
    Offer[] memory rightOffers = new Offer[](
      _offers.length - _offers.length / 2
    );
    result = new Offer[](_offers.length);

    uint256 i = 0;
    uint256 j = 0;
    uint256 k = 0;

    for (uint256 l = 0; l < leftOffers.length; l++) leftOffers[l] = _offers[l];
    for (uint256 l = 0; l < rightOffers.length; l++)
      rightOffers[l] = _offers[leftOffers.length + l];

    leftOffers = offerMergeSort(
      leftOffers,
      _unitPriceOrdering,
      _energyAmountOrdering
    );
    rightOffers = offerMergeSort(
      rightOffers,
      _unitPriceOrdering,
      _energyAmountOrdering
    );

    while (i < leftOffers.length && j < rightOffers.length) {
      if (
        (_unitPriceOrdering == Ordering.ASCENDING)
          ? (leftOffers[i].unitPrice <= rightOffers[j].unitPrice)
          : (leftOffers[i].unitPrice >= rightOffers[j].unitPrice)
      ) result[k++] = leftOffers[i++];
      else result[k++] = rightOffers[j++];
    }

    while (i < leftOffers.length) result[k++] = leftOffers[i++];
    while (j < rightOffers.length) result[k++] = rightOffers[j++];
  }

  // THIS FUNCTION NEEDS TO BE REMOVED BEFORE ANY DEPLOYMENT
  function offerMergeSortTest(
    address[] memory _traderAddrs,
    uint256[] memory _energyAmounts,
    uint256[] memory _unitPrices,
    Ordering _unitPriceOrdering,
    Ordering _energyAmountOrdering
  ) external pure returns (Offer[] memory) {
    require(
      _traderAddrs.length == _energyAmounts.length &&
        _traderAddrs.length == _unitPrices.length,
      "Array lengths must match."
    );

    Offer[] memory offers = new Offer[](_traderAddrs.length);
    for (uint256 i = 0; i < _traderAddrs.length; i++) {
      offers[i] = Offer(_traderAddrs[i], _energyAmounts[i], _unitPrices[i]);
    }

    return offerMergeSort(offers, _unitPriceOrdering, _energyAmountOrdering);
  }
}
