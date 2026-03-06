function [nbr_jumps,t_ads] = Sub_JumpingAnalysis(DL,N_MSD_MAX,Lmin)

% Lmin=150;


Number_TRACK = length(DL);
nbr_jumps = zeros(1,Number_TRACK);
t_ads = zeros(Number_TRACK,N_MSD_MAX);
t_ads(t_ads==0) = NaN;

    for li = (1 : Number_TRACK)
        int = find(DL(li,:)>Lmin); 
        nbr_jumps(li) = length(int); % number of jump in this trajectory
        
        if ~isempty(int)
            last_jp = 1;

            for jp = (1:length(int))
                
                next_jp = int(jp);
                t_ads(li,jp) = next_jp - last_jp; % adsorbed periods between jumps [frame]
                last_jp = next_jp;

            end

            next_jp = find(DL(li,:)>0,1,'last'); % find the last spot of the trajectory
            t_ads(li,jp+1) = next_jp - last_jp; % last adsorbed period before definitely leaving the surface 

        else
            t_ads(li,1) = 0;
        end
    end
    % 
    % 
    % 





end