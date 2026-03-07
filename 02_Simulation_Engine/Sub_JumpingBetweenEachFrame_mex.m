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
t_r = 0;

% 配置动态数组
coder.varsize('Xads', [1, Inf], [0, 1]);
coder.varsize('Yads', [1, Inf], [0, 1]);
Xads = zeros(1, 0); Yads = zeros(1, 0);

if isempty(Xd)
    Xads = NaN; Yads = NaN; t_r = max(0, tclock - t_tot);
    return;
end

% Linked-Cell：建立局部网格索引（9邻域搜索）
cell_size = max(2*adR, 2*k);
minX = min(Xd) - cell_size;
minY = min(Yd) - cell_size;
ix = floor((Xd - minX) / cell_size) + 1;
iy = floor((Yd - minY) / cell_size) + 1;
ny = max(iy) + 2;
key = ix * ny + iy;

[key_sorted, order] = sort(key);
Xs = Xd(order); Ys = Yd(order);
[dummy_u, ia] = unique(key_sorted, 'stable'); %#ok<ASGLU>
starts = ia;
ends = [ia(2:end)-1; numel(key_sorted)];
ukeys = key_sorted(ia);

if tclock < t_tot
    for i = 1:10000000
        % 自适应积分：远场大步长，近场高频细步长
        min_d_sq = nearest_dist_sq_9cell(xb, yb, Xs, Ys, minX, minY, cell_size, ny, ukeys, starts, ends);
        if isinf(min_d_sq) || min_d_sq > (8*adR)^2
            dt = 50 * tjmp;
        elseif min_d_sq > (4*adR)^2
            dt = 10 * tjmp;
        elseif min_d_sq > (2*adR)^2
            dt = 2 * tjmp;
        else
            dt = tjmp;
        end

        k_dt = k * sqrt(dt / tjmp);
        xe = xb + k_dt*randn + vx*dt;
        ye = yb + k_dt*randn + vy*dt;

        min_d_sq = nearest_dist_sq_9cell(xe, ye, Xs, Ys, minX, minY, cell_size, ny, ukeys, starts, ends);

        if min_d_sq < adR^2
            Xads = [Xads, xe]; Yads = [Yads, ye];
            switch DistMode
                case 1, t_ads = Sub_GeneratePowerLawWithMean(TI, tm_ads, 1);
                case 2, t_ads = Sub_GenerateExponentialWithMean(tm_ads, 1);
                case 3, t_ads = Sub_GenerateUniformWithMean(tm_ads, 2*TI, 1);
                otherwise, t_ads = 0;
            end
            tclock = tclock + t_ads + dt;
        else
            tclock = tclock + dt;
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

function min_d_sq = nearest_dist_sq_9cell(xp, yp, Xs, Ys, minX, minY, cell_size, ny, ukeys, starts, ends)
ixp = floor((xp - minX) / cell_size) + 1;
iyp = floor((yp - minY) / cell_size) + 1;
min_d_sq = inf;

for dix = -1:1
    for diy = -1:1
        key = (ixp + dix) * ny + (iyp + diy);
        pos = find(ukeys == key, 1);
        if ~isempty(pos)
            s = starts(pos); e = ends(pos);
            dx = xp - Xs(s:e);
            dy = yp - Ys(s:e);
            d2 = dx.^2 + dy.^2;
            local_min = min(d2);
            if local_min < min_d_sq
                min_d_sq = local_min;
            end
        end
    end
end
end
