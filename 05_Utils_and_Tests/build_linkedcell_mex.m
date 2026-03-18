clc; clear;

% ============================================================
% 一键编译 Linked-Cell + Block-Hash 帧间跳跃 MEX (适配新版 MATLAB)
% ============================================================

cfg = coder.config('mex');
cfg.IntegrityChecks = false;
cfg.ResponsivenessChecks = false;
cfg.ExtrinsicCalls = false;

% ++ 更新：使用新版 MATLAB 推荐的动态内存分配语法
cfg.EnableDynamicMemoryAllocation = true;
cfg.DynamicMemoryAllocationThreshold = 64; % 阈值设低(64 bytes)，确保变长数组直接走动态内存分配

% GCC / MinGW 优化
cfg.PostCodeGenCommand = ...
    'buildInfo.addCompileFlags(''-O3 -march=native -ffast-math -fno-math-errno'');';

% ------------------------------------------------------------
% 输入类型定义
% ------------------------------------------------------------
% 扩大点数上限，防止高密度缺陷时爆内存
MAX_TOTAL_POINTS = 10000000; 
% 优化：将网格尺寸设为变长 (上限2000)，防止改变 L_block 后尺寸对不上导致崩溃
MAX_GRID_SIZE    = 2000;     

args_list = { ...
    0.0, ...                                                % 1. x0
    0.0, ...                                                % 2. y0
    coder.typeof(0.0, [MAX_TOTAL_POINTS, 1], [1 0]), ...    % 3. AllX (变长)
    coder.typeof(0.0, [MAX_TOTAL_POINTS, 1], [1 0]), ...    % 4. AllY (变长)
    coder.typeof(uint32(0), [MAX_GRID_SIZE, MAX_GRID_SIZE, 4], [1 1 0]), ... % 5. CellStart (前两维变长)
    coder.typeof(uint32(0), [MAX_GRID_SIZE, MAX_GRID_SIZE, 4], [1 1 0]), ... % 6. CellCount (前两维变长)
    coder.typeof(0.0, [1, 12], [0 0]), ...                  % 7. DataTrans (固定1x12)
    0.0, ...                                                % 8. TimeSeed
    0.0, ...                                                % 9. L_block
    0.0, ...                                                % 10. cell_size
    int32(0), ...                                           % 11. nx_i
    int32(0) ...                                            % 12. ny_i
};

fprintf('>>> 正在启动 Linked-Cell MEX 重新编译...\n');
codegen -config cfg Sub_JumpingBetweenEachFrame_LinkedCell -args args_list -report
fprintf('>>> 编译成功！新版 MEX 已支持导出真实吸附时间。\n');