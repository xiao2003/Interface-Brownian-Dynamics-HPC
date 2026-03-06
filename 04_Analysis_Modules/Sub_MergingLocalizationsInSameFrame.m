function [positionlist] = Sub_MergingLocalizationsInSameFrame(PL)
% This function is to merge all the localizations on the same frame

m = max(PL(:,3));

X = []; Y = []; Frame = [];

for i = 1:m
    [m1,n1] = find(PL(:,3) == i);

    if isempty(m1)
        continue
    else
        X(i) = mean(PL(m1,1));Y(i) = mean(PL(m1,2));Frame(i) = mean(PL(m1,3));

        sprintf('%f %% localizations Merged',round(i/m*100))

        % X = [X;xavg]; Y = [Y;yavg]; Frame = [Frame;Favg];

    end
end


clear positionlist;
positionlist(:,1) = X';      % In nm
positionlist(:,2) = Y';      % In nm
positionlist(:,3) = Frame';      % Frame



end