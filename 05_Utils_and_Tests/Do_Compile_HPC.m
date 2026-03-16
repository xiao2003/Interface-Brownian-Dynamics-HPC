% 一键开启极限性能编译 (MinGW GCC 专版)
clc; clear;

% 1. 基础配置
cfg = coder.config('mex');
cfg.IntegrityChecks = false; 
cfg.ResponsivenessChecks = false; 
cfg.ExtrinsicCalls = false;

% 2. 纯净版指令注入
cfg.PostCodeGenCommand = 'buildInfo.addCompileFlags(''-O3 -march=native -ffast-math -fno-math-errno'');';

% 3. 定义精确的输入参数类型
args_list = { ...
    0.0, ...                                      % x0
    0.0, ...                                      % y0
    coder.typeof(0.0, [150, 100, 100, 4], [0 0 0 0]), ... % HashX
    coder.typeof(0.0, [150, 100, 100, 4], [0 0 0 0]), ... % HashY
    coder.typeof(0.0, [100, 100, 4], [0 0 0]), ...       % HashCount
    coder.typeof(0.0, [1, 12], [0 0]), ...               % DataTrans
    0.0 ...                                       % TimeSeed
};

% 4. 执行编译
fprintf('正在启动 IBD-HPC 指令级加速编译...\n');
codegen -config cfg Sub_JumpingBetweenEachFrame_mex -args args_list -report
fprintf('编译成功！\n');