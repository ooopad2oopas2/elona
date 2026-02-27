// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/*
 * Elona — institutional tide-lines and governance radar.
 * This contract tracks institution identifiers, trend snapshots, and rolling aggregates
 * for large allocators across regions, designed for long-horizon mainnet deployments.
 * It is intentionally verbose to provide rich view functions for off-chain infra.
 */

contract Elona {
    // Core constants and salts (unique)
    uint256 public constant ELN_VERSION = 1;
    uint256 public constant ELN_MAX_INSTITUTIONS = 4096;
    uint256 public constant ELN_MAX_SNAPSHOTS_PER_INST = 8192;
    uint256 public constant ELN_VIEW_BATCH = 96;
    uint256 public constant ELN_WINDOW_DAYS = 30;

    bytes32 public constant ELN_DOMAIN_SALT =
        bytes32(
            uint256(
                0x5c9e1a7f3b2d8046c1d7e0f4a3b8c5d9e2074f3c9b5a6d1e8c4b0f9271a3d6c8
            )
        );
    bytes32 public constant ELN_FLOW_FEED_SALT =
        bytes32(
            uint256(
                0x3a7d2c9f1e4b8065d2f7a1c3e9b4f0a6c8d2e7f1b3a5c9e0f4d1a6b8c3e7d9
            )
        );

    // Immutable control addresses (unique constructor set)
    address public immutable governance;
    address public immutable flowOracle;
    address public immutable feeSink;
    address public immutable sentinel;

    uint256 public snapshotFeeWei;

    struct InstitutionMeta {
        bool active;
        uint64 onboardedAt;
        uint32 regionCode;
        uint8 riskTier;
        bytes32 primaryTag;
        bytes32[] tags;
    }

    struct TrendSnapshot {
        uint64 timestamp;
        int32 netFlowBps;
        uint64 notionalUsdScaled;
        int32 sentimentScore;
        uint32 horizonDays;
        bytes32 labelHash;
    }

    struct InstitutionAggregates {
        int256 cumulativeNetFlowBps;
        uint256 totalSnapshots;
        uint256 lastSnapshotIndex;
        uint64 lastTimestamp;
        uint64 rollingWindowStart;
        uint256 rollingSnapshotCount;
        int256 rollingNetFlowBps;
    }

    mapping(uint256 => InstitutionMeta) private _institutions;
    mapping(uint256 => TrendSnapshot[]) private _snapshots;
    mapping(uint256 => InstitutionAggregates) private _aggregates;
    mapping(address => uint256) private _instIdByAddress;
    mapping(uint256 => address) private _controllerForInst;
    mapping(address => bool) public isReporter;

    uint256 public institutionCount;
    bool public halted;

    // Errors (ELN_ prefix)
    error ELN_NotGovernance();
    error ELN_NotSentinel();
    error ELN_NotReporter();
    error ELN_NotController();
    error ELN_Halted();
    error ELN_ZeroAddress();
    error ELN_MaxInstitutions();
    error ELN_InstitutionNotFound();
    error ELN_MaxSnapshots();
    error ELN_InvalidLabel();
    error ELN_InvalidRegion();
    error ELN_FeeTooHigh();
    error ELN_InvalidRiskTier();
    error ELN_AlreadyReporter();
    error ELN_NotActive();
    error ELN_FeeRequired();
    error ELN_ArrayTooLong();
    error ELN_IndexOutOfRange();

    // Events (ELN_ prefix)
    event GovernanceTransferred(address indexed previousGov, address indexed newGov);
    event ReporterSet(address indexed reporter, bool active);
    event InstitutionOnboarded(
        uint256 indexed instId,
        address indexed controller,
        uint32 regionCode,
        uint8 riskTier,
        bytes32 primaryTag
    );
    event InstitutionDeactivated(uint256 indexed instId);
    event SnapshotRecorded(
        uint256 indexed instId,
        uint256 indexed idx,
        int32 netFlowBps,
        uint64 notionalUsdScaled,
        int32 sentimentScore,
        uint32 horizonDays,
        bytes32 labelHash
    );
    event SnapshotFeeUpdated(uint256 previousFee, uint256 newFee);
    event HaltToggled(bool halted);
    event TagsUpdated(uint256 indexed instId, bytes32[] tags);
    event FeeCollected(address indexed payer, uint256 amountWei);
    event TrendWindowRebased(uint256 indexed instId, uint64 fromTimestamp, uint64 toTimestamp);

    modifier onlyGovernance() {
        if (msg.sender != governance) revert ELN_NotGovernance();
        _;
    }

