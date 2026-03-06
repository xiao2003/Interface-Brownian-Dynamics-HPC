% 保存MATLAB命令行所有历史记录到文本文件
% 功能: 提取并保存MATLAB命令历史记录

function savacommandhistory(file_name)

    %% 1. 获取命令历史记录
    % 获取完整的命令历史记录，返回cell数组格式
    history_cells = commandhistory;
    
    %% 2. 数据清洗和格式整理
    % 去除空行和无效记录
    clean_history = {};
    for i = 1:length(history_cells)
        % 去除字符串两端的空白字符
        current_line = strtrim(history_cells{i});
        % 只保留非空的有效记录
        if ~isempty(current_line)
            clean_history{end+1} = current_line;
        end
    end
    
    %% 3. 保存到文件
    % 定义保存路径和文件名（可根据需要修改）
    save_filename = 'commandhistory' + file_name;
    save_path = fullfile(pwd, save_filename); % 保存到当前工作目录
    
    % 打开文件并写入内容
    fid = fopen(save_path, 'w', 'n', 'UTF-8'); % 使用UTF-8编码确保中文正常显示
    if fid == -1
        error('无法创建文件，请检查路径权限！');
    end
    
    % 逐行写入历史记录，每行末尾添加换行符
    for i = 1:length(clean_history)
        fprintf(fid, '%s\n', clean_history{i});
    end
    
    % 关闭文件
    fclose(fid);
    
    %% 4. 提示信息
    fprintf('命令历史记录已成功保存！\n');
    fprintf('保存路径: %s\n', save_path);
    fprintf('共保存 %d 条有效命令记录\n', length(clean_history));
    
    % 可选：显示前5条记录预览
    if length(clean_history) > 0
        fprintf('\n=== 记录预览（前5条）===\n');
        preview_num = min(5, length(clean_history));
        for i = 1:preview_num
            fprintf('%d: %s\n', i, clean_history{i});
        end
    end
end