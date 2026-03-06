DX = analysis_results.result_data(:,2);
DY = analysis_results.result_data(:,3);
DX(isnan(DX)) = 0;
DY(isnan(DY)) = 0;
sum(DX)
mean(nanmean(DX))
sum(DY)
mean(nanmean(DY))