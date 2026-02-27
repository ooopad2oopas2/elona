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
