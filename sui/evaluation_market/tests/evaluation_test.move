#[test_only]
module evaluation_market::evaluation_tests {
    use std::string;
    use std::vector;
    use sui::test_scenario::{Self as test, Scenario, next_tx, ctx};
    use sui::transfer;
    use evaluation_market::evaluation;

    // 测试常量
    const ADMIN: address = @0xAD;
    const EVALUATOR1: address = @0xB1;
    const EVALUATOR2: address = @0xB2;
    const EVALUATOR3: address = @0xB3;

    // 辅助函数：创建基本评估参数
    fun create_basic_evaluation_data(): (string::String, string::String, u64, u64, vector<address>) {
        let evaluators = vector::empty<address>();
        vector::push_back(&mut evaluators, EVALUATOR1);
        vector::push_back(&mut evaluators, EVALUATOR2);
        vector::push_back(&mut evaluators, EVALUATOR3);

        (
            string::utf8(b"GPT-4"),           // subject
            string::utf8(b"v1.0"),            // version
            1000,                             // duration
            3,                                // total_rounds
            evaluators                        // evaluators
        )
    }

    // 辅助函数：创建有效的评分向量
    fun create_valid_scores(): vector<u64> {
        let scores = vector::empty<u64>();
        vector::push_back(&mut scores, 2); // REASONING
        vector::push_back(&mut scores, 2); // KNOWLEDGE
        vector::push_back(&mut scores, 2); // OUTPUT
        vector::push_back(&mut scores, 2); // INTERACTION
        vector::push_back(&mut scores, 2); // INNOVATION
        // 总分 = 10 (MAX_SCORE)
        scores
    }

    // 测试：创建新评估
    #[test]
    fun test_new_evaluation() {
        let scenario = test::begin(ADMIN);
        let (subject, version, duration, total_rounds, evaluators) = create_basic_evaluation_data();

        next_tx(&mut scenario, ADMIN);
        {
            let evaluation = evaluation::create_evaluation(
                subject,
                version,
                duration,
                total_rounds,
                evaluators,
                ctx(&mut scenario)
            );

            // 验证评估基本属性
            let (current_round, total_rounds, is_active, has_result, evaluators_len, rounds_len) = 
                evaluation::get_evaluation_fields(&evaluation);

            assert!(current_round == 0, 0);
            assert!(total_rounds == 3, 1);
            assert!(is_active == true, 2);
            assert!(has_result == false, 3);
            assert!(evaluators_len == 3, 4);
            assert!(rounds_len == 0, 5);

            // 验证评估者列表
            let evaluators = evaluation::get_evaluators(&evaluation);
            assert!(vector::contains(evaluators, &EVALUATOR1), 6);
            assert!(vector::contains(evaluators, &EVALUATOR2), 7);
            assert!(vector::contains(evaluators, &EVALUATOR3), 8);

            transfer::public_transfer(evaluation, ADMIN);
        };

        test::end(scenario);
    }

    // 测试：创建新回合
    #[test]
    fun test_new_round() {
        let scenario = test::begin(ADMIN);
        
        next_tx(&mut scenario, ADMIN);
        {
            let start_time = 1000;
            let end_time = 2000;
            let round = evaluation::create_test_round(start_time, end_time);

            // 使用测试辅助函数获取字段值
            let (evaluator_count, is_complete, round_start_time, round_end_time, evaluator_scores_len, total_scores_len) = 
                evaluation::get_round_fields(&round);

            // 验证回合基本属性
            assert!(evaluator_count == 0, 0);
            assert!(is_complete == false, 1);
            assert!(round_start_time == start_time, 2);
            assert!(round_end_time == end_time, 3);
            assert!(evaluator_scores_len == 0, 4);
            assert!(total_scores_len == 5, 5); // DIMENSION_COUNT = 5

            // 验证总分初始化为0
            let total_scores = evaluation::get_total_scores(&round);
            let i = 0;
            while (i < 5) {
                assert!(*vector::borrow(total_scores, i) == 0, 6);
                i = i + 1;
            };

            // 使用辅助函数销毁Round对象
            evaluation::destroy_test_round(round);
        };

        test::end(scenario);
    }

    // 测试：验证分数
    #[test]
    fun test_validate_scores() {
        // 测试有效分数
        {
            let valid_scores = create_valid_scores();
            assert!(evaluation::validate_scores_test(&valid_scores), 0);
            while (!vector::is_empty(&valid_scores)) {
                vector::pop_back(&mut valid_scores);
            };
            vector::destroy_empty(valid_scores);
        };

        // 测试维度数量错误
        {
            let invalid_scores = vector::empty<u64>();
            vector::push_back(&mut invalid_scores, 5);
            vector::push_back(&mut invalid_scores, 5);
            assert!(!evaluation::validate_scores_test(&invalid_scores), 1);
            while (!vector::is_empty(&invalid_scores)) {
                vector::pop_back(&mut invalid_scores);
            };
            vector::destroy_empty(invalid_scores);
        };

        // 测试分数超出范围
        {
            let invalid_scores = vector::empty<u64>();
            vector::push_back(&mut invalid_scores, 11); // > MAX_SCORE
            vector::push_back(&mut invalid_scores, 2);
            vector::push_back(&mut invalid_scores, 2);
            vector::push_back(&mut invalid_scores, 2);
            vector::push_back(&mut invalid_scores, 2);
            assert!(!evaluation::validate_scores_test(&invalid_scores), 2);
            while (!vector::is_empty(&invalid_scores)) {
                vector::pop_back(&mut invalid_scores);
            };
            vector::destroy_empty(invalid_scores);
        };

        // 测试总分不等于MAX_SCORE
        {
            let invalid_scores = vector::empty<u64>();
            vector::push_back(&mut invalid_scores, 1);
            vector::push_back(&mut invalid_scores, 1);
            vector::push_back(&mut invalid_scores, 1);
            vector::push_back(&mut invalid_scores, 1);
            vector::push_back(&mut invalid_scores, 1);
            assert!(!evaluation::validate_scores_test(&invalid_scores), 3);
            while (!vector::is_empty(&invalid_scores)) {
                vector::pop_back(&mut invalid_scores);
            };
            vector::destroy_empty(invalid_scores);
        };
    }

    // 测试：评估者验证
    #[test]
    fun test_evaluators_validation() {
        let scenario = test::begin(ADMIN);
        let (subject, version, duration, total_rounds, evaluators) = create_basic_evaluation_data();

        next_tx(&mut scenario, ADMIN);
        {
            let evaluation = evaluation::create_test_evaluation(
                subject,
                version,
                duration,
                total_rounds,
                ADMIN,
                evaluators,
                ctx(&mut scenario)
            );

            // 验证评估者列表
            let evaluators = evaluation::get_evaluators(&evaluation);
            assert!(vector::contains(evaluators, &EVALUATOR1), 0);
            assert!(vector::contains(evaluators, &EVALUATOR2), 1);
            assert!(vector::contains(evaluators, &EVALUATOR3), 2);
            assert!(!vector::contains(evaluators, &ADMIN), 3);

            transfer::public_transfer(evaluation, ADMIN);
        };

        test::end(scenario);
    }

    // 测试：提交评分
    #[test]
    fun test_submit_scores() {
        let scenario = test::begin(ADMIN);
        let (subject, version, duration, total_rounds, evaluators) = create_basic_evaluation_data();

        // 创建评估
        next_tx(&mut scenario, ADMIN);
        {
            let evaluation = evaluation::create_evaluation(
                subject,
                version,
                duration,
                total_rounds,
                evaluators,
                ctx(&mut scenario)
            );
            
            // 开始新回合
            evaluation::start_round(&mut evaluation, ctx(&mut scenario));

            // 评估者提交评分
            let scores = create_valid_scores();
            next_tx(&mut scenario, EVALUATOR1);
            evaluation::submit_scores(
                &mut evaluation,
                1,
                scores,
                ctx(&mut scenario)
            );

            // 验证评分
            let (evaluator_count, is_complete, _, _, _, _) = 
                evaluation::get_round_fields(vector::borrow(evaluation::get_rounds(&evaluation), 0));
            
            assert!(evaluator_count == 1, 0);
            assert!(!is_complete, 1);

            transfer::public_transfer(evaluation, ADMIN);
        };

        test::end(scenario);
    }

    // 测试：完整评估流程
    #[test]
    fun test_complete_evaluation() {
        let scenario = test::begin(ADMIN);
        let (subject, version, duration, total_rounds, evaluators) = create_basic_evaluation_data();

        // 创建评估
        next_tx(&mut scenario, ADMIN);
        {
            let evaluation = evaluation::create_evaluation(
                subject,
                version,
                duration,
                total_rounds,
                evaluators,
                ctx(&mut scenario)
            );

            // 开始第一回合
            evaluation::start_round(&mut evaluation, ctx(&mut scenario));

            // 所有评估者提交评分
            let scores = create_valid_scores();

            // EVALUATOR1 提交
            next_tx(&mut scenario, EVALUATOR1);
            evaluation::submit_scores(&mut evaluation, 1, scores, ctx(&mut scenario));

            // EVALUATOR2 提交
            next_tx(&mut scenario, EVALUATOR2);
            evaluation::submit_scores(&mut evaluation, 1, scores, ctx(&mut scenario));

            // EVALUATOR3 提交
            next_tx(&mut scenario, EVALUATOR3);
            evaluation::submit_scores(&mut evaluation, 1, scores, ctx(&mut scenario));

            // 验证回合完成并自动开始新回合
            let (current_round, _, _, _, _, rounds_len) = evaluation::get_evaluation_fields(&evaluation);
            assert!(current_round == 2, 0); // 当前回合应该是2
            assert!(rounds_len == 2, 1);    // 应该有两个回合（一个完成，一个新开始）

            // 验证第一个回合的状态
            let (evaluator_count, is_complete, _, _, _, _) = 
                evaluation::get_round_fields(vector::borrow(evaluation::get_rounds(&evaluation), 0));
            assert!(evaluator_count == 3, 2);
            assert!(is_complete, 3);

            transfer::public_transfer(evaluation, ADMIN);
        };

        test::end(scenario);
    }
}