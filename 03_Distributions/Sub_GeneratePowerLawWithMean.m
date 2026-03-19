function [PN] = Sub_GeneratePowerLawWithMean(alpha, meanValue, N)
%#codegen
% alpha - exponent of the power-law distribution
% meanValue - desired average value of the power-law distribution
% N - number of random numbers to generate
    
    alpha_val = -alpha; 

    if alpha_val > 2.0
        % =======================================================
        % 1. 针对 TI-2.5 (即传入 alpha=-2.5，alpha_val=2.5)
        % 经典长尾分布，积分收敛
        % =======================================================
        xmin = meanValue * (alpha_val - 2.0) / (alpha_val - 1.0);
        u = rand(N, 1);
        PN = xmin * (1.0 - u).^(-1.0 / (alpha_val - 1.0));
        
    elseif alpha_val > 1.0 && alpha_val <= 2.0
        % =======================================================
        % 2. 针对 TI-1.5 (即传入 alpha=-1.5, alpha_val=1.5)
        % 极度长尾分布，必须引入物理截断上限 (1000s)
        % =======================================================
        t_max = 1000.0; 
        t_min = ( meanValue * ((2.0 - alpha_val)/(alpha_val - 1.0)) * (t_max^(alpha_val - 2.0)) ).^(1.0 / (alpha_val - 1.0));
        
        if t_min < 1e-12, t_min = 1e-12; end
        if t_min > meanValue, t_min = meanValue; end
        
        u = rand(N, 1);
        term1 = t_max^(1.0 - alpha_val);
        term2 = t_min^(1.0 - alpha_val);
        PN = (u .* (term1 - term2) + term2).^(1.0 / (1.0 - alpha_val));
        
    else
        % =======================================================
        % 3. 针对 TI2.5 (即传入 alpha=2.5, alpha_val=-2.5)
        % 短尾/加速分布，最大值收敛于 xmin
        % =======================================================
        xmin = meanValue * (alpha_val - 2.0) / (alpha_val - 1.0);
        u = rand(N, 1);
        PN = xmin * (1.0 - u).^(1.0 / (1.0 - alpha_val));
    end
end