function [PN] = Sub_GeneratePowerLawWithMean(alpha, meanValue, N)
%#codegen
% alpha     - 幂指数 (主程序传入的 TI, 如 -2.5 或 -1.5)
% meanValue - 目标平均吸附时间 (tm_ads)
% N         - 生成的随机数个数
    
    alpha_val = -alpha; % 转换为正的幂指数 (例如 -1.5 -> 1.5)

    if alpha_val > 2.0
        % =======================================================
        % 正常长尾情况 (alpha > 2)
        % =======================================================
        % 均值收敛，使用经典公式推导最小下界 xmin
        xmin = meanValue * (alpha_val - 2.0) / (alpha_val - 1.0);
        
        u = rand(N, 1);
        % 经典逆变换采样 (积分上限至无穷大)
        PN = xmin * (1.0 - u).^(-1.0 / (alpha_val - 1.0));
        
    elseif alpha_val > 1.0 && alpha_val <= 2.0
        % =======================================================
        % 极端长尾情况 (1 < alpha <= 2) : 必须引入截断 (Truncation)
        % =======================================================
        t_max = 1000.0; % 物理截断上限 (你的仿真总时长 1000s)
        
        % [核心物理推导]: 为了保持你的顶层参数扫描有效，我们反推所需的极小下界 t_min。
        % 使得被 t_max 截断后的真实物理期望值，完美等于你输入的 meanValue。
        t_min = ( meanValue * ((2.0 - alpha_val)/(alpha_val - 1.0)) * (t_max^(alpha_val - 2.0)) ).^(1.0 / (alpha_val - 1.0));
        
        % 防御性极值限制 (防止极其极端的参数导致 t_min 失去物理意义)
        if t_min < 1e-12
            t_min = 1e-12;
        elseif t_min > meanValue
            t_min = meanValue;
        end
        
        u = rand(N, 1);
        
        % 截断幂律分布 (Truncated Power Law) 的严谨逆变换采样公式
        term1 = t_max^(1.0 - alpha_val);
        term2 = t_min^(1.0 - alpha_val);
        PN = (u .* (term1 - term2) + term2).^(1.0 / (1.0 - alpha_val));
        
    else
        % =======================================================
        % 特例保护 (alpha <= 1，完全没有物理均值意义)
        % =======================================================
        PN = meanValue * ones(N, 1);
    end
end