// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.26;

/**
 * @title IAetherRing v3
 * @dev AetherGovernance / AetherElection / AetherDonation 依赖的接口
 *
 *  v3.2 (M11): 将 RingTier / RingInfo 类型 + 写入方法纳入接口，
 *              消除依赖合约中的 `AetherRing(address(ringContract))` 强转调用，
 *              使 mock 测试与未来代理升级不再因强转而 revert。
 */
interface IAetherRing {
    // ──────────── 14 级权级枚举 ────────────
    enum RingTier {
        NONE, // 0
        PARLIAMENT_MEMBER, // 1  议员（议会基层）
        PARLIAMENT_SENIOR, // 2  参议员（议会中层）
        PARLIAMENT_SPEAKER, // 3  议长（议会高层）
        FEDERATION_MEMBER, // 4  委员（联邦基层）
        FEDERATION_SENIOR, // 5  委员长（联邦中层）
        FEDERATION_MINISTER, // 6  执政（联邦高层）
        TRIBUNAL_JUDGE, // 7  法官（法庭基层）
        TRIBUNAL_SENIOR, // 8  大法官（法庭中层）
        TRIBUNAL_CHIEF, // 9  首席（法庭高层）
        COUNCIL_MEMBER, // 10 理事（理事会基层）
        COUNCIL_SENIOR, // 11 常务理事（理事会中层）
        COUNCIL_CHAIR, // 12 理事长（理事会高层）
        ELDER, // 13 元老（独立机构）
        CITIZEN // 14 公民（基金会成员）
    }

    // ──────────── 数据结构 ────────────
    struct RingInfo {
        RingTier tier;
        uint64 mintedAt;
        uint64 termEndAt; // 任期结束时间；高层/元老/公民为 type(uint64).max
        uint8 consecutiveTerms; // 已连任次数（v3 始终为 0，保留字段兼容）
        bool isActive; // 投票/提案权限
        bool isEmeritus; // 退休标记（退休元老）
        bool isExpired; // 任期到期标记
        string covenantHash;
        uint64 lastActivityAt; // 最后一次治理活动时间（休眠判断用，仅公民）
        bool isDormant; // 是否休眠（仅公民）
        bool isRetiredElder; // 退休元老（无治理权）
        bool isAppointedElder; // 任命元老（有治理权）
    }

    // ──────────── 查询 ────────────

    /// @notice 检查地址是否持有有效道环（活跃 + 未到期 + 非退休 + 非休眠）
    function isBearer(address holder) external view returns (bool);

    /// @notice 获取地址的权级编码（0=无，1-14 对应 RingTier）
    function getTier(address holder) external view returns (uint8);

    /// @notice 获取地址持有的道环 tokenId（0 表示无）
    function getRingId(address holder) external view returns (uint256);

    /// @notice 获取活跃公民总数（用于治理 quorum 分母，排除休眠公民）
    function getActiveCitizens() external view returns (uint256);

    /// @notice 获取公民总数（含休眠，审计用）
    function getTotalCitizens() external view returns (uint256);

    /// @notice 检查 tokenId 是否已到期（被动失效）
    function isExpired(uint256 tokenId) external view returns (bool);

    /// @notice 检查地址是否为任命元老（有治理权：否决/弹劾）
    function isElderActive(address holder) external view returns (bool);

    /// @notice 检查地址是否为退休元老（仅名誉，无治理权）
    function isRetiredElder(address holder) external view returns (bool);

    /// @notice 检查公民是否休眠
    function isDormant(address holder) external view returns (bool);

    /// @notice 检查地址是否可重新获取公民身份（30 天冷却期）
    function canReacquireCitizenship(address user) external view returns (bool);

    /// @notice 获取道环完整信息（用于选举资格判断等，返回原始 tier 不受 isActive 影响）
    function getRingInfo(uint256 tokenId) external view returns (RingInfo memory);

    // ──────────── 写入（由 Governance / Election / Donation 合约调用） ────────────

    /// @notice 治理活动回调（由 Governance/Election 合约调用，更新公民最后活动时间）
    function markVoteActivity(address voter) external;

    /// @notice 铸造道环（由 Election / Donation 调用）
    function mintRing(address recipient, RingTier tier, string calldata covenantHash)
        external
        returns (uint256);

    /// @notice 升级道环 tier（由 Election 调用）
    function updateTier(uint256 tokenId, RingTier newTier, bool resetTerm) external;

    /// @notice 撤销道环（由 Governance 弹劾执行 / Admin 调用）
    function revokeRing(uint256 tokenId) external;

    /// @notice 任命元老（由 Admin/Safe 调用）
    function appointElder(address candidate, string calldata covenantHash) external;

    /// @notice 重新激活休眠公民（由 Donation 调用）
    function reactivateDormantCitizen(address voter) external;
}
