# CustomToken Smart Contract

A feature-rich, upgradeable ERC20 token implementation with advanced functionality including vesting, multi-signature governance, and anti-whale mechanisms.

## Features

- 🔄 UUPS Upgradeable
- 🔐 Multi-signature governance
- ⏳ Token vesting with cliff period
- 🐋 Anti-whale mechanism
- ⛔ Blacklist functionality
- ⏸️ Emergency pause
- 💰 Automatic fee collection
- 🔒 Liquidity locking

## Technical Overview

### Token Economics
- Total Supply: 10 billion tokens
- Max Transfer: 2% of total supply per transaction
- Fees: 0.5% marketing + 0.5% liquidity (1% total)

### Distribution
- Community: 50%
- Liquidity: 30%
- Development: 15%
- Founders: 5%

### Vesting Schedule
- Cliff Period: 1 year
- Vesting Period: 4 years
- Linear vesting after cliff

### Security Features
- Multi-signature governance (2-10 owners)
- Minimum 2 signatures required
- 24-hour operation delay
- 1-hour signature timeout
- Anti-whale threshold: 500,000 tokens

## Deployment Guide (Remix)

1. Load the contract files into Remix
2. Select compiler settings:
   - Solidity version: 0.8.20
   - Enable optimizer: 200 runs

3. Deploy using 'Deploy with Proxy'
   - Contract: CustomToken
   - Initialize with parameters:
     - _owners: Array of initial owner addresses
     - _requiredSignatures: Number of required signatures (min 2)
     - _marketingWallet: Marketing fee collection address
     - _liquidityPool: Liquidity pool address

## Security

This contract includes several security features:

- OpenZeppelin security contracts
- Reentrancy protection
- Overflow protection (Solidity 0.8+)
- Multi-signature requirements
- Timelock for critical operations
- Emergency pause functionality

⚠️ This contract has not been audited. Use at your own risk.

## License

MIT License - see LICENSE.md

## Contact

Jaden Chilton - [@anyonmus1](https://x.com/keepcalm_dev_on)

Project Link: [https://github.com/anyonmus1/multisig-token-for-L2](https://github.com/anyonmus1/multisig-token-for-L2)

