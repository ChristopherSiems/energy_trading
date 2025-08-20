# Chainlink Functions

[https://docs.chain.link/chainlink-functions](https://docs.chain.link/chainlink-functions)

- Don't require maintaining own node
- Allow including secret values
- Subscription account is billed in LINK to pay for requests
- We can only use functions on mainnet and testnet
  - Sepolia
  - Need testnet ETH and LINK
    - Need mainnet LINK to request testnet ETH
    - Limits ability to use this technology
    - Can maybe use local Chainlink oracle for simulation

## Process

1. Smart contract sends code to a DON
2. Nodes run the code and produce their outputs
3. Results are aggregated
4. Aggregated result is returned to the contract
