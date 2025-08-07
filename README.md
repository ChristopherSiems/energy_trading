# Energy Trading

## `EnergyTrade.sol`

This contract implements a double auction mechanism for trading energy. The double auction protocol works as follows:

1. The contract is initialized and an initial bucket is opened.
2. Would-be buyers submit bids containing a requested amount of energy and a unit price. Buyers transfer $\text{energy amount} * \text{unit price}$ funds to the contract with their request. Would-be sellers submit asks containing the amount of suppliable energy and desired unit price.
3. Eventually, the bucket is closed.
4. Bids are sorted in descending order by unit price.
5. Asks are sorted in ascending order by unit price.
6. The bid offering the most is matched with the ask requesting the least. This is repeated until there remains no bids offering greater than or equal to the next ask.
7. The price requested by the last matched ask is made the clearing price that is paid by all buyers.
8. Unmatched bids are refunded.
9. Overpaid bids are partially refunded.
10. Matched trades are broadcasted on the blockchain.
11. A new bucket is opened and users can submit bids and asks to this new bucket.
12. Sellers provide their energy and mark their energy as supplied. Payment is released to the sellers.

## Testing

Hardhat enables writing unit tests for solidity contracts written in Javascript or Typescript. This repo uses Typescript. When implementing new features to the contract, be sure to add comprehensive unit tests. Unit tests for a specific contract live in the `tests/ContractName.ts` file. Use the below command to run the test suites:

```bash
npx hardhat test
```

## Tasks

Hardhat supports a feature called `tasks`. A task is a script written in Javascript or Typescript, in our case Typescript, that can be declared to hardhat and conveniently run. New tasks should be placed in the `tasks/` directory and imported in `hardhat.config.ts`.

### `compile`

`compile` is a builtin task that compiles solidity contracts.

```bash
npx hardhat compile
```

### `test`

`test` is a builtin task that compiles solidity contracts and then runs test suites.

```bash
npx hardhat test
```

### `node`

`node` is builtin task that deploys a local Ethereum node simulation to `localhost`. Along with the node simulation, 20 funded accounts are deployed for use.

```bash
npx hardhat node
```

### `deploy`

`deploy` is a custom task that deploys the `EnergyTrade` contract to a local simulated blockchain. Best practice is to use this task in conjunction with `node`. You should use `node` in one shell then use `deploy` in another shell. If used successfully, you should see an output from the shell running the simulated Ethereum node announcing the deployment.

```bash
npx hardhat deploy --network localhost
```

### `cli`

`cli` is a custom task that enables interactive use of `EnergyContract` with a locally deployed instance. Best practice is to use this task in conjunction with `node` and `deploy`. You should use `node` in one shell then use `deploy` in another shell. In the same shell as `deploy`, `cli` can be used. `cli` is more complicated than the other tasks.

- `account`: tells `cli` which account to use, pass this flag an integer in the range $[0, 20)$ to use that account. `0` is the contract owner account.
- `cmd`: tells `cli` which interaction to do
  - `bid`: submits a bid request
  - `ask`: submits an ask request
  - `roll`: rolls the current bucket, will only succeed if account is `0`
  - `mark`: marks an energy trade as supplied, will only succeed if the account is the same account as the seller for the trade
- `energy`: sets the energy amount for `bid` and `ask`
- `price`: sets the unit price for `bid` and `ask`
- `bucket`: the bucket ID of the trade to mark
- `trade`: the trade ID of the trade to mark

```bash
npx hardhat cli --network localhost --account A --cmd bid --energy B -price C
npx hardhat cli --network localhost --account D --cmd ask --energy E -price F
npx hardhat cli --network localhost --account 0 --cmd roll
npx hardhat cli --network localhost --account D --cmd mark --bucket G --trade H
```

### `audit`

`audit` is a custom task that prints the trade history of the locally deployed `EnergyTrade` contract. Best practice is to use this task in conjunction with `node`, `deploy`, and `cli`. You should use `node` in one shell then use `deploy` and `cli` in another shell. In that same shell, `audit` can be used.

```bash
npx hardhat audit --network localhost
```
