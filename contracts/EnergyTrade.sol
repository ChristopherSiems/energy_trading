// SPDX-License-Identifier: MIT

pragma solidity ^0.8.28;

import "hardhat/console.sol";

contract EnergyTrade {
  address public contractOwner;
  uint256 public currBucketID;
  uint256 public bucketStartTime;
  uint256 public bucketDuration;

  mapping(uint256 => Offer[]) public bidBuckets;
  mapping(uint256 => Offer[]) public askBuckets;
  mapping(uint256 => Status) public bucketStatuses;
  mapping(uint256 => TradeBucket) public matchedTrades;

  enum Status {
    OPEN,
    CLOSED,
    CLEARED
  }

  enum TradeType {
    BID,
    ASK
  }

  enum Ordering {
    ASCENDING,
    DESCENDING
  }

  struct Offer {
    address traderAddr;
    uint256 energyAmount;
    uint256 unitPrice;
    uint256 offerID;
  }

  struct Trade {
    address buyerAddr;
    address sellerAddr;
    uint256 energyAmount;
    bool supplied;
  }

  struct TradeBucket {
    uint256 clearingPrice;
    Trade[] confirmedTrades;
  }

  event OwnerAnnounce(address indexed _ownerAddr);

  event TradeReceived(
    address indexed _traderAddr,
    uint256 indexed _bucketID,
    TradeType indexed _tradeType,
    uint256 _tradeID,
    uint256 _energyAmount,
    uint256 _unitPrice
  );

  event TradeRejected(
    address indexed _traderAddr,
    uint256 indexed _bucketID,
    TradeType indexed _tradeType,
    uint256 _tradeID,
    uint256 _refundAmount,
    string _message
  );

  event TradeExpired(
    address indexed _buyerAddr,
    address indexed _sellerAddr,
    uint256 indexed _bucketID,
    uint256 _tradeID,
    uint256 _refundAmount
  );

  event TradeMatched(
    address indexed _buyer,
    address indexed _seller,
    uint256 indexed _bucketID,
    uint256 _tradeID,
    uint256 _energyAmount,
    uint256 _clearingPrice,
    bool _supplied
  );

  event EnergySupplied(
    address indexed _supplier,
    address indexed _receiver,
    uint256 indexed _bucketID,
    uint256 _tradeID,
    uint256 _energyAmount,
    uint256 _paymentAmount
  );

  constructor(uint256 _bucketDuration) {
    contractOwner = msg.sender;
    currBucketID = 0;
    bucketStatuses[currBucketID] = Status.OPEN;
    bucketStartTime = block.timestamp;
    bucketDuration = _bucketDuration;

    emit OwnerAnnounce(msg.sender);
  }

  modifier prerequest(uint256 _energyAmount, uint256 _unitPrice) {
    require(_energyAmount > 0, "`_energyAmount` must be > 0.");
    require(_unitPrice > 0, "`_unitPrice` must be > 0.");

    _;
  }

  function getLastTradeBucketTradeCount() external view returns (uint256) {
    return matchedTrades[currBucketID - 1].confirmedTrades.length;
  }

  function getLastTradeBucketClearingPrice() external view returns (uint256) {
    return matchedTrades[currBucketID - 1].clearingPrice;
  }

  function _getTradeBucket(
    uint256 _bucketIndex
  )
    internal
    view
    returns (
      uint256 clearingPrice,
      uint256 tradeCount,
      uint256[] memory energyAmounts,
      address[] memory buyerAddrs,
      address[] memory sellerAddrs,
      bool[] memory supplieds
    )
  {
    clearingPrice = matchedTrades[_bucketIndex].clearingPrice;
    tradeCount = matchedTrades[_bucketIndex].confirmedTrades.length;

    energyAmounts = new uint256[](
      matchedTrades[_bucketIndex].confirmedTrades.length
    );
    buyerAddrs = new address[](energyAmounts.length);
    sellerAddrs = new address[](energyAmounts.length);
    supplieds = new bool[](energyAmounts.length);

    for (uint256 i = 0; i < energyAmounts.length; i++) {
      energyAmounts[i] = matchedTrades[_bucketIndex]
        .confirmedTrades[i]
        .energyAmount;
      buyerAddrs[i] = matchedTrades[_bucketIndex].confirmedTrades[i].buyerAddr;
      sellerAddrs[i] = matchedTrades[_bucketIndex]
        .confirmedTrades[i]
        .sellerAddr;
      supplieds[i] = matchedTrades[_bucketIndex].confirmedTrades[i].supplied;
    }
  }

  function getLastTradeBucket()
    external
    view
    returns (
      uint256,
      uint256,
      uint256[] memory,
      address[] memory,
      address[] memory,
      bool[] memory
    )
  {
    return _getTradeBucket(currBucketID - 1);
  }

  function getTradeBucket(
    uint256 _bucketIndex
  )
    external
    view
    returns (
      uint256,
      uint256,
      uint256[] memory,
      address[] memory,
      address[] memory,
      bool[] memory
    )
  {
    return _getTradeBucket(_bucketIndex);
  }

  function bidRequest(
    uint256 _energyAmount,
    uint256 _unitPrice
  ) external payable prerequest(_energyAmount, _unitPrice) {
    require(
      msg.value == _energyAmount * _unitPrice,
      "Correct bid value must be included in bid request."
    );

    bidBuckets[currBucketID].push(
      Offer(
        msg.sender,
        _energyAmount,
        _unitPrice,
        bidBuckets[currBucketID].length
      )
    );

    emit TradeReceived(
      msg.sender,
      currBucketID,
      TradeType.BID,
      bidBuckets[currBucketID].length - 1,
      _energyAmount,
      _unitPrice
    );
  }

  function askRequest(
    uint256 _energyAmount,
    uint256 _unitPrice
  ) external prerequest(_energyAmount, _unitPrice) {
    askBuckets[currBucketID].push(
      Offer(
        msg.sender,
        _energyAmount,
        _unitPrice,
        askBuckets[currBucketID].length
      )
    );

    emit TradeReceived(
      msg.sender,
      currBucketID,
      TradeType.ASK,
      askBuckets[currBucketID].length - 1,
      _energyAmount,
      _unitPrice
    );
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

    uint256 currAskIndex = 0;
    uint256 askOffset;
    uint256 asksEmptied;
    uint256 currProvision;
    uint256 currClearingPrice = 0;
    uint256 tempTradeCount;
    uint256 tradeCount = 0;
    Trade[] memory tempTrades;
    Trade[] memory tradesConfirmedTruncated;

    // refund unfulfilled trades
    if (currBucketID > 0) {
      for (
        uint256 i = 0;
        i < matchedTrades[currBucketID - 1].confirmedTrades.length;
        i++
      ) {
        if (!matchedTrades[currBucketID - 1].confirmedTrades[i].supplied)
          payable(matchedTrades[currBucketID - 1].confirmedTrades[i].sellerAddr)
            .transfer(
              matchedTrades[currBucketID - 1].confirmedTrades[i].energyAmount *
                matchedTrades[currBucketID - 1].clearingPrice
            );

        emit TradeExpired(
          matchedTrades[currBucketID - 1].confirmedTrades[i].buyerAddr,
          matchedTrades[currBucketID - 1].confirmedTrades[i].sellerAddr,
          currBucketID - 1,
          i,
          matchedTrades[currBucketID - 1].confirmedTrades[i].energyAmount *
            matchedTrades[currBucketID - 1].clearingPrice
        );
      }
      bucketStatuses[currBucketID - 1] = Status.CLEARED;
    }

    bucketStatuses[currBucketID] = Status.CLOSED;
    currBucketID++;
    bucketStatuses[currBucketID] = Status.OPEN;
    bucketStartTime = block.timestamp;

    Offer[] memory bidsMemory = new Offer[](
      bidBuckets[currBucketID - 1].length
    );
    Offer[] memory asksMemory = new Offer[](
      askBuckets[currBucketID - 1].length
    );
    uint256[] memory bidEnergyAmounts = new uint256[](bidsMemory.length);
    uint256[] memory askEnergyAmounts = new uint256[](asksMemory.length);
    Trade[] memory tradesConfirmed = new Trade[](
      bidsMemory.length + asksMemory.length
    );

    // copy storage arrays into memory
    for (uint256 i = 0; i < bidsMemory.length; i++)
      bidsMemory[i] = bidBuckets[currBucketID - 1][i];
    for (uint256 i = 0; i < asksMemory.length; i++)
      asksMemory[i] = askBuckets[currBucketID - 1][i];

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

    // matching
    for (uint256 bidIndex = 0; bidIndex < bidsSorted.length; bidIndex++) {
      // stop matching if asks are depleted or too expensive
      if (
        currAskIndex >= asksSorted.length ||
        bidsSorted[bidIndex].unitPrice < asksSorted[currAskIndex].unitPrice
      ) break;

      // match asks
      askOffset = 0;
      asksEmptied = 0;
      tempTradeCount = 0;
      bidEnergyAmounts[bidIndex] = bidsSorted[bidIndex].energyAmount;
      tempTrades = new Trade[](asksSorted.length - currAskIndex);
      while (currAskIndex + askOffset < asksSorted.length) {
        // check if next ask is too expensive
        if (
          bidsSorted[bidIndex].unitPrice <
          asksSorted[currAskIndex + askOffset].unitPrice
        ) break;

        // store ask energy amounts to restore later
        askEnergyAmounts[askOffset] = asksSorted[currAskIndex + askOffset]
          .energyAmount;

        // trading logic
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

        // create object representing the current seller's contribution to the trade
        tempTrades[askOffset] = Trade(
          bidsSorted[bidIndex].traderAddr,
          asksSorted[currAskIndex + askOffset].traderAddr,
          currProvision,
          false
        );
        tempTradeCount++;

        // check if the requested amount of energy is spoken for
        if (bidsSorted[bidIndex].energyAmount == 0) {
          currClearingPrice = asksSorted[currAskIndex + askOffset].unitPrice;
          break;
        }
        askOffset++;
      }

      // restore asked supply if asks are unused
      if (bidsSorted[bidIndex].energyAmount > 0) {
        for (uint256 i = 0; i < askOffset; i++)
          asksSorted[currAskIndex + i].energyAmount = askEnergyAmounts[i];
        continue;
      }

      // make temporary trades permanent
      for (uint256 i = 0; i < tempTradeCount; i++)
        tradesConfirmed[tradeCount + i] = tempTrades[i];
      tradeCount += tempTradeCount;
      currAskIndex += asksEmptied;
    }

    // truncate trade array
    tradesConfirmedTruncated = new Trade[](tradeCount);
    for (uint256 i = 0; i < tradeCount; i++) {
      tradesConfirmedTruncated[i] = tradesConfirmed[i];
    }
    matchedTrades[currBucketID - 1] = TradeBucket(
      currClearingPrice,
      tradesConfirmedTruncated
    );

    // refunds
    for (uint256 i = 0; i < bidsSorted.length; i++) {
      payable(bidsSorted[i].traderAddr).transfer(
        (bidsSorted[i].energyAmount != 0)
          ? bidsSorted[i].energyAmount * bidsSorted[i].unitPrice
          : bidEnergyAmounts[i] * (bidsSorted[i].unitPrice - currClearingPrice)
      );

      // inform bidders that their bids were unmet
      if (bidsSorted[i].energyAmount != 0)
        emit TradeRejected(
          bidsSorted[i].traderAddr,
          currBucketID - 1,
          TradeType.BID,
          bidsSorted[i].offerID,
          bidsSorted[i].energyAmount * bidsSorted[i].unitPrice,
          "Bid rejected due to unmeetable demand at bid price."
        );
    }

    // inform askers that their asks were unmet
    for (uint256 i = 0; i < asksSorted.length; i++)
      if (asksSorted[i].energyAmount != 0)
        emit TradeRejected(
          asksSorted[i].traderAddr,
          currBucketID - 1,
          TradeType.ASK,
          asksSorted[i].offerID,
          0,
          "Ask partially or fully rejected due to undemanded supply at ask price."
        );

    // inform the market of successful matches
    for (uint256 i = 0; i < tradeCount; i++)
      emit TradeMatched(
        tradesConfirmedTruncated[i].buyerAddr,
        tradesConfirmedTruncated[i].sellerAddr,
        currBucketID - 1,
        i,
        tradesConfirmedTruncated[i].energyAmount,
        currClearingPrice,
        false
      );
  }

  function markEnergySupplied(uint256 _bucketID, uint256 _tradeID) external {
    require(
      _tradeID < matchedTrades[_bucketID].confirmedTrades.length,
      "`_tradeID` must be valid."
    );
    require(
      matchedTrades[_bucketID].confirmedTrades[_tradeID].sellerAddr ==
        msg.sender,
      "Only seller can mark energy supplied."
    );
    require(
      !matchedTrades[_bucketID].confirmedTrades[_tradeID].supplied,
      "Energy cannot already be supplied."
    );

    matchedTrades[_bucketID].confirmedTrades[_tradeID].supplied = true;
    payable(msg.sender).transfer(
      matchedTrades[_bucketID].confirmedTrades[_tradeID].energyAmount *
        matchedTrades[_bucketID].clearingPrice
    );

    emit EnergySupplied(
      msg.sender,
      matchedTrades[_bucketID].confirmedTrades[_tradeID].buyerAddr,
      _bucketID,
      _tradeID,
      matchedTrades[_bucketID].confirmedTrades[_tradeID].energyAmount,
      matchedTrades[_bucketID].confirmedTrades[_tradeID].energyAmount *
        matchedTrades[_bucketID].clearingPrice
    );
  }

  function offerMergeSort(
    Offer[] memory _offers,
    Ordering _unitPriceOrdering,
    Ordering _energyAmountOrdering
  ) public pure returns (Offer[] memory result) {
    if (_offers.length <= 1) return _offers;

    Offer[] memory leftOffers = new Offer[](_offers.length / 2);
    Offer[] memory rightOffers = new Offer[](
      _offers.length - leftOffers.length
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
      offers[i] = Offer(_traderAddrs[i], _energyAmounts[i], _unitPrices[i], 0);
    }

    return offerMergeSort(offers, _unitPriceOrdering, _energyAmountOrdering);
  }
}
