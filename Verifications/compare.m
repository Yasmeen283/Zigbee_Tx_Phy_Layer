% =========================================================================
% IEEE 802.15.4 CSS PHY - RTL vs MATLAB Verification (L = 0)
% =========================================================================

clear; clc;

% --- File Paths ---
rtl_real_path = 'rtl_outputs/rtl_1Mbps_len  0_real.txt';
rtl_imag_path = 'rtl_outputs/rtl_1Mbps_len  0_imag.txt';

mat_real_path = 'test_vectors/payloadlength_0_vectors/13_TxOutput_fixed_real_1Mbps.txt'; 
mat_imag_path = 'test_vectors/payloadlength_0_vectors/13_TxOutput_fixed_imag_1Mbps.txt';

% --- Load Datasets ---
rtl_real = load(rtl_real_path);
rtl_imag = load(rtl_imag_path);
mat_real = load(mat_real_path);
mat_imag = load(mat_imag_path);

% --- Length Verification ---
len_rtl = length(rtl_real);
len_mat = length(mat_real);

fprintf('--- Sample Length Check ---\n');
fprintf('RTL Sample Count    : %d\n', len_rtl);
fprintf('MATLAB Sample Count : %d\n', len_mat);

if len_rtl ~= len_mat
    warning('Sample count mismatch! Truncating to shorter dataset for comparison.');
    min_len = min(len_rtl, len_mat);
    rtl_real = rtl_real(1:min_len);
    rtl_imag = rtl_imag(1:min_len);
    mat_real = mat_real(1:min_len);
    mat_imag = mat_imag(1:min_len);
end

% --- Difference & MSE Calculation ---
diff_real = rtl_real - mat_real;
diff_imag = rtl_imag - mat_imag;

err_cnt_real = sum(diff_real ~= 0);
err_cnt_imag = sum(diff_imag ~= 0);

mse_real = mean(diff_real.^2);
mse_imag = mean(diff_imag.^2);

% --- Report Results ---
fprintf('\n--- Comparison Results (L = 0) ---\n');
fprintf('Real Channel  - Mismatches: %d / %d | MSE: %.6f\n', err_cnt_real, length(rtl_real), mse_real);
fprintf('Imag Channel  - Mismatches: %d / %d | MSE: %.6f\n', err_cnt_imag, length(rtl_imag), mse_imag);

if (err_cnt_real == 0) && (err_cnt_imag == 0)
    fprintf('\n[VERDICT: PASS] RTL output is BIT-EXACT with MATLAB stage 13!\n');
elseif (mse_real <= 0.005) && (mse_imag <= 0.005)
    fprintf('\n[VERDICT: PASS] RTL output matches MATLAB stage 13 within acceptable MSE tolerance.\n');
else
    fprintf('\n[VERDICT: FAIL] Output divergence detected between RTL and MATLAB.\n');
end