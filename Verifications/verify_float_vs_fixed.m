
clear; clc; close all;

addpath('common');
addpath('transmitter');
global chirpIndex;
chirpIndex = 1;

globalSettings();
global samplingFreqMhz;
global TxDACbitNumber;


% DAC Scale Factor (e.g., 2^(5-1) - 1 = 15)
dac_scale = (2^(TxDACbitNumber - 1) - 1);

% Generate reference chirp sequences
chirpSeq_float = chirpSequenceGenerator(chirpIndex, samplingFreqMhz);
chirpSeq_fixed = floor(chirpSeq_float * dac_scale);

rates = [0, 1];            % 0 = 1 Mbps, 1 = 250 kbps
lengths = [0, 1, 50, 127]; % Payload lengths

fprintf('=====================================================================\n');
fprintf(' STAGE 1 VERIFICATION: Floating-Point vs. Fixed-Point Model (MSE <= 0.005)\n');
fprintf('=====================================================================\n\n');

all_pass = true;

mse_results = [];
labels = {};
for r = rates
    rate_str = ternary(r == 0, '1Mbps', '250kbps');
    
    for L = lengths
        % --- Build Payload Bitstream ---
        if L == 0
            incomingStream = [];
        else
            payload_bytes = uint8(mod(0:L-1, 256));
            bits_mat = zeros(L, 8);
            for b = 1:8
                bits_mat(:, b) = bitget(payload_bytes(:), b);
            end
            incomingStream = reshape(bits_mat', 1, []);
        end
        
        % --- Run Floating-Point Model (Scaled to DAC Range) ---
        Tx_float_raw = ChirpSpreadSpectrum_Tx(incomingStream, r, chirpSeq_float);
        Tx_float = Tx_float_raw * dac_scale;
        
        % --- Run Fixed-Point Model ---
        Tx_fixed = ChirpSpreadSpectrum_Tx(incomingStream, r, chirpSeq_fixed);
        
        % --- Compute IEEE Normalized MSE ---
        sig_diff = double(Tx_float) - double(Tx_fixed);
        numerator = sum(abs(sig_diff).^2);
        denominator = sum(abs(double(Tx_float)).^2);
        
        if denominator == 0
            mse = 0;
        else
            mse = numerator / denominator;
        end
        mse_results(end+1) = mse;
        labels{end+1} = sprintf('%s L=%d', rate_str, L);
        % --- Acceptance Criterion (MSE <= 0.005) ---
        status = 'PASS';
        if mse > 0.005
            status = 'FAIL';
            all_pass = false;
        end
        
        fprintf('Rate: %-7s | L = %3d | Samples: %6d | Normalized MSE: %.6f [%s]\n', ...
                rate_str, L, length(Tx_float), mse, status);
    end
end

figure;
bar(mse_results);
hold on;
yline(0.005, 'r--', 'LineWidth', 1.5);
set(gca, 'XTickLabel', labels, 'XTick', 1:length(labels));
xtickangle(45);
ylabel('Normalized MSE');
title('Stage 1: Fixed-Point vs. Floating-Point MSE per Test Case');
legend('MSE', 'Threshold = 0.005', 'Location', 'best');
grid on;
saveas(gcf, 'stage1_mse_report.png');
fprintf('\nPlot saved to stage1_mse_report.png\n');

fprintf('\n---------------------------------------------------------------------\n');
if all_pass
    fprintf('OVERALL STAGE 1 VERDICT: PASS (Fixed-point model satisfies IEEE MSE bound <= 0.005)\n');
else
    fprintf('OVERALL STAGE 1 VERDICT: FAIL (MSE exceeds standard threshold of 0.005)\n');
end
fprintf('---------------------------------------------------------------------\n');

function val = ternary(cond, val_true, val_false)
    if cond, val = val_true; else, val = val_false; end
end
