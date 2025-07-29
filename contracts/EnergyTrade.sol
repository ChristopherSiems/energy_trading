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

  event DebugFlag(string _flag);
  event DebugVal(uint256 _val);
  event DebugTradeBucket(uint256 _clearingPrice);
  event DebugTrade(address _buyerAddr, uint256 _sellerCount);
  event DebugSeller(address _sellerAddr, uint256 _energyAmount);
  event BidReceived(address _bidderAddr, uint256 _bidID);
  event TradeRejected(address indexed _trader, string _message);
  event TradeMatched(
    address indexed _buyer,
    address indexed _seller,
    uint256 _energyAmount,
    uint256 _clearingPrice
  );

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

  function debugTradeBucket(TradeBucket memory _tradeBucket) internal {
    emit DebugTradeBucket(_tradeBucket.clearingPrice);

    for (uint256 i = 0; i < _tradeBucket.confirmedTrades.length; i++) {
      Trade memory trade = _tradeBucket.confirmedTrades[i];
      emit DebugTrade(trade.buyerAddr, trade.sellersInfo.length);

      for (uint256 j = 0; j < trade.sellersInfo.length; j++) {
        SellerHook memory seller = trade.sellersInfo[j];
        emit DebugSeller(seller.sellerAddr, seller.energyAmount);
      }
    }
  }

  function getLastTradeBucketTradeCount() external view returns (uint256) {
    return matchedTrades[currBucketID - 1].confirmedTrades.length;
  }

  function getLastTradeBucketClearingPrice() external view returns (uint256) {
    return matchedTrades[currBucketID - 1].clearingPrice;
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
    buyers = new address[](
      matchedTrades[currBucketID - 1].confirmedTrades.length
    );
    sellers = new address[][](
      matchedTrades[currBucketID - 1].confirmedTrades.length
    );
    sellerAmounts = new uint256[][](
      matchedTrades[currBucketID - 1].confirmedTrades.length
    );

    for (
      uint256 i = 0;
      i < matchedTrades[currBucketID - 1].confirmedTrades.length;
      i++
    ) {
      buyers[i] = matchedTrades[currBucketID - 1].confirmedTrades[i].buyerAddr;

      address[] memory sellerAddrs = new address[](
        matchedTrades[currBucketID - 1].confirmedTrades[i].sellersInfo.length
      );
      uint256[] memory sellerAmountsInternal = new uint256[](
        matchedTrades[currBucketID - 1].confirmedTrades[i].sellersInfo.length
      );

      for (
        uint256 j = 0;
        j <
        matchedTrades[currBucketID - 1].confirmedTrades[i].sellersInfo.length;
        j++
      ) {
        sellerAddrs[j] = matchedTrades[currBucketID - 1]
          .confirmedTrades[i]
          .sellersInfo[j]
          .sellerAddr;
        sellerAmountsInternal[j] = matchedTrades[currBucketID - 1]
          .confirmedTrades[i]
          .sellersInfo[j]
          .energyAmount;
      }

      sellers[i] = sellerAddrs;
      sellerAmounts[i] = sellerAmountsInternal;
    }

    clearingPrice = matchedTrades[currBucketID - 1].clearingPrice;
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

    Offer[] memory bidsMemory = new Offer[](
      bidBuckets[currBucketID - 1].length
    );
    Offer[] memory asksMemory = new Offer[](
      askBuckets[currBucketID - 1].length
    );
    uint256[] memory bidEnergyAmounts = new uint256[](bidsMemory.length);
    uint256[] memory askAmountsFallback = new uint256[](asksMemory.length);
    SellerHook[] memory currSellers = new SellerHook[](asksMemory.length);
    Trade[] memory tradesConfirmed = new Trade[](bidsMemory.length);

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
      bidEnergyAmounts[bidIndex] = bidsSorted[bidIndex].energyAmount;
      while (currAskIndex + askOffset < asksSorted.length) {
        // store ask energy amounts to restore later
        askAmountsFallback[askOffset] = asksSorted[currAskIndex + askOffset]
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
        currSellers[askOffset] = SellerHook(
          asksSorted[currAskIndex + askOffset].traderAddr,
          currProvision
        );

        // check if the requested amount of energy is spoken for
        if (bidsSorted[bidIndex].energyAmount == 0) {
          currClearingPrice = asksSorted[currAskIndex + askOffset].unitPrice;
          break;
        }

        askOffset++;
      }

      // restore asked supply if asks are unused
      if (bidsSorted[bidIndex].energyAmount > 0) {
        for (uint256 j = 0; j < askOffset; j++)
          asksSorted[currAskIndex + j].energyAmount = askAmountsFallback[j];
        continue;
      }

      // truncate the list of SellerHooks
      currSellersTruncated = new SellerHook[](askOffset + 1);
      for (uint256 j = 0; j < askOffset + 1; j++)
        currSellersTruncated[j] = currSellers[j];

      // create a trade object for the bid
      tradesConfirmed[tradeCount] = Trade(
        bidsSorted[bidIndex].traderAddr,
        currSellersTruncated
      );
      tradeCount++;
      currAskIndex += asksEmptied;
    }

    tradesConfirmedTruncated = new Trade[](tradeCount);
    for (uint256 i = 0; i < tradeCount; i++) {
      tradesConfirmedTruncated[i] = tradesConfirmed[i];
    }
    matchedTrades[currBucketID - 1] = TradeBucket(
      tradesConfirmedTruncated,
      currClearingPrice
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
          "Bid rejected due to unmeetable demand at bid price."
        );
    }

    // inform askers that their asks were unmet
    for (uint256 i = 0; i < asksSorted.length; i++)
      if (asksSorted[i].energyAmount != 0)
        emit TradeRejected(
          asksSorted[i].traderAddr,
          "Ask rejected due to undemanded supply at ask price."
        );

    // inform the market of successful matches
    for (
      uint256 tradeIndex = 0;
      tradeIndex < matchedTrades[currBucketID - 1].confirmedTrades.length;
      tradeIndex++
    ) {
      for (
        uint256 sellerIndex = 0;
        sellerIndex <
        matchedTrades[currBucketID - 1]
          .confirmedTrades[tradeIndex]
          .sellersInfo
          .length;
        sellerIndex++
      ) {
        emit TradeMatched(
          matchedTrades[currBucketID - 1].confirmedTrades[tradeIndex].buyerAddr,
          matchedTrades[currBucketID - 1]
            .confirmedTrades[tradeIndex]
            .sellersInfo[sellerIndex]
            .sellerAddr,
          matchedTrades[currBucketID - 1]
            .confirmedTrades[tradeIndex]
            .sellersInfo[sellerIndex]
            .energyAmount,
          currClearingPrice
        );
      }
    }
  }

  function markEnergySupplied() external {}

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
