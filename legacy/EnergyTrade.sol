// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

contract EnergyTrade {
  address public seller;
  address public buyer;
  uint256 public energyAmount;
  uint256 public unitPrice;
  bool public tradeActive;
  bool public tradeDeposit;
  bool public energyDelivered;
  bool public payReleased;

  constructor(address _buyer, uint256 _energyAmount, uint256 _unitPrice) {
    seller = msg.sender;
    buyer = _buyer;
    energyAmount = _energyAmount;
    unitPrice = _unitPrice;
    tradeActive = true;
    tradeDeposit = false;
    energyDelivered = false;
    payReleased = false;
  }

  function payDeposit() external payable {
    require(tradeActive, "The trade is not active.");
    require(!tradeDeposit, "The deposit is already paid.");
    require(msg.sender == buyer, "Only the buyer can pay for the trade.");
    require(msg.value == energyAmount * unitPrice, "Incorrect amount paid.");

    tradeDeposit = true;
  }

  function markDelivered() external {
    require(tradeActive, "The trade is not active.");
    require(tradeDeposit, "The deposit is not paid.");
    require(!energyDelivered, "The energy was already delivered.");
    require(
      msg.sender == seller,
      "Only the seller can mark the energy as delivered."
    );

    payable(seller).transfer(address(this).balance);

    energyDelivered = true;
    payReleased = true;
    tradeActive = false;
  }

  function cancelTrade() external {
    require(tradeActive, "The trade is not active.");
    require(!energyDelivered, "The energy is already delivered.");
    require(!payReleased, "The deposit has already been released.");

    if (tradeDeposit) {
      payable(buyer).transfer(address(this).balance);
    }

    tradeDeposit = false;
    tradeActive = false;
  }
}
