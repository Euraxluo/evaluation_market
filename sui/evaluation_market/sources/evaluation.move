module evaluation_market::evaluation {
    use std::string::{Self, String};
    use sui::object::{Self, UID};
    use std::vector;
    use sui::tx_context::{Self, TxContext};
    use sui::event;
    use sui::transfer;

    // 错误码
    const ENotCreator: u64 = 0;
    const ENotEvaluator: u64 = 1;
    const EInvalidRound: u64 = 2;
    const ERoundComplete: u64 = 3;
    const ERoundFullyScored: u64 = 4;
    const EInvalidScores: u64 = 5;

    // 常量
    const MAX_SCORE: u64 = 10;
    const MIN_SCORE: u64 = 0;
    const REQUIRED_EVALUATORS: u64 = 3;
    const DIMENSION_COUNT: u64 = 5;

    // 评估维度
    const REASONING: u64 = 0;      // 推理/逻辑能力
    const KNOWLEDGE: u64 = 1;      // 知识应用能力
    const OUTPUT: u64 = 2;         // 输出/表达质量
    const INTERACTION: u64 = 3;    // 交互/回应能力
    const INNOVATION: u64 = 4;     // 创新/创造能力

    // 评估记录
    struct Round has store {
        evaluator_scores: vector<vector<u64>>,  // 评估者 => 维度 => 分数
        total_scores: vector<u64>,              // 维度 => 总分
        evaluator_count: u64,                   // 已评分的评估者数量
        is_complete: bool,                      // 回合是否完成
        start_time: u64,                        // 回合开始时间
        end_time: u64                           // 回合结束时间
    }

    // 评估对象
    struct Evaluation has key, store {
        id: UID,
        subject: String,                        // 评估主题/对象
        version: String,                        // 版本信息
        start_time: u64,                        // 评估开始时间
        duration: u64,                          // 评估持续时间
        end_time: u64,                          // 评估结束时间
        current_round: u64,                     // 当前回合
        total_rounds: u64,                      // 总回合数
        is_active: bool,                        // 评估是否活跃
        creator: address,                       // 评估创建者
        market: address,                        // 市场地址
        evaluators: vector<address>,            // 评估者列表
        rounds: vector<Round>,                  // 回合信息
        final_scores: vector<u64>,              // 最终得分(按维度)
        has_result: bool                        // 是否有结果
    }

    // 事件定义
    struct EvaluationCreated has copy, drop {
        evaluation_id: address,
        subject: String,
        version: String,
        duration: u64,
        total_rounds: u64,
        evaluators: vector<address>
    }

    struct RoundStarted has copy, drop {
        evaluation_id: address,
        round_number: u64,
        start_time: u64
    }

    struct ScoreSubmitted has copy, drop {
        evaluation_id: address,
        round_number: u64,
        evaluator: address,
        scores: vector<u64>
    }

    // === 内部构造函数 ===

    // 创建新评估
    fun new_evaluation(
        subject: String,
        version: String,
        duration: u64,
        total_rounds: u64,
        creator: address,
        evaluators: vector<address>,
        ctx: &mut TxContext
    ): Evaluation {
        let start_time = tx_context::epoch(ctx);
        
        Evaluation {
            id: object::new(ctx),
            subject,
            version,
            start_time,
            duration,
            end_time: start_time + duration,
            current_round: 0,
            total_rounds,
            is_active: true,
            creator,
            market: @0x0,
            evaluators,
            rounds: vector::empty(),
            final_scores: vector::empty(),
            has_result: false
        }
    }

    // 创建新回合
    fun new_round(start_time: u64, end_time: u64): Round {
        let total_scores = vector::empty();
        let i = 0;
        while (i < DIMENSION_COUNT) {
            vector::push_back(&mut total_scores, 0);
            i = i + 1;
        };

        Round {
            evaluator_scores: vector::empty(),
            total_scores,
            evaluator_count: 0,
            is_complete: false,
            start_time,
            end_time
        }
    }

    // 验证分数
    public fun validate_scores(scores: &vector<u64>): bool {
        if (vector::length(scores) != DIMENSION_COUNT) {
            return false
        };

        let total = 0u64;
        let i = 0;
        while (i < DIMENSION_COUNT) {
            let score = *vector::borrow(scores, i);
            if (score > MAX_SCORE) {
                return false
            };
            total = total + score;
            i = i + 1;
        };

        total == MAX_SCORE
    }

    // === 公共函数 ===

    // 创建新评估
    public fun create_evaluation(
        subject: String,
        version: String,
        duration: u64,
        total_rounds: u64,
        evaluators: vector<address>,
        ctx: &mut TxContext
    ): Evaluation {
        let creator = tx_context::sender(ctx);
        let evaluation = new_evaluation(
            subject,
            version,
            duration,
            total_rounds,
            creator,
            evaluators,
            ctx
        );

        // 发出事件
        event::emit(EvaluationCreated {
            evaluation_id: object::uid_to_address(&evaluation.id),
            subject: evaluation.subject,
            version: evaluation.version,
            duration: evaluation.duration,
            total_rounds: evaluation.total_rounds,
            evaluators: evaluation.evaluators
        });

        evaluation
    }

    // 开始新回合
    public fun start_round(evaluation: &mut Evaluation, ctx: &TxContext) {
        let sender = tx_context::sender(ctx);
        assert!(sender == evaluation.creator, ENotCreator);

        let start_time = tx_context::epoch(ctx);
        let end_time = start_time + evaluation.duration;
        let round = new_round(start_time, end_time);
        vector::push_back(&mut evaluation.rounds, round);
        evaluation.current_round = evaluation.current_round + 1;

        event::emit(RoundStarted {
            evaluation_id: object::uid_to_address(&evaluation.id),
            round_number: evaluation.current_round,
            start_time
        });
    }

    // 提交评分
    public fun submit_scores(
        evaluation: &mut Evaluation,
        round_number: u64,
        scores: vector<u64>,
        ctx: &TxContext
    ) {
        let sender = tx_context::sender(ctx);
        
        // 验证评估者身份
        assert!(vector::contains(&evaluation.evaluators, &sender), ENotEvaluator);
        
        // 验证回合
        assert!(round_number == evaluation.current_round, EInvalidRound);
        let round = vector::borrow_mut(&mut evaluation.rounds, round_number - 1);
        assert!(!round.is_complete, ERoundComplete);
        assert!(round.evaluator_count < REQUIRED_EVALUATORS, ERoundFullyScored);

        // 验证分数
        assert!(validate_scores(&scores), EInvalidScores);

        // 记录分数
        let evaluator_scores = &mut round.evaluator_scores;
        vector::push_back(evaluator_scores, scores);

        // 更新总分
        let i = 0;
        while (i < DIMENSION_COUNT) {
            let score = *vector::borrow(&scores, i);
            if (vector::length(&round.total_scores) <= i) {
                vector::push_back(&mut round.total_scores, score);
            } else {
                let total = vector::borrow_mut(&mut round.total_scores, i);
                *total = *total + score;
            };
            i = i + 1;
        };

        // 更新评估者计数
        round.evaluator_count = round.evaluator_count + 1;

        // 检查回合是否完成
        if (round.evaluator_count == REQUIRED_EVALUATORS) {
            round.is_complete = true;
            if (evaluation.current_round < evaluation.total_rounds) {
                // 自动开始下一回合
                let start_time = tx_context::epoch(ctx);
                let end_time = start_time + evaluation.duration;
                let new_round = new_round(start_time, end_time);
                vector::push_back(&mut evaluation.rounds, new_round);
                evaluation.current_round = evaluation.current_round + 1;
            }
        };

        // 发出事件
        event::emit(ScoreSubmitted {
            evaluation_id: object::uid_to_address(&evaluation.id),
            round_number,
            evaluator: sender,
            scores
        });
    }

    // 完成评估
    public fun finalize_evaluation(evaluation: &mut Evaluation) {
        evaluation.is_active = false;
        evaluation.has_result = true;
        evaluation.final_scores = determine_final_scores(evaluation);
    }

    // === 内部函数 ===

    // 计算最终得分
    fun determine_final_scores(evaluation: &Evaluation): vector<u64> {
        let final_scores = vector::empty();
        let i = 0;
        
        // 初始化最终得分向量
        while (i < DIMENSION_COUNT) {
            vector::push_back(&mut final_scores, 0);
            i = i + 1;
        };

        // 计算所有完成回合的总分
        let round_idx = 0;
        while (round_idx < vector::length(&evaluation.rounds)) {
            let round = vector::borrow(&evaluation.rounds, round_idx);
            if (round.is_complete) {
                let score_idx = 0;
                while (score_idx < vector::length(&round.total_scores)) {
                    let current_total = vector::borrow_mut(&mut final_scores, score_idx);
                    *current_total = *current_total + *vector::borrow(&round.total_scores, score_idx);
                    score_idx = score_idx + 1;
                };
            };
            round_idx = round_idx + 1;
        };

        final_scores
    }

    // === 辅助函数 ===

    // 验证评估者
    fun is_evaluator(evaluation: &Evaluation, addr: address): bool {
        vector::contains(&evaluation.evaluators, &addr)
    }

    // 获取当前回合
    fun get_current_round(evaluation: &Evaluation): u64 {
        evaluation.current_round
    }

    // 获取回合总分
    fun get_round_scores(evaluation: &Evaluation, round_number: u64): vector<u64> {
        let round = vector::borrow(&evaluation.rounds, round_number - 1);
        round.total_scores
    }

    // === 测试函数 ===
    #[test_only]
    public fun create_test_evaluation(
        subject: String,
        version: String,
        duration: u64,
        total_rounds: u64,
        creator: address,
        evaluators: vector<address>,
        ctx: &mut TxContext
    ): Evaluation {
        new_evaluation(subject, version, duration, total_rounds, creator, evaluators, ctx)
    }

    #[test_only]
    public fun create_test_round(start_time: u64, end_time: u64): Round {
        new_round(start_time, end_time)
    }

    #[test_only]
    public fun destroy_test_round(round: Round) {
        let Round { 
            evaluator_scores, 
            total_scores, 
            evaluator_count: _, 
            is_complete: _, 
            start_time: _, 
            end_time: _ 
        } = round;
        
        while (!vector::is_empty(&evaluator_scores)) {
            let scores = vector::pop_back(&mut evaluator_scores);
            while (!vector::is_empty(&scores)) {
                vector::pop_back(&mut scores);
            };
            vector::destroy_empty(scores);
        };
        vector::destroy_empty(evaluator_scores);

        while (!vector::is_empty(&total_scores)) {
            vector::pop_back(&mut total_scores);
        };
        vector::destroy_empty(total_scores);
    }

    // === 测试辅助函数 ===
    #[test_only]
    public fun get_evaluation_fields(evaluation: &Evaluation): (u64, u64, bool, bool, u64, u64) {
        (
            evaluation.current_round,
            evaluation.total_rounds,
            evaluation.is_active,
            evaluation.has_result,
            vector::length(&evaluation.evaluators),
            vector::length(&evaluation.rounds)
        )
    }

    #[test_only]
    public fun get_round_fields(round: &Round): (u64, bool, u64, u64, u64, u64) {
        (
            round.evaluator_count,
            round.is_complete,
            round.start_time,
            round.end_time,
            vector::length(&round.evaluator_scores),
            vector::length(&round.total_scores)
        )
    }

    #[test_only]
    public fun get_evaluators(evaluation: &Evaluation): &vector<address> {
        &evaluation.evaluators
    }

    #[test_only]
    public fun get_rounds(evaluation: &Evaluation): &vector<Round> {
        &evaluation.rounds
    }

    #[test_only]
    public fun get_total_scores(round: &Round): &vector<u64> {
        &round.total_scores
    }

    #[test_only]
    /// 测试用的验证分数函数
    public fun validate_scores_test(scores: &vector<u64>): bool {
        validate_scores(scores)
    }
} 