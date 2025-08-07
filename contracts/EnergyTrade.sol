// SPDX-License-Identifier: MIT

pragma solidity ^0.8.28;

import "hardhat/console.sol";

/// @title EnergyTrade
/// @author ChristopherSiems
/// @notice EnergyTrade implements a system for trading energy on the Ethereum blockchain
/// @dev This contract is a toy prototype in its current state
contract EnergyTrade {
  /// @notice The address of the contract owner
  address public contractOwner;

  /// @notice The ID of the current bucket
  uint256 public currBucketID;

  /// @notice The start time of the current bucket
  uint256 public bucketStartTime;

  /// @notice The minimum duration of the bucket
  uint256 public bucketDuration;

  /// @notice A mapping of integers to arrays of Offers representing bids
  mapping(uint256 => Offer[]) public bidBuckets;

  /// @notice A mapping of integers to arrays of Offers representing asks
  mapping(uint256 => Offer[]) public askBuckets;

  /// @notice A mapping of integers to Statuses of buckets
  mapping(uint256 => Status) public bucketStatuses;

  /// @notice A mapping of integers to matched trade buckets
  mapping(uint256 => TradeBucket) public matchedTrades;

  /// @notice An enum representing the statuses trade buckets
  enum Status {
    OPEN,
    CLOSED,
    CLEARED
  }

  /// @notice An enum representing the types of trades
  enum TradeType {
    BID,
    ASK
  }

  /// @notice An enum defining the ordering to use when sorting
  enum Ordering {
    ASCENDING,
    DESCENDING
  }

  /// @notice A struct representing a trade offer
  struct Offer {
    address traderAddr;
    uint256 energyAmount;
    uint256 unitPrice;
    uint256 offerID;
  }

  /// @notice A struct representing a matched trade
  struct Trade {
    address buyerAddr;
    address sellerAddr;
    uint256 energyAmount;
    bool supplied;
  }

  /// @notice A struct representing a collection of matched trades
  struct TradeBucket {
    uint256 clearingPrice;
    Trade[] matchedTrades;
  }

  /// @notice Announces the address of the owner of the contract
  /// @param _ownerAddr Address of the owner
  event OwnerAnnounce(address indexed _ownerAddr);

  /// @notice Announces the receipt of a trade request
  /// @param _traderAddr Address of the requesting trader
  /// @param _bucketID ID of the bucket the request is included in
  /// @param _tradeType Type of the trade
  /// @param _tradeID ID of the trade in the bucket
  /// @param _energyAmount Amount of energy included in the request
  /// @param _unitPrice Unit price of the energy included in the request
  event TradeReceived(
    address indexed _traderAddr,
    uint256 indexed _bucketID,
    TradeType indexed _tradeType,
    uint256 _tradeID,
    uint256 _energyAmount,
    uint256 _unitPrice
  );

  /// @notice Announces a partial or total rejection of a trade
  /// @param _traderAddr Address of the requesting trader
  /// @param _bucketID ID of the bucket the request is included in
  /// @param _tradeType Type of the trade
  /// @param _tradeID ID of the trade in the bucket
  /// @param _refundAmount Amount of funds refunded as a part of the rejection
  /// @param _message Message included in the event
  event TradeRejected(
    address indexed _traderAddr,
    uint256 indexed _bucketID,
    TradeType indexed _tradeType,
    uint256 _tradeID,
    uint256 _refundAmount,
    string _message
  );

  /// @notice Announces the expiration of a matched trade
  /// @param _buyerAddr The address of the buyer
  /// @param _sellerAddr The address of the seller
  /// @param _bucketID The ID of the bucket the request is included in
  /// @param _tradeID The ID of the trade in the bucket
  /// @param _refundAmount The amount of funds refunded as a part of the expiration
  event TradeExpired(
    address indexed _buyerAddr,
    address indexed _sellerAddr,
    uint256 indexed _bucketID,
    uint256 _tradeID,
    uint256 _refundAmount
  );

  /// @notice Announces a matched trade
  /// @param _buyerAddr Address of the buyer
  /// @param _sellerAddr Address of the seller
  /// @param _bucketID ID of the bucket the request is included in
  /// @param _tradeID ID of the trade in the bucket
  /// @param _energyAmount Amount of energy traded
  /// @param _clearingPrice Unit price of the energy
  /// @param _supplied Truth of the energy being supplied
  event TradeMatched(
    address indexed _buyerAddr,
    address indexed _sellerAddr,
    uint256 indexed _bucketID,
    uint256 _tradeID,
    uint256 _energyAmount,
    uint256 _clearingPrice,
    bool _supplied
  );

  /// @notice Announces the supplying of energy within a trade
  /// @param _buyerAddr Address of the buyer
  /// @param _sellerAddr Address of the seller
  /// @param _bucketID ID of the bucket the request is included in
  /// @param _tradeID ID of the trade in the bucket
  /// @param _energyAmount Amount of energy traded
  /// @param _paymentAmount Amount of payment released to the seller
  event EnergySupplied(
    address indexed _buyerAddr,
    address indexed _sellerAddr,
    uint256 indexed _bucketID,
    uint256 _tradeID,
    uint256 _energyAmount,
    uint256 _paymentAmount
  );

  /// @notice Constructs the contract
  /// @param _bucketDuration Minimum bucket duration for the contract
  constructor(uint256 _bucketDuration) {
    contractOwner = msg.sender;
    currBucketID = 0;
    bucketStatuses[currBucketID] = Status.OPEN;
    bucketStartTime = block.timestamp;
    bucketDuration = _bucketDuration;

    emit OwnerAnnounce(msg.sender);
  }

  /// @notice Modifier that runs before trade requests to check that `_energyAmount` and `_unitPrice` are non-zero
  /// @param _energyAmount Amount of energy in the trade
  /// @param _unitPrice Unit price for the trade
  modifier prerequest(uint256 _energyAmount, uint256 _unitPrice) {
    require(_energyAmount > 0, "`_energyAmount` must be > 0.");
    require(_unitPrice > 0, "`_unitPrice` must be > 0.");

    _;
  }

  /// @notice Get the number of trades from the last bucket
  /// @return Number of trades from the last bucket
  function getLastTradeBucketTradeCount() external view returns (uint256) {
    return matchedTrades[currBucketID - 1].matchedTrades.length;
  }

  /// @notice Get the clearing price from the last trade bucket
  /// @return Clearing price of the last trade bucket
  function getLastTradeBucketClearingPrice() external view returns (uint256) {
    return matchedTrades[currBucketID - 1].clearingPrice;
  }

  /// @notice Get a desired trade bucket
  /// @dev Internal function
  /// @param _bucketIndex The index of the desired bucket
  /// @return clearingPrice Clearing price of the bucket
  /// @return tradeCount Number of trades in the bucket
  /// @return energyAmounts Amounts of energy in each trade
  /// @return buyerAddrs Addresses of buyers in each trade
  /// @return sellerAddrs Addresses of sellers in each trade
  /// @return supplieds Truths of whether or not trades have been supplied
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
    tradeCount = matchedTrades[_bucketIndex].matchedTrades.length;

    energyAmounts = new uint256[](
      matchedTrades[_bucketIndex].matchedTrades.length
    );
    buyerAddrs = new address[](energyAmounts.length);
    sellerAddrs = new address[](energyAmounts.length);
    supplieds = new bool[](energyAmounts.length);

    for (uint256 i = 0; i < energyAmounts.length; i++) {
      energyAmounts[i] = matchedTrades[_bucketIndex]
        .matchedTrades[i]
        .energyAmount;
      buyerAddrs[i] = matchedTrades[_bucketIndex].matchedTrades[i].buyerAddr;
      sellerAddrs[i] = matchedTrades[_bucketIndex].matchedTrades[i].sellerAddr;
      supplieds[i] = matchedTrades[_bucketIndex].matchedTrades[i].supplied;
    }
  }

  /// @notice Get the last trade bucket
  /// @return clearingPrice Clearing price of the bucket
  /// @return tradeCount Number of trades in the bucket
  /// @return energyAmounts Amounts of energy in each trade
  /// @return buyerAddrs Addresses of buyers in each trade
  /// @return sellerAddrs Addresses of sellers in each trade
  /// @return supplieds Truths of whether or not trades have been supplied
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

  /// @notice Get a desired trade bucket
  /// @param _bucketIndex The index of the desired bucket
  /// @return Clearing price of the bucket
  /// @return Number of trades in the bucket
  /// @return Amounts of energy in each trade
  /// @return Addresses of buyers in each trade
  /// @return Addresses of sellers in each trade
  /// @return Truths of whether or not trades have been supplied
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

  /// @notice Submits a bid
  /// @dev Uses `prerequest` modifier
  /// @param _energyAmount Amount of energy bid for
  /// @param _unitPrice Unit price offered
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

  /// @notice Submits an ask
  /// @dev Uses `prerequest` modifier
  /// @param _energyAmount Amount of energy provided
  /// @param _unitPrice Unit price requested
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

  /// @notice Close the current bucket, create a new bucket, and match trades
  /// @dev Only callable by the contract owner
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
        i < matchedTrades[currBucketID - 1].matchedTrades.length;
        i++
      ) {
        if (!matchedTrades[currBucketID - 1].matchedTrades[i].supplied)
          payable(matchedTrades[currBucketID - 1].matchedTrades[i].sellerAddr)
            .transfer(
              matchedTrades[currBucketID - 1].matchedTrades[i].energyAmount *
                matchedTrades[currBucketID - 1].clearingPrice
            );

        emit TradeExpired(
          matchedTrades[currBucketID - 1].matchedTrades[i].buyerAddr,
          matchedTrades[currBucketID - 1].matchedTrades[i].sellerAddr,
          currBucketID - 1,
          i,
          matchedTrades[currBucketID - 1].matchedTrades[i].energyAmount *
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

  /// @notice Seller marks the energy in a trade as provided
  /// @param _bucketID ID of the bucket containing the trade
  /// @param _tradeID ID of the trade in the bucket
  function markEnergySupplied(uint256 _bucketID, uint256 _tradeID) external {
    require(
      _tradeID < matchedTrades[_bucketID].matchedTrades.length,
      "`_tradeID` must be valid."
    );
    require(
      matchedTrades[_bucketID].matchedTrades[_tradeID].sellerAddr == msg.sender,
      "Only seller can mark energy supplied."
    );
    require(
      !matchedTrades[_bucketID].matchedTrades[_tradeID].supplied,
      "Energy cannot already be supplied."
    );

    matchedTrades[_bucketID].matchedTrades[_tradeID].supplied = true;
    payable(msg.sender).transfer(
      matchedTrades[_bucketID].matchedTrades[_tradeID].energyAmount *
        matchedTrades[_bucketID].clearingPrice
    );

    emit EnergySupplied(
      matchedTrades[_bucketID].matchedTrades[_tradeID].buyerAddr,
      msg.sender,
      _bucketID,
      _tradeID,
      matchedTrades[_bucketID].matchedTrades[_tradeID].energyAmount,
      matchedTrades[_bucketID].matchedTrades[_tradeID].energyAmount *
        matchedTrades[_bucketID].clearingPrice
    );
  }

  /// @notice Merge sort on an array of Offers
  /// @param _offers Array of offer objects
  /// @param _unitPriceOrdering Ordering direction for unit price
  /// @param _energyAmountOrdering Ordering direction for energy amount
  /// @return result Sorted array of Offers
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

  /// @notice Test merge sort
  /// @dev Remove this function before any mainnet deployment
  /// @param _traderAddrs Addresses of traders
  /// @param _energyAmounts Amounts of energy
  /// @param _unitPrices Unit prices
  /// @param _unitPriceOrdering Ordering direction for unit price
  /// @param _energyAmountOrdering Ordering direction for energy amount
  /// @return Sorted array of Offers
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
