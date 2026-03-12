% killall.m - 一键中止并行、清理内存、冷却 CPU
function killall()
    fprintf('>>> 正在强制中止所有并行任务...\n');
    
    % 1. 销毁并行池
    try
        poolObj = gcp('nocreate');
        if ~isempty(poolObj)
            delete(poolObj);
        end
    catch
    end
    
    % 2. 清理并行集群队列
    try
        c = parcluster('local');
        delete(c.Jobs);
    catch
    end
    
    % 3. 释放内存
    clear; 
    clear mex; % 释放 MEX 占用的内存句柄
    clear all; 
    
    % 4. 强制垃圾回收
    java.lang.System.gc();
    
    clc;
    fprintf('>>> 已清理完毕。冷却中...\n');
end