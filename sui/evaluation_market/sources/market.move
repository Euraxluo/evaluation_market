module evaluation_market::market {
    use std::string::String;
    use sui::object::{Self, UID};
    use std::vector;
    use sui::tx_context::{Self, TxContext};
    use sui::event;
    use sui::transfer;
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;

    // 错误码
    const EInvalidPrice: u64 = 0;
    const EInvalidOrderSize: u64 = 1;
    const EMarketNotActive: u64 = 2;
    const EInvalidOutcome: u64 = 3;
    const EMarketResolved: u64 = 4;
    const ENotCreator: u64 = 5;

    // 常量
    const BASIS_POINTS: u64 = 10000;
    const MIN_PRICE: u64 = 100;      // 1%
    const MAX_PRICE: u64 = 9900;     // 99%
    const MIN_ORDER_SIZE: u64 = 100;  // 最小订单大小

    // 市场状态
    struct BondingCurve has store {
        target: u64,          // 目标金额
        duration: u64,        // 持续时间
        base_price: u64,      // 基础价格
        current_price: u64,   // 当前价格
        total_volume: u64     // 总交易量
    }

    // 市场结果
    struct Outcome has store {
        id: u64,             // 结果ID
        name: String,        // 结果名称
        volume: u64,         // 交易量
        price: u64           // 当前价格
    }

    // 订单记录
    struct Order has store {
        trader: address,     // 交易者
        outcome_id: u64,     // 结果ID
        amount: u64,         // 数量
        price: u64,         // 价格
        timestamp: u64      // 时间戳
    }

    // 市场对象
    struct Market has key, store {
        id: UID,
        token: String,                    // 代币类型
        evaluation_id: address,           // 关联的评估ID
        bonding_curve: BondingCurve,      // 债券曲线
        outcomes: vector<Outcome>,         // 可能的结果
        orders: vector<Order>,             // 订单历史
        is_active: bool,                   // 市场是否活跃
        is_resolved: bool,                 // 市场是否已解决
        winning_outcome: u64,              // 获胜结果
        creator: address,                  // 创建者
        start_time: u64,                   // 开始时间
        end_time: u64                      // 结束时间
    }

    // 事件定义
    struct MarketCreated has copy, drop {
        market_id: address,
        evaluation_id: address,
        token: String,
        start_time: u64,
        end_time: u64
    }

    struct OrderPlaced has copy, drop {
        market_id: address,
        trader: address,
        outcome_id: u64,
        amount: u64,
        price: u64
    }

    struct MarketResolved has copy, drop {
        market_id: address,
        winning_outcome: u64,
        final_price: u64
    }

    // === 内部构造函数 ===

    // 创建新市场
    fun new_market(
        token: String,
        evaluation_id: address,
        bonding_target: u64,
        bonding_duration: u64,
        base_price: u64,
        creator: address,
        ctx: &mut TxContext
    ): Market {
        let start_time = tx_context::epoch(ctx);
        
        Market {
            id: object::new(ctx),
            token,
            evaluation_id,
            bonding_curve: BondingCurve {
                target: bonding_target,
                duration: bonding_duration,
                base_price,
                current_price: base_price,
                total_volume: 0
            },
            outcomes: vector::empty(),
            orders: vector::empty(),
            is_active: true,
            is_resolved: false,
            winning_outcome: 0,
            creator,
            start_time,
            end_time: start_time + bonding_duration
        }
    }

    // 创建新结果
    fun new_outcome(id: u64, name: String): Outcome {
        Outcome {
            id,
            name,
            volume: 0,
            price: 0
        }
    }

    // 创建新订单
    fun new_order(
        trader: address,
        outcome_id: u64,
        amount: u64,
        price: u64,
        timestamp: u64
    ): Order {
        Order {
            trader,
            outcome_id,
            amount,
            price,
            timestamp
        }
    }

    // === 公共函数 ===

    // 创建市场
    public fun create_market(
        token: String,
        evaluation_id: address,
        bonding_target: u64,
        bonding_duration: u64,
        base_price: u64,
        ctx: &mut TxContext
    ): Market {
        let creator = tx_context::sender(ctx);
        let market = new_market(
            token,
            evaluation_id,
            bonding_target,
            bonding_duration,
            base_price,
            creator,
            ctx
        );

        event::emit(MarketCreated {
            market_id: object::uid_to_address(&market.id),
            evaluation_id: market.evaluation_id,
            token: market.token,
            start_time: market.start_time,
            end_time: market.end_time
        });

        market
    }

    // 添加结果选项
    public fun add_outcome(
        market: &mut Market,
        name: String,
        ctx: &TxContext
    ) {
        assert!(tx_context::sender(ctx) == market.creator, ENotCreator);
        let id = vector::length(&market.outcomes);
        vector::push_back(&mut market.outcomes, new_outcome(id, name));
    }

    // 下限价单
    public fun place_limit_order(
        market: &mut Market,
        outcome_id: u64,
        amount: u64,
        price: u64,
        payment: Coin<SUI>,
        ctx: &mut TxContext
    ) {
        // 验证市场状态
        assert!(market.is_active, EMarketNotActive);
        assert!(!market.is_resolved, EMarketResolved);
        
        // 验证订单参数
        assert!(outcome_id < vector::length(&market.outcomes), EInvalidOutcome);
        assert!(amount >= MIN_ORDER_SIZE, EInvalidOrderSize);
        assert!(price >= MIN_PRICE && price <= MAX_PRICE, EInvalidPrice);

        // 更新结果状态
        let outcome = vector::borrow_mut(&mut market.outcomes, outcome_id);
        outcome.volume = outcome.volume + amount;
        outcome.price = price;

        // 更新债券曲线
        let curve = &mut market.bonding_curve;
        curve.total_volume = curve.total_volume + amount;
        curve.current_price = calculate_current_price(curve);

        // 记录订单
        let trader = tx_context::sender(ctx);
        let timestamp = tx_context::epoch(ctx);
        vector::push_back(
            &mut market.orders,
            new_order(trader, outcome_id, amount, price, timestamp)
        );

        // 发出事件
        event::emit(OrderPlaced {
            market_id: object::uid_to_address(&market.id),
            trader,
            outcome_id,
            amount,
            price
        });

        // 处理支付
        transfer::public_transfer(payment, market.creator);
    }

    // 解决市场
    public fun resolve_market(
        market: &mut Market,
        winning_outcome: u64,
        ctx: &TxContext
    ) {
        assert!(tx_context::sender(ctx) == market.creator, ENotCreator);
        assert!(!market.is_resolved, EMarketResolved);
        assert!(winning_outcome < vector::length(&market.outcomes), EInvalidOutcome);

        market.is_resolved = true;
        market.winning_outcome = winning_outcome;
        market.is_active = false;

        let outcome = vector::borrow(&market.outcomes, winning_outcome);
        event::emit(MarketResolved {
            market_id: object::uid_to_address(&market.id),
            winning_outcome,
            final_price: outcome.price
        });
    }

    // === 内部函数 ===

    // 计算当前价格
    fun calculate_current_price(curve: &BondingCurve): u64 {
        let progress = (curve.total_volume * BASIS_POINTS) / curve.target;
        if (progress >= BASIS_POINTS) {
            return curve.base_price
        };
        curve.base_price + ((MAX_PRICE - curve.base_price) * progress) / BASIS_POINTS
    }

    // === 测试函数 ===
    #[test_only]
    public fun create_test_market(
        token: String,
        evaluation_id: address,
        bonding_target: u64,
        bonding_duration: u64,
        base_price: u64,
        creator: address,
        ctx: &mut TxContext
    ): Market {
        new_market(token, evaluation_id, bonding_target, bonding_duration, base_price, creator, ctx)
    }

    #[test_only]
    public fun create_test_outcome(id: u64, name: String): Outcome {
        new_outcome(id, name)
    }

    // === 测试辅助函数 ===
    #[test_only]
    public fun get_market_fields(market: &Market): (address, bool, bool, u64, u64, u64) {
        (
            market.evaluation_id,
            market.is_active,
            market.is_resolved,
            market.winning_outcome,
            vector::length(&market.outcomes),
            vector::length(&market.orders)
        )
    }

    #[test_only]
    public fun get_outcome_fields(outcome: &Outcome): (u64, String, u64, u64) {
        (
            outcome.id,
            *&outcome.name,
            outcome.volume,
            outcome.price
        )
    }

    #[test_only]
    public fun get_curve_fields(curve: &BondingCurve): (u64, u64, u64, u64, u64) {
        (
            curve.target,
            curve.duration,
            curve.base_price,
            curve.current_price,
            curve.total_volume
        )
    }

    #[test_only]
    public fun get_bonding_curve_fields(market: &Market): (u64, u64, u64, u64, u64) {
        get_curve_fields(&market.bonding_curve)
    }

    #[test_only]
    public fun get_outcomes(market: &Market): &vector<Outcome> {
        &market.outcomes
    }

    #[test_only]
    public fun get_orders(market: &Market): &vector<Order> {
        &market.orders
    }
} 