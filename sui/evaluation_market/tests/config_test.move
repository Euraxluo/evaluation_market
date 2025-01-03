// tests/config_test.move
#[test_only]
module evaluation_market::config_tests {
    use sui::test_scenario::{Self as test, next_tx, ctx};
    use evaluation_market::config::{Self, AdminCap, MarketConfig};
    use std::string;

    // 测试常量
    const ADMIN: address = @0xAD;
    const NEW_RECIPIENT: address = @0xB2;

    #[test]
    fun test_init_config() {
        let scenario = test::begin(ADMIN);
        
        // 初始化配置
        next_tx(&mut scenario, ADMIN);
        {
            config::init_for_testing(ctx(&mut scenario));
        };

        // 在新的交易中测试配置
        next_tx(&mut scenario, ADMIN);
        {
            let config = test::take_shared<MarketConfig>(&scenario);
            assert!(config::is_amount_valid(&config, 500), 0);
            assert!(!config::is_amount_valid(&config, 50), 1);
            assert!(!config::is_amount_valid(&config, 2000000), 2);
            assert!(!config::is_paused(&config), 3);
            test::return_shared(config);
        };

        test::end(scenario);
    }

    #[test]
    fun test_update_config() {
        let scenario = test::begin(ADMIN);
        
        // 初始化配置
        next_tx(&mut scenario, ADMIN);
        {
            config::init_for_testing(ctx(&mut scenario));
        };

        // 在新的交易中更新配置
        next_tx(&mut scenario, ADMIN);
        {
            let config = test::take_shared<MarketConfig>(&scenario);
            let cap = test::take_from_sender<AdminCap>(&scenario);

            config::update_config(
                &mut config,
                &cap,
                200,  // new_min_bet
                2000000, // new_max_bet
                200,  // new_fee_percentage (2%)
                NEW_RECIPIENT,
                ctx(&mut scenario)
            );

            assert!(config::is_amount_valid(&config, 1000), 0);
            assert!(!config::is_amount_valid(&config, 100), 1);
            assert!(config::calculate_fee(&config, 10000) == 200, 2);
            assert!(config::fee_recipient(&config) == NEW_RECIPIENT, 3);

            test::return_to_sender(&scenario, cap);
            test::return_shared(config);
        };

        test::end(scenario);
    }

    #[test]
    fun test_token_management() {
        let scenario = test::begin(ADMIN);
        
        // 初始化配置
        next_tx(&mut scenario, ADMIN);
        {
            config::init_for_testing(ctx(&mut scenario));
        };

        // 在新的交易中管理代币
        next_tx(&mut scenario, ADMIN);
        {
            let config = test::take_shared<MarketConfig>(&scenario);
            let cap = test::take_from_sender<AdminCap>(&scenario);

            // 创建代币字符串
            let sui_token = string::utf8(b"SUI");
            let usdc_token = string::utf8(b"USDC");

            // 添加支持的代币
            config::add_supported_token(
                &mut config,
                &cap,
                sui_token
            );
            assert!(config::is_token_supported(&config, &sui_token), 0);
            assert!(!config::is_token_supported(&config, &usdc_token), 1);

            // 移除支持的代币
            config::remove_supported_token(
                &mut config,
                &cap,
                sui_token
            );
            assert!(!config::is_token_supported(&config, &sui_token), 2);

            test::return_to_sender(&scenario, cap);
            test::return_shared(config);
        };

        test::end(scenario);
    }

    #[test]
    fun test_pause_unpause() {
        let scenario = test::begin(ADMIN);
        
        // 初始化配置
        next_tx(&mut scenario, ADMIN);
        {
            config::init_for_testing(ctx(&mut scenario));
        };

        // 在新的交易中测试暂停/恢复
        next_tx(&mut scenario, ADMIN);
        {
            let config = test::take_shared<MarketConfig>(&scenario);
            let cap = test::take_from_sender<AdminCap>(&scenario);

            // 测试暂停
            config::set_paused(&mut config, &cap, true);
            assert!(config::is_paused(&config), 0);

            // 测试恢复
            config::set_paused(&mut config, &cap, false);
            assert!(!config::is_paused(&config), 1);

            test::return_to_sender(&scenario, cap);
            test::return_shared(config);
        };

        test::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = config::E_INVALID_FEE)]
    fun test_invalid_fee() {
        let scenario = test::begin(ADMIN);
        
        // 初始化配置
        next_tx(&mut scenario, ADMIN);
        {
            config::init_for_testing(ctx(&mut scenario));
        };

        // 在新的交易中测试无效费用
        next_tx(&mut scenario, ADMIN);
        {
            let config = test::take_shared<MarketConfig>(&scenario);
            let cap = test::take_from_sender<AdminCap>(&scenario);

            // 尝试设置超过10%的手续费
            config::update_config(
                &mut config,
                &cap,
                100,
                1000000,
                1100, // 11%
                NEW_RECIPIENT,
                ctx(&mut scenario)
            );

            test::return_to_sender(&scenario, cap);
            test::return_shared(config);
        };

        test::end(scenario);
    }
}