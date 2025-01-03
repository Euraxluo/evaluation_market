#[test_only]
module evaluation_market::market_tests {
    use std::string;
    use std::vector;
    use sui::test_scenario::{Self as test, next_tx, ctx};
    use sui::transfer;
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use evaluation_market::market::{Self, Market};

    // 测试常量
    const ADMIN: address = @0xAD;
    const TRADER1: address = @0xB1;
    const TRADER2: address = @0xB2;
    const EVALUATION_ID: address = @0xE1;

    // 辅助函数：创建基本市场参数
    fun create_basic_market_data(): (string::String, address, u64, u64, u64) {
        (
            string::utf8(b"SUI"),           // token
            EVALUATION_ID,                   // evaluation_id
            1000000,                        // bonding_target
            1000,                           // bonding_duration
            5000                            // base_price (50%)
        )
    }

    // 测试：创建新市场
    #[test]
    fun test_new_market() {
        let scenario = test::begin(ADMIN);
        let (token, evaluation_id, bonding_target, bonding_duration, base_price) = create_basic_market_data();

        next_tx(&mut scenario, ADMIN);
        {
            let market = market::create_market(
                token,
                evaluation_id,
                bonding_target,
                bonding_duration,
                base_price,
                ctx(&mut scenario)
            );

            // 验证市场基本属性
            let (eval_id, is_active, is_resolved, winning_outcome, outcomes_len, orders_len) = 
                market::get_market_fields(&market);

            assert!(eval_id == EVALUATION_ID, 0);
            assert!(is_active == true, 1);
            assert!(is_resolved == false, 2);
            assert!(winning_outcome == 0, 3);
            assert!(outcomes_len == 0, 4);
            assert!(orders_len == 0, 5);

            // 直接解构 bonding_curve_fields
            let (target, duration, base_p, current_price, total_volume) = 
                market::get_bonding_curve_fields(&market);
            
            assert!(target == bonding_target, 6);
            assert!(duration == bonding_duration, 7);
            assert!(base_p == base_price, 8);
            assert!(current_price == base_price, 9);
            assert!(total_volume == 0, 10);

            transfer::public_transfer(market, ADMIN);
        };

        test::end(scenario);
    }

    // 测试：添加结果选项
    #[test]
    fun test_add_outcome() {
        let scenario = test::begin(ADMIN);
        let (token, evaluation_id, bonding_target, bonding_duration, base_price) = create_basic_market_data();

        next_tx(&mut scenario, ADMIN);
        {
            let market = market::create_market(
                token,
                evaluation_id,
                bonding_target,
                bonding_duration,
                base_price,
                ctx(&mut scenario)
            );

            // 添加结果选项
            market::add_outcome(
                &mut market,
                string::utf8(b"Yes"),
                ctx(&mut scenario)
            );

            market::add_outcome(
                &mut market,
                string::utf8(b"No"),
                ctx(&mut scenario)
            );

            // 验证结果选项
            let outcomes = market::get_outcomes(&market);
            assert!(vector::length(outcomes) == 2, 0);

            let (id, name, volume, price) = market::get_outcome_fields(vector::borrow(outcomes, 0));
            assert!(id == 0, 1);
            assert!(name == string::utf8(b"Yes"), 2);
            assert!(volume == 0, 3);
            assert!(price == 0, 4);

            transfer::public_transfer(market, ADMIN);
        };

        test::end(scenario);
    }

    // 测试：下限价单
    #[test]
    fun test_place_limit_order() {
        let scenario = test::begin(ADMIN);
        let (token, evaluation_id, bonding_target, bonding_duration, base_price) = create_basic_market_data();

        // 第一步：管理员创建市场
        next_tx(&mut scenario, ADMIN);
        {
            let market = market::create_market(
                token,
                evaluation_id,
                bonding_target,
                bonding_duration,
                base_price,
                ctx(&mut scenario)
            );
            
            // 添加一些结果选项
            market::add_outcome(&mut market, string::utf8(b"Yes"), ctx(&mut scenario));
            market::add_outcome(&mut market, string::utf8(b"No"), ctx(&mut scenario));
            
            // 将市场转为共享对象
            transfer::public_share_object(market);
        };

        // 第二步：交易者下单
        next_tx(&mut scenario, TRADER1);
        {
            // 创建测试用的 SUI 代币
            let test_coin = coin::mint_for_testing<SUI>(500, ctx(&mut scenario));
            
            // 获取共享的市场对象
            let market = test::take_shared<Market>(&scenario);
            
            // 下限价单 - 注意这里不再使用 &mut coin
            market::place_limit_order(
                &mut market,
                0, // outcome_id = 0 (Yes)
                500, // amount
                6000, // price 60%
                test_coin,  // 直接传入支付代币
                ctx(&mut scenario)
            );

            // 验证订单是否正确创建
            let (_, _, _, _, _, orders_len) = market::get_market_fields(&market);
            assert!(orders_len == 1, 0);

            // 验证结果选项的状态
            let outcomes = market::get_outcomes(&market);
            let outcome = vector::borrow(outcomes, 0);
            let (_, _, volume, price) = market::get_outcome_fields(outcome);
            assert!(volume == 500, 1);
            assert!(price == 6000, 2);

            // 归还市场对象和剩余代币
            test::return_shared(market);
        };

        test::end(scenario);
    }

    // 测试：解决市场
    #[test]
    fun test_resolve_market() {
        let scenario = test::begin(ADMIN);
        let (token, evaluation_id, bonding_target, bonding_duration, base_price) = create_basic_market_data();

        // 创建市场并添加结果选项
        next_tx(&mut scenario, ADMIN);
        {
            let market = market::create_market(
                token,
                evaluation_id,
                bonding_target,
                bonding_duration,
                base_price,
                ctx(&mut scenario)
            );

            market::add_outcome(&mut market, string::utf8(b"Yes"), ctx(&mut scenario));
            market::add_outcome(&mut market, string::utf8(b"No"), ctx(&mut scenario));

            // 解决市场
            market::resolve_market(&mut market, 0, ctx(&mut scenario));

            // 验证市场状态
            let (_, is_active, is_resolved, winning_outcome, _, _) = market::get_market_fields(&market);
            assert!(!is_active, 0);
            assert!(is_resolved, 1);
            assert!(winning_outcome == 0, 2);

            transfer::public_transfer(market, ADMIN);
        };

        test::end(scenario);
    }
} 