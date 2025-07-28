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
    uint256 asksUsed;
    uint256 asksEmptied;
    uint256 currProvision;
    uint256 currUnitPrice = 0;
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

    for (uint256 i = 0; i < bidsSorted.length; i++) {
      if (
        currAskIndex >= asksSorted.length ||
        bidsSorted[i].unitPrice < asksSorted[currAskIndex].unitPrice
      ) break;

      currProvision = 0;
      asksUsed = 0;
      asksEmptied = 0;
      for (uint256 j = 0; currAskIndex + j < asksSorted.length; j++) {
        currUnitPrice = asksSorted[currAskIndex + j].unitPrice;
        if (
          bidsSorted[i].energyAmount < asksSorted[currAskIndex + j].energyAmount
        ) {
          currProvision = bidsSorted[i].energyAmount;
          asksSorted[currAskIndex + j].energyAmount -= bidsSorted[i]
            .energyAmount;
          bidsSorted[i].energyAmount = 0;
          asksUsed++;
        } else if (
          bidsSorted[i].energyAmount > asksSorted[currAskIndex + j].energyAmount
        ) {
          currProvision = asksSorted[currAskIndex + j].energyAmount;
          bidsSorted[i].energyAmount -= asksSorted[currAskIndex + j]
            .energyAmount;
          asksSorted[currAskIndex + j].energyAmount = 0;
          asksUsed++;
          asksEmptied++;
        } else {
          currProvision = bidsSorted[i].energyAmount;
          bidsSorted[i].energyAmount = 0;
          asksSorted[currAskIndex + j].energyAmount = 0;
          asksUsed++;
          asksEmptied++;
        }

        currSellers[j] = SellerHook(
          asksSorted[currAskIndex + j].traderAddr,
          currProvision
        );
        if (bidsSorted[i].energyAmount == 0) break;
      }
      if (bidsSorted[i].energyAmount > 0) continue;

      currSellersTruncated = new SellerHook[](asksUsed);
      for (uint256 j = 0; j < asksUsed; j++)
        currSellersTruncated[j] = currSellers[j];

      tradesConfirmed[i] = Trade(
        bidsSorted[i].traderAddr,
        currSellersTruncated
      );
      currAskIndex += asksEmptied;
      currClearingPrice = currUnitPrice;
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
    bool pickLeft;

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
      pickLeft = (_unitPriceOrdering == Ordering.ASCENDING)
        ? (leftOffers[i].unitPrice <= rightOffers[j].unitPrice)
        : (leftOffers[i].unitPrice >= rightOffers[j].unitPrice);

      if (pickLeft) result[k++] = leftOffers[i++];
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
