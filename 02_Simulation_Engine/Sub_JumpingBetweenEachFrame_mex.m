function [xe, ye, Xads, Yads, t_r] = Sub_JumpingBetweenEachFrame_mex(x0, y0, XYd, DataTrans)
%#codegen
% 参数解包
t_tot = DataTrans(1); TI = DataTrans(2); t_a = DataTrans(3);        
tm_ads = DataTrans(4); k = DataTrans(5); jf = DataTrans(6);         
adR = DataTrans(7); vx = DataTrans(10); vy = DataTrans(11); 
DistMode = DataTrans(12);

% 初始化
Xd = XYd(:,1); Yd = XYd(:,2);
tjmp = 1/jf; tclock = t_a; xe = x0; ye = y0; xb = x0; yb = y0;
t_r = 0; % 必须初始化防止报错

% 配置动态数组
coder.varsize('Xads', [1, Inf], [0, 1]);
coder.varsize('Yads', [1, Inf], [0, 1]);
Xads = zeros(1, 0); Yads = zeros(1, 0); 

% 局部缺陷点筛选 (优化搜索性能，固定搜索半径 8000nm)
Dis_init = (x0 - Xd).^2 + (y0 - Yd).^2;
XdN = Xd(Dis_init < 8000^2); 
YdN = Yd(Dis_init < 8000^2); 

if tclock < t_tot
    for i = 1:10000000 % 限制最大步数保护
        xe = xb + k*randn + vx*tjmp;
        ye = yb + k*randn + vy*tjmp;
        
        dist_sq = (xe - XdN).^2 + (ye - YdN).^2;
        [min_d, ~] = min(dist_sq);
        
        if min_d < adR^2
            Xads = [Xads, xe]; Yads = [Yads, ye];
            switch DistMode
                case 1, t_ads = Sub_GeneratePowerLawWithMean(TI, tm_ads, 1);
                case 2, t_ads = Sub_GenerateExponentialWithMean(tm_ads, 1); 
                case 3, t_ads = Sub_GenerateUniformWithMean(tm_ads, 2*TI, 1);    
                otherwise, t_ads = 0;
            end
            tclock = tclock + t_ads + tjmp;
        else
            tclock = tclock + tjmp;
        end
        xb = xe; yb = ye;
        if tclock >= t_tot
            t_r = tclock - t_tot;
            break;
        end
    end
    if isempty(Xads), Xads = NaN; Yads = NaN; end
else
    t_r = tclock - t_tot;
    Xads = xe; Yads = ye;
end
end