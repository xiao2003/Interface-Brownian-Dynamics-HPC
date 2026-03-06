function [UN] = Sub_GenerateUniformWithMean(meanValue, range, N)
% 功能：生成具有指定数学期望的均匀分布随机数
% 输入：
%   meanValue - 均匀分布的数学期望（均值）
%   range - 分布的区间长度（即最大值与最小值的差值）
%   N - 生成的随机数数量
% 输出：
%   UN - 符合指定均值的均匀分布随机数数组（N×1矩阵）

    % 均匀分布的均值 = (a + b)/2，其中a为最小值，b为最大值
    % 由 range = b - a，可得 a = meanValue - range/2，b = meanValue + range/2
    a = meanValue - range / 2;  % 分布下界
    b = meanValue + range / 2;  % 分布上界
    
    % 生成[0,1)区间的均匀随机数，映射到[a,b]区间
    u = rand(N, 1);
    UN = a + (b - a) * u;
end