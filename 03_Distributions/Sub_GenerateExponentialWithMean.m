function [EN] = Sub_GenerateExponentialWithMean(meanValue, N)
% 功能：生成具有指定数学期望的指数分布随机数
% 输入：
%   meanValue - 指数分布的数学期望（均值）
%   N - 生成的随机数数量
% 输出：
%   EN - 符合指定均值的指数分布随机数数组（N×1矩阵）

    % 指数分布的参数λ与均值的关系：λ = 1/meanValue
    lambda = 1 / meanValue;
    
    % 生成[0,1)区间的均匀随机数
    u = rand(N, 1);
    
    % 利用逆变换法生成指数分布随机数（指数分布CDF的逆函数）
    EN = -log(1 - u) / lambda;
end