% =========================================================================
% IEEE 802.15.4 CSS PHY - Chirp Quantizer Resolution Sweep (Section 3.3)
%
% Purpose: justify the internal word-length (R) choice for the chirp
% sequence generator by sweeping R = 2..8 bits and computing the MSE
% between the exact (floating-point) chirp and the fixed-point
% (quantized) chirp, per the formula in the reference document:
%
%   MSE(R) = sum(|exact - fixed(R)|.^2) / sum(|exact|.^2)   over N = 152
%
% This is INDEPENDENT of the RTL / Verilog verification. It only compares
% two MATLAB models (floating-point vs fixed-point), and is what
% justifies the choice of R (the doc's own reference design picked R=5).
% =========================================================================
clear; clc; close all;
addpath('common');
addpath('transmitter');

globalSettings();
global samplingFreqMhz;

chirpIndex = 1; % pick any one of the 4 chirp sequences (m = 1..4); doc uses N=152 samples of one full sequence

% --- Exact (floating-point) reference chirp ---
exactChirp = chirpSequenceGenerator(chirpIndex, samplingFreqMhz); % complex, length 152, |value| <= 1 (unquantized)

N = length(exactChirp);
if N ~= 152
    warning('Expected 152 samples per chirp sequence, got %d. Continuing anyway.', N);
end

R_values = 2:8;
mse_values = zeros(size(R_values));

fprintf('====================================================\n');
fprintf(' Chirp Quantizer Resolution Sweep (Section 3.3)\n');
fprintf('====================================================\n');
fprintf(' R (bits) |     MSE      | Pass (<=0.005)?\n');
fprintf('----------------------------------------------------\n');

for k = 1:length(R_values)
    R = R_values(k);

    % Quantize to R bits: same style of quantization as TxDACbitNumber
    % elsewhere in the model (round toward nearest integer, scale by
    % full-scale for R-bit signed representation, then rescale back to
    % the same numeric range as exactChirp so the MSE is apples-to-apples).
    fullScale = 2^(R - 1) - 1;
    fixedChirp_int = round(exactChirp * fullScale); % quantized integer codes (real+imag rounded independently)
    fixedChirp = fixedChirp_int / fullScale;        % rescaled back to compare against exactChirp

    num = sum(abs(exactChirp - fixedChirp).^2);
    den = sum(abs(exactChirp).^2);
    mse_values(k) = num / den;

    passStr = ternary(mse_values(k) <= 0.005, 'YES', 'no');
    fprintf('    %2d    |  %8.6f  |   %s\n', R, mse_values(k), passStr);
end

fprintf('====================================================\n');

% --- Plot MSE vs R with the 0.005 threshold line ---
figure;
semilogy(R_values, mse_values, '-o', 'LineWidth', 1.5, 'MarkerSize', 6);
hold on;
yline(0.005, 'r--', 'LineWidth', 1.5, 'Label', 'MSE threshold = 0.005');
xlabel('Quantizer resolution R (bits)');
ylabel('MSE (log scale)');
title('Chirp Sequence Quantization Error vs. Resolution');
grid on;

% --- Report the minimum R that satisfies the threshold ---
passIdx = find(mse_values <= 0.005, 1, 'first');
if ~isempty(passIdx)
    fprintf('\nMinimum R satisfying MSE <= 0.005: R = %d bits (MSE = %.6f)\n', ...
        R_values(passIdx), mse_values(passIdx));
else
    fprintf('\nNo tested R value satisfies the MSE <= 0.005 threshold. Extend the sweep range.\n');
end

saveas(gcf, 'chirp_resolution_sweep.png');
fprintf('Plot saved to chirp_resolution_sweep.png\n');

function val = ternary(cond, val_true, val_false)
    if cond, val = val_true; else, val = val_false; end
end