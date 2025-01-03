module evaluation_market::timelock {
    use std::vector;
    use sui::object::{Self, UID};
    use sui::tx_context::{Self, TxContext};
    use sui::clock::{Self, Clock};
    use sui::event;

    // 错误码
    const E_OPERATION_NOT_READY: u64 = 1;
    const E_DELAY_TOO_SHORT: u64 = 2;
    const E_NOT_ADMIN: u64 = 3;
    const E_ALREADY_EXECUTED: u64 = 4;

    // 操作类型
    const OP_UPDATE_ADMIN: u8 = 1;
    const OP_UPDATE_PARAMS: u8 = 2;
    const OP_RESOLVE_MARKET: u8 = 3;

    // 时间锁结构
    struct TimeLock has key,store {
        id: UID,
        minimum_delay: u64,      // 最小延迟时间（毫秒）
        operations: vector<Operation>,
        admin: address
    }

    // 待执行的操作
    struct Operation has store {
        op_type: u8,
        target: address,
        data: vector<u8>,
        execution_time: u64,     // 时间戳（毫秒）
        executed: bool
    }

    // 操作调度事件
    struct OperationScheduled has copy, drop {
        op_type: u8,
        target: address,
        execution_time: u64
    }

    // 操作执行事件
    struct OperationExecuted has copy, drop {
        op_type: u8,
        target: address,
        execution_time: u64
    }

    // 创建时间锁
    public fun new(minimum_delay: u64, ctx: &mut TxContext): TimeLock {
        TimeLock {
            id: object::new(ctx),
            minimum_delay,
            operations: vector::empty(),
            admin: tx_context::sender(ctx)
        }
    }

    // 调度新操作
    public fun schedule_operation(
        timelock: &mut TimeLock,
        clock: &Clock,
        op_type: u8,
        target: address,
        data: vector<u8>,
        ctx: &TxContext
    ) {
        // 检查调用者是否为管理员
        assert!(tx_context::sender(ctx) == timelock.admin, E_NOT_ADMIN);
        
        // 计算执行时间
        let current_time = clock::timestamp_ms(clock);
        let execution_time = current_time + timelock.minimum_delay;

        // 创建新操作
        let operation = Operation {
            op_type,
            target,
            data,
            execution_time,
            executed: false
        };

        // 添加到操作列表
        vector::push_back(&mut timelock.operations, operation);

        // 发出事件
        event::emit(OperationScheduled {
            op_type,
            target,
            execution_time
        });
    }

    // 执行操作
    public fun execute_operation(
        timelock: &mut TimeLock,
        clock: &Clock,
        operation_index: u64,
        ctx: &TxContext
    ): vector<u8> {
        // 获取操作
        let operation = vector::borrow_mut(&mut timelock.operations, operation_index);
        
        // 检查时间锁
        let current_time = clock::timestamp_ms(clock);
        assert!(current_time >= operation.execution_time, E_OPERATION_NOT_READY);
        assert!(!operation.executed, E_ALREADY_EXECUTED);

        // 标记为已执行
        operation.executed = true;

        // 发出事件
        event::emit(OperationExecuted {
            op_type: operation.op_type,
            target: operation.target,
            execution_time: operation.execution_time
        });

        // 返回操作数据
        *&operation.data
    }

    // 更新最小延迟时间
    public fun update_minimum_delay(
        timelock: &mut TimeLock,
        new_delay: u64,
        ctx: &TxContext
    ) {
        assert!(tx_context::sender(ctx) == timelock.admin, E_NOT_ADMIN);
        assert!(new_delay > 0, E_DELAY_TOO_SHORT);
        timelock.minimum_delay = new_delay;
    }

    // === 查询函数 ===
    public fun get_minimum_delay(timelock: &TimeLock): u64 {
        timelock.minimum_delay
    }

    public fun get_admin(timelock: &TimeLock): address {
        timelock.admin
    }

    public fun get_operation(
        timelock: &TimeLock, 
        operation_index: u64
    ): (u8, address, u64, bool) {
        let operation = vector::borrow(&timelock.operations, operation_index);
        (
            operation.op_type,
            operation.target,
            operation.execution_time,
            operation.executed
        )
    }

    public fun is_operation_ready(
        timelock: &TimeLock,
        clock: &Clock,
        operation_index: u64
    ): bool {
        let operation = vector::borrow(&timelock.operations, operation_index);
        !operation.executed && clock::timestamp_ms(clock) >= operation.execution_time
    }

    public fun operations_count(timelock: &TimeLock): u64 {
        vector::length(&timelock.operations)
    }
}