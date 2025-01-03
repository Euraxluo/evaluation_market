// sources/config.move
module evaluation_market::config {
    use sui::object::{Self, UID};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use std::string::String;
    use sui::table::{Self, Table};
    use sui::event;

    // 错误码
    const E_NOT_ADMIN: u64 = 1;
    const E_INVALID_FEE: u64 = 2;
    const E_INVALID_AMOUNT: u64 = 3;

    // 管理员权限
    struct AdminCap has key {
        id: UID
    }

    // 市场配置
    struct MarketConfig has key {
        id: UID,
        min_bet: u64,
        max_bet: u64,
        fee_percentage: u64,
        fee_recipient: address,
        supported_tokens: Table<String, bool>,
        paused: bool
    }

    // 配置更新事件
    struct ConfigUpdated has copy, drop {
        min_bet: u64,
        max_bet: u64,
        fee_percentage: u64,
        fee_recipient: address
    }

    // 初始化函数
    fun init(ctx: &mut TxContext) {
        let admin_cap = AdminCap {
            id: object::new(ctx)
        };
        transfer::transfer(admin_cap, tx_context::sender(ctx));

        let market_config = MarketConfig {
            id: object::new(ctx),
            min_bet: 100,
            max_bet: 1000000,
            fee_percentage: 100, // 1%
            fee_recipient: tx_context::sender(ctx),
            supported_tokens: table::new(ctx),
            paused: false
        };
        transfer::share_object(market_config);
    }

    // 更新配置
    public entry fun update_config(
        config: &mut MarketConfig,
        _cap: &AdminCap,
        new_min_bet: u64,
        new_max_bet: u64,
        new_fee_percentage: u64,
        new_fee_recipient: address,
        _ctx: &TxContext
    ) {
        assert!(new_fee_percentage <= 1000, E_INVALID_FEE); // 最大10%
        assert!(new_min_bet < new_max_bet, E_INVALID_AMOUNT);

        config.min_bet = new_min_bet;
        config.max_bet = new_max_bet;
        config.fee_percentage = new_fee_percentage;
        config.fee_recipient = new_fee_recipient;

        event::emit(ConfigUpdated {
            min_bet: new_min_bet,
            max_bet: new_max_bet,
            fee_percentage: new_fee_percentage,
            fee_recipient: new_fee_recipient
        });
    }

    // 添加支持的代币
    public entry fun add_supported_token(
        config: &mut MarketConfig,
        _cap: &AdminCap,
        token: String
    ) {
        table::add(&mut config.supported_tokens, token, true);
    }

    // 移除支持的代币
    public entry fun remove_supported_token(
        config: &mut MarketConfig,
        _cap: &AdminCap,
        token: String
    ) {
        table::remove(&mut config.supported_tokens, token);
    }

    // 暂停/恢复市场
    public entry fun set_paused(
        config: &mut MarketConfig,
        _cap: &AdminCap,
        paused: bool
    ) {
        config.paused = paused;
    }

    // 检查代币是否支持
    public fun is_token_supported(config: &MarketConfig, token: &String): bool {
        table::contains(&config.supported_tokens, *token)
    }

    // 检查金额是否有效
    public fun is_amount_valid(config: &MarketConfig, amount: u64): bool {
        amount >= config.min_bet && amount <= config.max_bet
    }

    // 计算手续费
    public fun calculate_fee(config: &MarketConfig, amount: u64): u64 {
        (amount * config.fee_percentage) / 10000
    }

    // 获取手续费接收者
    public fun fee_recipient(config: &MarketConfig): address {
        config.fee_recipient
    }

    // 检查市场是否暂停
    public fun is_paused(config: &MarketConfig): bool {
        config.paused
    }

    // 获取最小下注金额
    public fun min_bet(config: &MarketConfig): u64 {
        config.min_bet
    }

    // 获取最大下注金额
    public fun max_bet(config: &MarketConfig): u64 {
        config.max_bet
    }

    // 获取手续费百分比
    public fun fee_percentage(config: &MarketConfig): u64 {
        config.fee_percentage
    }

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(ctx)
    }
}