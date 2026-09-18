function compare(dataRateStr, payloadLen)
% Usage: 
%   compare('1Mbps', 0);
%   compare('250kbps', 50);
%   compare('all'); % Runs comparison across all lengths and rates

if nargin < 1, dataRateStr = 'all'; end

if strcmpi(dataRateStr, 'all')
    rates = {'1Mbps', '250kbps'};
    lengths = [0, 1, 50, 127];
    for r = 1:length(rates)
        for l = 1:length(lengths)
            run_single_compare(rates{r}, lengths(l));
        end
    end
else
    if nargin < 2, payloadLen = 0; end
    run_single_compare(dataRateStr, payloadLen);
end
end

function run_single_compare(dataRateStr, payloadLen)
% File paths matching generate_test_vectors.m and tb.sv outputs
rtl_real_path = sprintf('rtl_outputs/rtl_%s_len%03d_real.txt', dataRateStr, payloadLen);
rtl_imag_path = sprintf('rtl_outputs/rtl_%s_len%03d_imag.txt', dataRateStr, payloadLen);
mat_real_path = sprintf('test_vectors/mat_%s_len%03d_real.txt', dataRateStr, payloadLen);
mat_imag_path = sprintf('test_vectors/mat_%s_len%03d_imag.txt', dataRateStr, payloadLen);

% Verify files exist before loading
if ~exist(rtl_real_path, 'file') || ~exist(mat_real_path, 'file')
    fprintf('\n[SKIP] Missing files for Rate: %s, L = %d\n', dataRateStr, payloadLen);
    return;
end

% Load datasets
rtl_real = load(rtl_real_path);
rtl_imag = load(rtl_imag_path);
mat_real = load(mat_real_path);
mat_imag = load(mat_imag_path);

% Length verification
len_rtl = length(rtl_real);
len_mat = length(mat_real);
fprintf('\n====================================================\n');
fprintf(' Sample Length Check (%s, L = %d)\n', dataRateStr, payloadLen);
fprintf('====================================================\n');
fprintf('RTL Sample Count    : %d\n', len_rtl);
fprintf('MATLAB Sample Count : %d\n', len_mat);

if len_rtl < len_mat
    tail_r = mat_real(len_rtl+1:end);
    tail_i = mat_imag(len_rtl+1:end);
    if all(tail_r == 0) && all(tail_i == 0)
        fprintf('[INFO] %d trailing MATLAB samples are zero (preallocation pad) - OK\n', ...
                len_mat - len_rtl);
        rtl_real(end+1:len_mat) = 0;
        rtl_imag(end+1:len_mat) = 0;
    else
        error('RTL is short by %d samples and the MATLAB tail is NOT zero.', len_mat-len_rtl);
    end
elseif len_rtl > len_mat
    error('RTL produced MORE samples (%d) than MATLAB (%d).', len_rtl, len_mat);
end

% Error and MSE calculation
diff_real = rtl_real - mat_real;
diff_imag = rtl_imag - mat_imag;
err_cnt_real = sum(diff_real ~= 0);
err_cnt_imag = sum(diff_imag ~= 0);
%mse_real = mean(diff_real.^2);
%mse_imag = mean(diff_imag.^2);

fprintf('\n--- Comparison Results (%s, L = %d) ---\n', dataRateStr, payloadLen);
fprintf('Real Channel  - Mismatches: %d / %d \n', err_cnt_real, length(rtl_real));
fprintf('Imag Channel  - Mismatches: %d / %d \n', err_cnt_imag, length(rtl_imag));

if (err_cnt_real == 0) && (err_cnt_imag == 0)
    fprintf('[VERDICT: PASS] RTL output is BIT-EXACT with MATLAB stage 13!\n');
else
    fprintf('[VERDICT: FAIL] Output divergence detected between RTL and MATLAB.\n');
end
end

%Compare single run: compare('1Mbps', 0) or compare('250kbps', 127)
%Compare all generated test vectors at once: compare('all')