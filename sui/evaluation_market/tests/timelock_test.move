#[test_only]
module evaluation_market::timelock_tests {
    use sui::test_scenario::{Self as test, next_tx, ctx};
    use sui::clock::{Self, Clock};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use evaluation_market::timelock::{Self, TimeLock};
    use std::vector;

    // 测试常量
    const ADMIN: address = @0xAD;
    const USER: address = @0xB1;
    const TARGET: address = @0xB2;
    const HOUR_IN_MS: u64 = 3600000; // 1小时的毫秒数

    // 辅助函数：创建并设置时钟
    fun create_clock_at(timestamp_ms: u64, ctx: &mut TxContext): Clock {
        let clock = clock::create_for_testing(ctx);
        clock::set_for_testing(&mut clock, timestamp_ms);
        clock
    }

    #[test]
    fun test_create_timelock() {
        let scenario = test::begin(ADMIN);
        
        next_tx(&mut scenario, ADMIN);
        {
            let clk = create_clock_at(0, ctx(&mut scenario));
            let timelock = timelock::new(HOUR_IN_MS, ctx(&mut scenario));
            
            assert!(timelock::get_admin(&timelock) == ADMIN, 0);
            assert!(timelock::get_minimum_delay(&timelock) == HOUR_IN_MS, 1);
            assert!(timelock::operations_count(&timelock) == 0, 2);

            transfer::public_share_object(timelock);
            clock::share_for_testing(clk);
        };

        test::end(scenario);
    }

    #[test]
    fun test_schedule_and_execute_operation() {
        let scenario = test::begin(ADMIN);
        let start_time = 1000000;
        
        // 创建时间锁和时钟
        next_tx(&mut scenario, ADMIN);
        {
            let clk = create_clock_at(start_time, ctx(&mut scenario));
            let timelock = timelock::new(HOUR_IN_MS, ctx(&mut scenario));
            transfer::public_share_object(timelock);
            clock::share_for_testing(clk);
        };

        // 调度操作
        next_tx(&mut scenario, ADMIN);
        {
            let timelock = test::take_shared<TimeLock>(&scenario);
            let clk = test::take_shared<Clock>(&scenario);
            
            timelock::schedule_operation(
                &mut timelock,
                &clk,
                1, // OP_UPDATE_ADMIN
                TARGET,
                vector::empty(),
                ctx(&mut scenario)
            );

            assert!(!timelock::is_operation_ready(&timelock, &clk, 0), 0);

            test::return_shared(timelock);
            clock::share_for_testing(clk);
        };

        // 推进时间
        next_tx(&mut scenario, ADMIN);
        {
            let clk = test::take_shared<Clock>(&scenario);
            clock::set_for_testing(&mut clk, start_time + HOUR_IN_MS + 1);
            clock::share_for_testing(clk);
        };

        // 执行操作
        next_tx(&mut scenario, ADMIN);
        {
            let timelock = test::take_shared<TimeLock>(&scenario);
            let clk = test::take_shared<Clock>(&scenario);
            
            assert!(timelock::is_operation_ready(&timelock, &clk, 0), 1);
            
            let data = timelock::execute_operation(&mut timelock, &clk, 0, ctx(&mut scenario));
            assert!(vector::is_empty(&data), 2);

            let (_, _, _, executed) = timelock::get_operation(&timelock, 0);
            assert!(executed, 3);

            test::return_shared(timelock);
            clock::share_for_testing(clk);
        };

        test::end(scenario);
    }

    #[test]
    fun test_update_minimum_delay() {
        let scenario = test::begin(ADMIN);

        // 第一个事务：创建并共享 timelock 和 clock
        next_tx(&mut scenario, ADMIN);
        {
            let clk = create_clock_at(0, ctx(&mut scenario));  // 添加：创建时钟
            let timelock = timelock::new(100, ctx(&mut scenario));
            transfer::public_share_object(timelock);
            clock::share_for_testing(clk);  // 添加：共享时钟
        };

        // 第二个事务：更新最小延迟并调度操作
        next_tx(&mut scenario, ADMIN);
        {
            let timelock = test::take_shared<TimeLock>(&scenario);
            let clk = test::take_shared<Clock>(&scenario);
            
            // 更新最小延迟
            timelock::update_minimum_delay(&mut timelock, 200, ctx(&mut scenario));
            
            // 调度新操作，应该使用新的延迟时间
            timelock::schedule_operation(
                &mut timelock,
                &clk,
                1u8,
                TARGET,
                vector::empty<u8>(),
                ctx(&mut scenario)
            );

            test::return_shared(timelock);
            clock::share_for_testing(clk);
        };

        test::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = timelock::E_DELAY_TOO_SHORT)]
    fun test_invalid_minimum_delay() {
        let scenario = test::begin(ADMIN);
        
        next_tx(&mut scenario, ADMIN);
        {
            let timelock = timelock::new(100, ctx(&mut scenario));
            transfer::public_share_object(timelock);
        };

        next_tx(&mut scenario, ADMIN);
        {
            let timelock = test::take_shared<TimeLock>(&scenario);
            
            // 尝试设置为0，应该失败
            timelock::update_minimum_delay(&mut timelock, 0, ctx(&mut scenario));

            test::return_shared(timelock);
        };

        test::end(scenario);
    }

    #[test]
    #[expected_failure]
    fun test_unauthorized_schedule() {
        let scenario = test::begin(ADMIN);
        
        // 管理员创建时间锁
        next_tx(&mut scenario, ADMIN);
        {
            let timelock = timelock::new(100, ctx(&mut scenario));
            transfer::public_share_object(timelock);
        };

        // 非管理员尝试调度操作
        next_tx(&mut scenario, USER);
        {
            let timelock = test::take_shared<TimeLock>(&scenario);
            let clk = test::take_shared<Clock>(&scenario);
            timelock::schedule_operation(
                &mut timelock,
                &clk,
                1u8,
                TARGET,
                vector::empty<u8>(),
                ctx(&mut scenario)
            );

            test::return_shared(timelock);
            clock::share_for_testing(clk);
        };

        test::end(scenario);
    }

    #[test]
    fun test_multiple_operations() {
        let scenario = test::begin(ADMIN);
        let start_time = 1000000;
        
        next_tx(&mut scenario, ADMIN);
        {
            let clk = create_clock_at(start_time, ctx(&mut scenario));
            let timelock = timelock::new(HOUR_IN_MS, ctx(&mut scenario));
            transfer::public_share_object(timelock);
            clock::share_for_testing(clk);
        };

        next_tx(&mut scenario, ADMIN);
        {
            let timelock = test::take_shared<TimeLock>(&scenario);
            let clk = test::take_shared<Clock>(&scenario);
            
            // 调度多个操作
            timelock::schedule_operation(
                &mut timelock,
                &clk,
                1,
                TARGET,
                vector::empty(),
                ctx(&mut scenario)
            );

            timelock::schedule_operation(
                &mut timelock,
                &clk,
                2,
                TARGET,
                vector::empty(),
                ctx(&mut scenario)
            );

            test::return_shared(timelock);
            clock::share_for_testing(clk);
        };

        // 推进时间
        next_tx(&mut scenario, ADMIN);
        {
            let clk = test::take_shared<Clock>(&scenario);
            clock::set_for_testing(&mut clk, start_time + HOUR_IN_MS * 2);
            clock::share_for_testing(clk);
        };
        
        next_tx(&mut scenario, ADMIN);
        {
            let timelock = test::take_shared<TimeLock>(&scenario);
            let clk = test::take_shared<Clock>(&scenario);
            
            // 执行所有操作
            let data1 = timelock::execute_operation(&mut timelock, &clk, 0, ctx(&mut scenario));
            let data2 = timelock::execute_operation(&mut timelock, &clk, 1, ctx(&mut scenario));
            
            assert!(vector::is_empty(&data1), 0);
            assert!(vector::is_empty(&data2), 1);

            test::return_shared(timelock);
            clock::share_for_testing(clk);
        };

        test::end(scenario);
    }
} 