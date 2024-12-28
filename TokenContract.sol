// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title CustomToken - Advanced ERC20 Implementation
 * @author Your Name
 * @notice A feature-rich, upgradeable ERC20 token with vesting, multi-sig, and anti-whale mechanisms
 * @dev UUPS-upgradeable implementation using OpenZeppelin contracts
 * 
 * Features:
 * - UUPS Upgradeable
 * - Multi-signature governance
 * - Token vesting with cliff
 * - Anti-whale mechanism
 * - Blacklist functionality
 * - Emergency pause
 * - Automatic fee collection
 * - Liquidity locking
 * 
 * Note: This implementation requires OpenZeppelin 4.8.0 contracts
 */

//==================== OpenZeppelin Upgradeable Imports ====================//
import "@openzeppelin/contracts-upgradeable@4.8.0/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable@4.8.0/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable@4.8.0/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable@4.8.0/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable@4.8.0/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable@4.8.0/proxy/utils/UUPSUpgradeable.sol";

//==================== Standard OpenZeppelin Imports ====================//
import "@openzeppelin/contracts@4.8.0/interfaces/IERC20.sol";
import "@openzeppelin/contracts@4.8.0/utils/cryptography/ECDSA.sol";

//==================== Internal Library ====================//
import "./TokenLib.sol";

/*////////////////////////////////////////////////////////////
//                     CUSTOM ERRORS
////////////////////////////////////////////////////////////*/
error Blacklisted();
error Finalized();
error ZeroAddress();
error InvalidSignature();
error MintingDisabledErr();
error ExceedsSupply();
error NotAllSupplyMinted();
error LiquidityLockedErr();
error CliffNotReached();
error NothingToClaim();
error DistributionMismatch();
error InvalidOwner();
error AlreadyOwner();
error DuplicateOwner();
error TooFewOwners();
error TooManyOwners();
error InvalidSignaturesErr();
error NotAnOwner();
error NotBlacklisted();
error AlreadyBlacklisted();
error ExceedsLimit();
error PausedTransfers();
error InvalidRevert();
error InvalidReqSignatures();
error SignaturesExpired();
error TransferFromZero();
error TransferToZero();
error ZeroAmount();

contract CustomToken is
    Initializable,
    ERC20Upgradeable,
    OwnableUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable
{
    using ECDSA for bytes32;

    /*////////////////////////////////////////////////////////////
                           CONSTANTS & STORAGE
    ////////////////////////////////////////////////////////////*/

    // ------------------ Token & Fees ------------------ //
    uint256 public constant TOTAL_SUPPLY = 10_000_000_000 * 10**18;
    uint256 public constant MAX_TRANSFER_AMOUNT = TOTAL_SUPPLY / 50; // 2% of total supply
    uint256 public constant MAX_FEE = 1000; // 10% max combined
    uint256 public constant MARKETING_FEE = 50; // 0.5%
    uint256 public constant LIQUIDITY_FEE = 50; // 0.5%

    // ------------------ Vesting ------------------ //
    uint256 public constant CLIFF_PERIOD = 365 days; // 1 year
    uint256 public constant VESTING_PERIOD = 1460 days; // 4 years

    // ------------------ Liquidity Lock ------------------ //
    uint256 public constant LIQUIDITY_LOCK_PERIOD = 365 days; // 1 year

    // ------------------ Distribution Splits (%) ------------------ //
    uint256 private constant COMMUNITY_PERCENTAGE = 50; // 50%
    uint256 private constant LIQUIDITY_PERCENTAGE = 30; // 30%
    uint256 private constant DEVELOPMENT_PERCENTAGE = 15; // 15%
    uint256 private constant FOUNDER_PERCENTAGE = 5; // 5%

    // ------------------ Multi-Sig ------------------ //
    uint256 public constant MAX_OWNERS = 10;
    uint256 public constant MIN_SIGNATURES = 2;
    uint256 public requiredSignatures;
    uint256 public constant OPERATION_DELAY = 24 hours;
    uint256 public constant SIGNATURE_TIMEOUT = 1 hours;

    // ------------------ UUPS ------------------ //
    bool private _initialized;
    bool private _finalized;
    bool private _mintingDisabled;

    // ------------------ Core Addresses ------------------ //
    address public marketingWallet;
    address public liquidityPool;

    // ------------------ Vesting Data ------------------ //
    struct VestingInfo {
        uint256 startTime;
        uint256 totalAmount;
        uint256 claimedAmount;
        bool initialized;
    }
    mapping(address => VestingInfo) public vestingInfo;

    // ------------------ Liquidity Lock Data ------------------ //
    struct LiquidityLock {
        uint256 unlockTime;
        bool isLocked;
    }
    LiquidityLock public liquidityLock;

    // ------------------ Multi-Owner (Multi-Sig) ------------------ //
    address[] public owners;
    mapping(address => bool) public isOwner;

    // ------------------ Blacklist ------------------ //
    mapping(address => bool) public isBlacklisted;

    // ------------------ Timed Operations ------------------ //
    mapping(bytes32 => uint256) public operationTimestamps;

    // ------------------ Anti-Whale Threshold ------------------ //
    uint256 public constant ANTIWHALE_THRESHOLD = 500_000 * 10**18;

    /*////////////////////////////////////////////////////////////
                           EVENTS
    ////////////////////////////////////////////////////////////*/

    event LiquidityLocked(uint256 unlockTime);
    event LiquidityUnlocked();
    event TokensClaimed(address indexed beneficiary, uint256 amount);
    event FeesCollected(uint256 marketingFee, uint256 liquidityFee);
    event VestingInitialized(address indexed beneficiary, uint256 amount);
    event MintingDisabledEvent();
    event ContractFinalized(uint256 timestamp);
    event RequiredSignaturesChanged(uint256 oldRequired, uint256 newRequired);
    event WalletUpdated(string walletType, address oldWallet, address newWallet);
    event OwnerAdded(address owner);
    event OwnerRemoved(address owner);
    event AddressBlacklistedEvent(address account);
    event AddressUnblacklistedEvent(address account);
    event DebugLog(string key, uint256 value);
    event DebugAddress(string key, address value);

    /*////////////////////////////////////////////////////////////
                           MODIFIERS
    ////////////////////////////////////////////////////////////*/

    modifier notBlacklistedMod(address a) {
        if (isBlacklisted[a]) revert Blacklisted();
        _;
    }

    modifier notFinalizedMod() {
        if (_finalized) revert Finalized();
        _;
    }

    /*////////////////////////////////////////////////////////////
                           CONSTRUCTOR
    ////////////////////////////////////////////////////////////*/

    /// @dev Disables initializers on implementation contract
    constructor() {
        _disableInitializers();
    }

    /*////////////////////////////////////////////////////////////
                           INITIALIZER
    ////////////////////////////////////////////////////////////*/

    /**
     * @notice Initializes the token contract with multi-sig owners and core parameters
     * @param _owners Array of initial multi-sig owners
     * @param _requiredSignatures Number of required signatures for multi-sig operations
     * @param _marketingWallet Address to receive marketing fees
     * @param _liquidityPool Address of the liquidity pool
     */
    function initialize(
        address[] memory _owners,
        uint256 _requiredSignatures,
        address _marketingWallet,
        address _liquidityPool
    ) public initializer {
        // Debug pre-initialization state
        emit DebugAddress("Marketing Wallet", _marketingWallet);
        emit DebugAddress("Liquidity Pool", _liquidityPool);

        // 1. Validate owners array
        if (_owners.length < MIN_SIGNATURES) revert TooFewOwners();
        if (_owners.length > MAX_OWNERS) revert TooManyOwners();
        
        // 2. Validate required signatures
        if (_requiredSignatures < MIN_SIGNATURES || _requiredSignatures > _owners.length) {
            revert InvalidReqSignatures();
        }
        
        // 3. Validate addresses
        if (_marketingWallet == address(0) || _liquidityPool == address(0))
            revert ZeroAddress();

        // Initialize upgradeable base classes
        __ERC20_init("Crypto Custom Token", "CCT");
        __Ownable_init();
        __Pausable_init();
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();

        // Set initial owner
        _transferOwnership(msg.sender);

        requiredSignatures = _requiredSignatures;

        // Setup multi-sig owners
        for (uint i = 0; i < _owners.length; i++) {
            address o = _owners[i];
            if (o == address(0)) revert ZeroAddress();
            if (isOwner[o]) revert DuplicateOwner();

            isOwner[o] = true;
            owners.push(o);
        }

        marketingWallet = _marketingWallet;
        liquidityPool = _liquidityPool;

        // 4. Mint total supply to this contract
        _mint(address(this), TOTAL_SUPPLY);

        // 5. Distributions
        uint256 cAlloc = (TOTAL_SUPPLY * COMMUNITY_PERCENTAGE) / 100;
        uint256 lAlloc = (TOTAL_SUPPLY * LIQUIDITY_PERCENTAGE) / 100;
        uint256 dAlloc = (TOTAL_SUPPLY * DEVELOPMENT_PERCENTAGE) / 100;
        uint256 fAlloc = (TOTAL_SUPPLY * FOUNDER_PERCENTAGE) / 100;

        emit DebugLog("Community Allocation", cAlloc);
        emit DebugLog("Liquidity Allocation", lAlloc);
        emit DebugLog("Development Allocation", dAlloc);
        emit DebugLog("Founder Allocation", fAlloc);

        if (cAlloc + lAlloc + dAlloc + fAlloc != TOTAL_SUPPLY)
            revert DistributionMismatch();

        // 6. Transfer liquidity portion
        _transfer(address(this), liquidityPool, lAlloc);

        // 7. Initialize vesting
        _initializeVesting(_marketingWallet, dAlloc);
        _initializeVesting(msg.sender, fAlloc);

        // 8. Lock liquidity
        liquidityLock.unlockTime = block.timestamp + LIQUIDITY_LOCK_PERIOD;
        liquidityLock.isLocked = true;

        emit LiquidityLocked(liquidityLock.unlockTime);
        _initialized = true;
    }
    /*////////////////////////////////////////////////////////////
                       UUPS UPGRADE AUTH
    ////////////////////////////////////////////////////////////*/

    /**
     * @dev Restricts who can upgrade (multi-sig).
     */
    function _authorizeUpgrade(address newImplementation)
        internal
        view
        override
    {
        require(newImplementation != address(0), "Implementation cannot be zero");
        if (!isOwner[msg.sender]) revert NotAnOwner();
    }

    /*////////////////////////////////////////////////////////////
                           VESTING
    ////////////////////////////////////////////////////////////*/

    function _initializeVesting(address b, uint256 amt) internal {
        if (b == address(0)) revert ZeroAddress();
        if (amt == 0) revert ZeroAmount();
        if (vestingInfo[b].initialized) revert InvalidRevert();

        vestingInfo[b] = VestingInfo({
            startTime:      block.timestamp,
            totalAmount:    amt,
            claimedAmount:  0,
            initialized:    true
        });

        emit VestingInitialized(b, amt);
    }

    function claimVestedTokens() external nonReentrant notBlacklistedMod(msg.sender) {
        VestingInfo storage info = vestingInfo[msg.sender];
        if (!info.initialized) revert InvalidRevert();
        if (block.timestamp < info.startTime + CLIFF_PERIOD) revert CliffNotReached();

        uint256 vested = TokenLib.calculateVestedAmount(
            info.startTime,
            info.totalAmount,
            info.claimedAmount,
            CLIFF_PERIOD,
            VESTING_PERIOD,
            block.timestamp
        );
        if (vested == 0) revert NothingToClaim();

        info.claimedAmount += vested;
        _transfer(address(this), msg.sender, vested);
        emit TokensClaimed(msg.sender, vested);
    }

    /*////////////////////////////////////////////////////////////
                       OVERRIDE _TRANSFER
    ////////////////////////////////////////////////////////////*/

    /**
     * @dev Anti-whale logic + fees + liquidity lock checks
     */
    function _transfer(
        address s,
        address r,
        uint256 amt
    )
        internal
        virtual
        override
        notBlacklistedMod(s)
        notBlacklistedMod(r)
    {
        emit DebugAddress("Sender", s);
        emit DebugAddress("Recipient", r);

        if (s == address(0)) revert TransferFromZero();
        if (r == address(0)) revert TransferToZero();
        if (amt == 0) revert ZeroAmount();
        if (paused()) revert PausedTransfers();

        emit DebugLog("Transfer Amount", amt);

        // 1) Anti-whale check
        bool isOwnerTx = (isOwner[s] || isOwner[r]);
        // If the sender is this contract (e.g. distributing tokens after mint),
        // skip the anti-whale check to avoid "ExceedsLimit" on distributions.
        bool skipAntiWhale = (s == address(this));

        if (!isOwnerTx && !skipAntiWhale) {
            uint256 senderBalance = balanceOf(s);

            emit DebugLog("Sender Balance", senderBalance);
            emit DebugLog("Anti-Whale Threshold", ANTIWHALE_THRESHOLD);

            if (senderBalance <= ANTIWHALE_THRESHOLD) {
                emit DebugLog("Allowed to transfer full balance", senderBalance);
                if (amt > senderBalance) revert ExceedsLimit();
            } else {
                uint256 halfBalance = senderBalance / 2;
                uint256 maxAllowed = (halfBalance < MAX_TRANSFER_AMOUNT)
                    ? halfBalance
                    : MAX_TRANSFER_AMOUNT;

                emit DebugLog("Max Allowed Transfer", maxAllowed);
                if (amt > maxAllowed) revert ExceedsLimit();
            }
        }

        // 2) Liquidity lock check
        if ((s == liquidityPool || r == liquidityPool) && liquidityPool != address(0)) {
            emit DebugLog("Liquidity Pool Check", block.timestamp);
            emit DebugLog("Liquidity Unlock Time", liquidityLock.unlockTime);

            if (liquidityLock.isLocked && block.timestamp < liquidityLock.unlockTime) {
                revert LiquidityLockedErr();
            }
        }

        // 3) Fee logic
        uint256 xferAmt = amt;
        if (s != address(this) && r != address(this)) {
            bool feesOk = TokenLib.validateFees(MARKETING_FEE, LIQUIDITY_FEE, MAX_FEE);
            emit DebugLog("Fees Valid?", feesOk ? 1 : 0);

            if (!feesOk) revert ExceedsLimit();

            (uint256 mFee, uint256 lFee, uint256 net) =
                TokenLib.calculateFees(amt, MARKETING_FEE, LIQUIDITY_FEE);

            emit DebugLog("Marketing Fee", mFee);
            emit DebugLog("Liquidity Fee", lFee);
            emit DebugLog("Net Transfer Amount", net);

            // If fees exceed the amount, zero them out
            if (mFee + lFee > amt) {
                mFee = 0;
                lFee = 0;
                net = amt;
            }

            // Transfer fees if any
            if (mFee > 0) super._transfer(s, marketingWallet, mFee);
            if (lFee > 0) super._transfer(s, liquidityPool, lFee);

            if (mFee + lFee > 0) {
                emit FeesCollected(mFee, lFee);
            }

            xferAmt = net;
        }

        // 4) Perform actual transfer
        super._transfer(s, r, xferAmt);
    }

    /*////////////////////////////////////////////////////////////
                       MULTI-SIG & BLACKLIST
    ////////////////////////////////////////////////////////////*/

    function addOwner(address o, bytes[] memory sigs) external {
        bytes32 h = keccak256(abi.encodePacked("addOwner", o, block.timestamp));
        if (!isValidSignature(h, sigs, block.timestamp)) revert InvalidSignature();
        if (isOwner[o]) revert AlreadyOwner();
        if (o == address(0)) revert ZeroAddress();
        if (owners.length >= MAX_OWNERS) revert TooManyOwners();

        isOwner[o] = true;
        owners.push(o);
        emit OwnerAdded(o);
    }

    function removeOwner(address o, bytes[] memory sigs) external {
        bytes32 h = keccak256(abi.encodePacked("removeOwner", o, block.timestamp));
        if (!isValidSignature(h, sigs, block.timestamp)) revert InvalidSignature();
        if (!isOwner[o]) revert NotAnOwner();
        if (owners.length <= requiredSignatures) revert InvalidRevert();

        isOwner[o] = false;
        for (uint i; i < owners.length; i++) {
            if (owners[i] == o) {
                owners[i] = owners[owners.length - 1];
                owners.pop();
                break;
            }
        }
        emit OwnerRemoved(o);
    }

    function updateRequiredSignatures(uint256 newReq, bytes[] memory sigs) external {
        bytes32 h = keccak256(
            abi.encodePacked("updateRequiredSignatures", newReq, block.timestamp)
        );
        if (!isValidSignature(h, sigs, block.timestamp)) revert InvalidSignature();
        if (newReq < MIN_SIGNATURES || newReq > owners.length) revert InvalidReqSignatures();

        uint256 old = requiredSignatures;
        requiredSignatures = newReq;
        emit RequiredSignaturesChanged(old, newReq);
    }

    function addToBlacklist(address a, bytes[] memory sigs) external {
        bytes32 h = keccak256(
            abi.encodePacked("addToBlacklist", a, block.timestamp)
        );
        if (!isValidSignature(h, sigs, block.timestamp)) revert InvalidSignature();
        if (isBlacklisted[a]) revert AlreadyBlacklisted();

        isBlacklisted[a] = true;
        emit AddressBlacklistedEvent(a);
    }

    function removeFromBlacklist(address a, bytes[] memory sigs) external {
        bytes32 h = keccak256(
            abi.encodePacked("removeFromBlacklist", a, block.timestamp)
        );
        if (!isValidSignature(h, sigs, block.timestamp)) revert InvalidSignature();
        if (!isBlacklisted[a]) revert NotBlacklisted();

        isBlacklisted[a] = false;
        emit AddressUnblacklistedEvent(a);
    }

    function areAddressesBlacklisted(address[] calldata ac)
        external
        view
        returns (bool[] memory)
    {
        bool[] memory out = new bool[](ac.length);
        for (uint i; i < ac.length; i++) {
            out[i] = isBlacklisted[ac[i]];
        }
        return out;
    }

    /*////////////////////////////////////////////////////////////
                        TIMED OPERATIONS
    ////////////////////////////////////////////////////////////*/

    function queueOperation(bytes32 opId) internal {
        operationTimestamps[opId] = block.timestamp + OPERATION_DELAY;
    }

    function isOperationReady(bytes32 opId) external view returns (bool rdy, uint256 t) {
        t = operationTimestamps[opId];
        rdy = (t != 0 && block.timestamp >= t);
    }

    /*////////////////////////////////////////////////////////////
                    EMERGENCY RECOVERY
    ////////////////////////////////////////////////////////////*/

    function recoverERC20(address tok, uint256 amt, bytes[] memory sigs) external {
        bytes32 h = keccak256(
            abi.encodePacked("recoverERC20", tok, amt, block.timestamp)
        );
        if (!isValidSignature(h, sigs, block.timestamp)) revert InvalidSignature();
        if (amt == 0) revert ZeroAmount();
        if (tok == address(this)) revert InvalidRevert();
        if (IERC20(tok).balanceOf(address(this)) < amt) revert ExceedsLimit();

        IERC20(tok).transfer(owner(), amt);
    }

    /*////////////////////////////////////////////////////////////
                  SIGNATURE VALIDATION
    ////////////////////////////////////////////////////////////*/

    function isValidSignature(
        bytes32 hash,
        bytes[] memory sigs,
        uint256 ts
    )
        internal
        view
        returns (bool)
    {
        if (sigs.length < requiredSignatures || sigs.length > owners.length)
            revert InvalidSignaturesErr();
        if (block.timestamp > ts + SIGNATURE_TIMEOUT) revert SignaturesExpired();

        address[] memory rec = new address[](sigs.length);
        for (uint i; i < sigs.length; i++) {
            bytes32 ethHash = hash.toEthSignedMessageHash();
            address signer = ethHash.recover(sigs[i]);
            if (!isOwner[signer]) revert NotAnOwner();

            // Check for duplicate signers
            for (uint j; j < i; j++) {
                if (rec[j] == signer) revert InvalidSignature();
            }
            rec[i] = signer;
        }
        return true;
    }

    /*////////////////////////////////////////////////////////////
                  MINTING & FINALIZATION
    ////////////////////////////////////////////////////////////*/

    function _mint(address to, uint256 amt) internal virtual override {
        if (_mintingDisabled) revert MintingDisabledErr();
        if (_finalized) revert Finalized();
        if (totalSupply() + amt > TOTAL_SUPPLY) revert ExceedsSupply();

        super._mint(to, amt);
    }

    function disableMinting(bytes[] memory sigs) external notFinalizedMod {
        bytes32 h = keccak256(abi.encodePacked("disableMinting", block.timestamp));
        if (!isValidSignature(h, sigs, block.timestamp)) revert InvalidSignature();
        if (_mintingDisabled) revert MintingDisabledErr();
        if (totalSupply() != TOTAL_SUPPLY) revert NotAllSupplyMinted();

        _mintingDisabled = true;
        emit MintingDisabledEvent();
    }

    function finalizeContract(bytes[] memory sigs) external notFinalizedMod {
        bytes32 h = keccak256(abi.encodePacked("finalizeContract", block.timestamp));
        if (!isValidSignature(h, sigs, block.timestamp)) revert InvalidSignature();
        if (totalSupply() != TOTAL_SUPPLY) revert NotAllSupplyMinted();
        if (marketingWallet == address(0) || liquidityPool == address(0)) revert ZeroAddress();
        if (owners.length < requiredSignatures) revert InvalidReqSignatures();

        _mintingDisabled = true;
        _finalized = true;
        emit ContractFinalized(block.timestamp);
    }

    /*////////////////////////////////////////////////////////////
                     GOVERNANCE & PAUSE
    ////////////////////////////////////////////////////////////*/

    function updateMarketingWallet(address w, bytes[] memory sigs) external {
        bytes32 h = keccak256(
            abi.encodePacked("updateMarketingWallet", w, block.timestamp)
        );
        if (!isValidSignature(h, sigs, block.timestamp)) revert InvalidSignature();
        if (w == address(0)) revert ZeroAddress();

        address old = marketingWallet;
        marketingWallet = w;
        emit WalletUpdated("Marketing", old, w);
    }

    function updateLiquidityPool(address w, bytes[] memory sigs) external {
        bytes32 h = keccak256(
            abi.encodePacked("updateLiquidityPool", w, block.timestamp)
        );
        if (!isValidSignature(h, sigs, block.timestamp)) revert InvalidSignature();
        if (w == address(0)) revert ZeroAddress();

        // Check lock status
        if (liquidityLock.isLocked && block.timestamp < liquidityLock.unlockTime) {
            revert LiquidityLockedErr();
        }

        address old = liquidityPool;
        liquidityPool = w;
        emit WalletUpdated("Liquidity", old, w);
    }

    function pauseToken(bytes[] memory sigs) external {
        bytes32 h = keccak256(abi.encodePacked("pause", block.timestamp));
        if (!isValidSignature(h, sigs, block.timestamp)) revert InvalidSignature();
        if (paused()) revert InvalidRevert();

        _pause();
    }

    function unpauseToken(bytes[] memory sigs) external {
        bytes32 h = keccak256(abi.encodePacked("unpause", block.timestamp));
        if (!isValidSignature(h, sigs, block.timestamp)) revert InvalidSignature();
        if (!paused()) revert InvalidRevert();

        _unpause();
    }

    /*////////////////////////////////////////////////////////////
                      VIEW FUNCTIONS
    ////////////////////////////////////////////////////////////*/

    function isInitialized() external view returns (bool) {
        return _initialized;
    }

    function isFinalized() external view returns (bool) {
        return _finalized;
    }

    function isMintingDisabled() external view returns (bool) {
        return _mintingDisabled;
    }

    function getOwners() external view returns (address[] memory) {
        return owners;
    }

    function getVestingInfo(address b)
        external
        view
        returns (
            uint256 startTime,
            uint256 totalAmount,
            uint256 claimedAmount,
            uint256 claimableAmount
        )
    {
        VestingInfo memory info = vestingInfo[b];
        startTime = info.startTime;
        totalAmount = info.totalAmount;
        claimedAmount = info.claimedAmount;
        claimableAmount = TokenLib.calculateVestedAmount(
            info.startTime,
            info.totalAmount,
            info.claimedAmount,
            CLIFF_PERIOD,
            VESTING_PERIOD,
            block.timestamp
        );
    }

    function getLiquidityLockInfo()
        external
        view
        returns (
            bool locked,
            uint256 unlockTime,
            uint256 remain
        )
    {
        locked = liquidityLock.isLocked;
        unlockTime = liquidityLock.unlockTime;
        remain = TokenLib.calculateLockTimeRemaining(
            unlockTime,
            block.timestamp
        );
    }
}