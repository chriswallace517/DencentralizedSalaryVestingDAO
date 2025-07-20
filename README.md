# DecentralizeSalaryVestingDAO

A smart contract system for decentralized salary vesting, built on the Stacks blockchain.

## Features
**Vesting Schedule Creation**: Owner can create vesting schedules for recipients.
**Automated Token Release**: Tokens vest based on block height and interval.
**Claim System**: Recipients can claim vested tokens.
**Batch Operations**: Owner can create multiple vesting schedules in one transaction.
**Fund Deposits**: Anyone can deposit STX to the contract.
**Excess Withdrawal**: Owner can withdraw excess funds.
**Emergency Pause/Resume**: Owner can pause or resume contract operations.
**Ownership Transfer**: Owner can transfer contract ownership.
**Read-only Queries**: Functions to get vesting schedule, contract owner, contract balance, and emergency pause status.

## Contract Data Structures

### Vesting Schedule

```clarity
{
    total: uint,
    claimed: uint,
    start-block: uint,
    interval: uint,
    step: uint
}
```

## Key Functions

### Public Functions

- `create-vesting(recipient, total, interval, step)`  
  Create a vesting schedule for a recipient (owner only).
- `claim-vested()`  
  Claim available vested tokens.
- `create-multiple-vestings(recipients, totals, intervals, steps)`  
  Batch create vesting schedules (owner only).
- `deposit-funds(amount)`  
  Deposit STX to the contract.
- `withdraw-excess-funds(amount)`  
  Withdraw excess funds (owner only).
- `emergency-pause-contract()`  
  Pause contract operations (owner only).
- `emergency-resume-contract()`  
  Resume contract operations (owner only).
- `set-contract-owner(new-owner)`  
  Transfer contract ownership (owner only).

### Read-only Functions

- `get-vesting-schedule(recipient)`  
  Get vesting schedule for a recipient.
- `get-contract-owner()`  
  Get contract owner.
- `get-contract-balance()`  
  Get contract STX balance.
- `is-emergency-paused()`  
  Check if contract is paused.

## Error Codes

- `u401` - Not authorized
- `u403` - Insufficient funds
- `u404` - Not found
- `u405` - Emergency pause
- `u406` - Invalid amount

### Installation

```sh
npm install
```

### Testing

Run unit tests:

```sh
npm test
```

Run tests with coverage and cost reports:

```sh
npm run test:report
```

Check contract syntax:

```sh
clarinet check
```
