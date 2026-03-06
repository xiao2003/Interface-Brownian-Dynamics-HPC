function [PN] = Sub_GeneratePowerLawWithMean(alpha, meanValue, N)
% alpha - exponent of the power-law distribution
% meanValue - desired average value of the power-law distribution
% N - number of random numbers to generate

    % Calculate xmin based on the desired mean value
    xmin = meanValue * (alpha - 2) / (alpha - 1);

    % Step 2: Generate uniform random numbers
    u = rand(N, 1);
    
    % Step 3: Apply the inverse CDF to get power-law distributed numbers
    PN = xmin * (1 - u).^(1 / (1 - alpha));
end

