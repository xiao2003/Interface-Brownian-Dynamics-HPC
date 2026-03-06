function [time_diff, fmt_str] = seconds2remainingtime(prev_time,delta,i)
    % 类型强制转换+非数值校验，确保参与运算的是数值
    curr_time = double(now());                  
    time_diff = double((curr_time - prev_time) * 86400);  
    delta = double(delta);
    % 处理除零/非数值异常，避免报错
    if delta == 0 || isnan(delta) || isnan(time_diff) || time_diff == 0
        time_diff = 0;
    else
        time_diff = (100-delta) / (delta / time_diff);
    end
    % 格式化输出：时:分:秒.毫秒
    hours = floor(time_diff/3600);
    mins = floor(mod(time_diff,3600)/60);
    secs = mod(time_diff,60);
    fmt_str = sprintf('预计仍需耗时：%02d:%02d:%06.3f', hours, mins, secs);
    sprintf('%.3f %% trajectories generated and tracked for the %d th trajectory\n%s',delta,i,fmt_str)
end